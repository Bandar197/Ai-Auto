"""UDS (ISO 14229) extended diagnostics over an ELM327, for non-powertrain modules.

Generic OBD-II (services 01/03/07/0A) only reaches the emissions/powertrain ECU.
Airbag (SRS), ABS, BCM and similar modules answer on *manufacturer-specific* CAN
addresses using UDS services:

* ``0x19 0x02`` reportDTCByStatusMask  → read stored/confirmed fault codes
* ``0x14``       clearDiagnosticInformation → clear a module's stored codes

The ELM327 is only a CAN gateway: we point it at a module with ATSH (request
header) + ATCRA (receive filter), then send the UDS request as hex. This file
holds the *pure* request builders and response parsers (fully unit-tested) plus a
thin async driver. Which module lives at which address is per-vehicle data that
must be captured and validated on a real car — never guessed — so addresses are
supplied by the caller (see ``UdsModule``), not hard-coded here.

Safety: reading is informational. Clearing goes through the same server-approved
authorisation as service 04 (``ClearAuthorization``); the AutoMind Control policy
additionally gates SRS clearing (refused while a fault is active, repair must be
confirmed, certified device + validated pack). Crash/deployment data is never
touched — this module only ever sends 0x19 (read) and 0x14 (clear codes).
"""

from __future__ import annotations

import contextlib
from dataclasses import dataclass, field

from .dtc import decode_dtc

# UDS service IDs we use (and only these).
SID_READ_DTC = 0x19
SID_CLEAR_DTC = 0x14
SUBFN_BY_STATUS_MASK = 0x02
POSITIVE_OFFSET = 0x40
NEGATIVE_RESPONSE = 0x7F

# status-of-DTC bit meanings (ISO 14229-1 Annex D).
_STATUS_BITS = {
    0: "test_failed",
    1: "test_failed_this_cycle",
    2: "pending",
    3: "confirmed",
    4: "test_not_completed_since_clear",
    5: "test_failed_since_clear",
    6: "test_not_completed_this_cycle",
    7: "warning_indicator",
}

# ISO 14229-1 negative response codes we surface by name.
_NRC = {
    0x10: "general_reject",
    0x11: "service_not_supported",
    0x12: "subfunction_not_supported",
    0x13: "incorrect_length_or_format",
    0x22: "conditions_not_correct",
    0x31: "request_out_of_range",
    0x33: "security_access_denied",
    0x7F: "service_not_supported_in_active_session",
}


@dataclass(frozen=True)
class UdsModule:
    """A diagnostic module addressed over UDS. Addresses are per-vehicle data."""

    key: str  # e.g. "srs", "abs", "bcm"
    name_en: str
    name_ar: str
    request_id: int  # CAN id we send to (ATSH), e.g. 0x7E0 or a maker SRS id
    response_id: int  # CAN id it answers on (ATCRA)
    id_bits: int = 11  # 11 or 29
    safety_category: str = "other"  # "airbag" | "abs" | "other" — drives policy gating

    def __post_init__(self) -> None:
        if self.id_bits not in (11, 29):
            raise ValueError("id_bits must be 11 or 29")
        for v in (self.request_id, self.response_id):
            if v < 0 or v > (0x1FFFFFFF if self.id_bits == 29 else 0x7FF):
                raise ValueError(f"CAN id out of range for {self.id_bits}-bit: {v:#x}")


@dataclass(frozen=True)
class UdsDtc:
    code: str  # standard 5-char code, e.g. "B0051"
    ftb: int  # failure type byte (3rd DTC byte); 0 when the ECU reports 2-byte codes
    status: int  # raw status-of-DTC byte
    flags: tuple[str, ...]  # decoded status bit names

    @property
    def display(self) -> str:
        return f"{self.code}-{self.ftb:02X}" if self.ftb else self.code

    @property
    def confirmed(self) -> bool:
        return "confirmed" in self.flags

    @property
    def active(self) -> bool:
        """The module reports the fault as failing now (drives the SRS active-fault gate)."""
        return "test_failed" in self.flags


class UdsError(Exception):
    """A UDS negative response or malformed answer."""

    def __init__(self, code: str, detail: str = "", *, service: int | None = None, nrc: int | None = None):
        super().__init__(detail or code)
        self.code = code
        self.detail = detail
        self.service = service
        self.nrc = nrc


# --------------------------------------------------------------------------- pure request builders
def build_read_dtc_request(status_mask: int = 0xFF) -> str:
    """UDS 0x19 0x02 <statusMask> — report DTCs matching the status mask."""
    if not 0 <= status_mask <= 0xFF:
        raise ValueError("status_mask must be a byte")
    return f"{SID_READ_DTC:02X}{SUBFN_BY_STATUS_MASK:02X}{status_mask:02X}"


def build_clear_request(group: int = 0xFFFFFF) -> str:
    """UDS 0x14 <groupOfDTC> — clear stored codes (0xFFFFFF = all groups)."""
    if not 0 <= group <= 0xFFFFFF:
        raise ValueError("group must be a 3-byte value")
    return f"{SID_CLEAR_DTC:02X}{group:06X}"


# --------------------------------------------------------------------------- pure response parsers
def _decode_status(b: int) -> tuple[str, ...]:
    return tuple(name for bit, name in _STATUS_BITS.items() if b & (1 << bit))


def _check_negative(data: bytes, expected_sid: int) -> None:
    if data and data[0] == NEGATIVE_RESPONSE:
        sid = data[1] if len(data) > 1 else None
        nrc = data[2] if len(data) > 2 else None
        raise UdsError(
            _NRC.get(nrc or -1, "negative_response"),
            f"negative response to service {expected_sid:#04x}: NRC {nrc:#04x}" if nrc is not None else "negative response",
            service=sid,
            nrc=nrc,
        )


def parse_read_dtc_response(data: bytes) -> list[UdsDtc]:
    """Parse a 0x59 0x02 response into DTCs. Each record is 4 bytes: 3 DTC + 1 status."""
    _check_negative(data, SID_READ_DTC)
    if len(data) < 2 or data[0] != SID_READ_DTC + POSITIVE_OFFSET or data[1] != SUBFN_BY_STATUS_MASK:
        raise UdsError("unexpected_response", f"not a 0x59 0x02 response: {data[:3].hex()}")
    body = data[3:]  # skip SID, subfunction, DTCStatusAvailabilityMask
    out: list[UdsDtc] = []
    for i in range(0, len(body) - 3, 4):
        hi, mid, ftb, status = body[i], body[i + 1], body[i + 2], body[i + 3]
        if hi == 0 and mid == 0 and ftb == 0:
            continue  # filler
        code = decode_dtc(hi, mid)
        if code is None:
            continue
        out.append(UdsDtc(code=code, ftb=ftb, status=status, flags=_decode_status(status)))
    return out


def parse_clear_response(data: bytes) -> bool:
    """True when the module positively acknowledged the clear (0x54)."""
    _check_negative(data, SID_CLEAR_DTC)
    return bool(data) and data[0] == SID_CLEAR_DTC + POSITIVE_OFFSET


def _hex_to_bytes(s: str) -> bytes:
    toks = s.replace("\r", " ").split()
    joined = "".join(t for t in toks if all(c in "0123456789ABCDEFabcdef" for c in t))
    if len(joined) % 2:
        joined = joined[:-1]
    return bytes.fromhex(joined) if joined else b""


# --------------------------------------------------------------------------- async driver
@dataclass
class UdsResult:
    module: str
    request: str
    response_raw: str
    dtcs: list[UdsDtc] = field(default_factory=list)
    ok: bool = True


class UdsClient:
    """Drives UDS reads/clears for a single module through an ELM327 (``Elm327``)."""

    def __init__(self, elm):  # noqa: ANN001 - Elm327, kept loose to avoid a cycle
        self.elm = elm

    async def _select(self, module: UdsModule) -> None:
        # Point the adapter at one module: send to request_id, accept only response_id.
        await self.elm.at(f"ATSH{module.request_id:03X}" if module.id_bits == 11 else f"ATSH{module.request_id:08X}")
        await self.elm.at(f"ATCRA{module.response_id:03X}" if module.id_bits == 11 else f"ATCRA{module.response_id:08X}")

    async def _restore(self) -> None:
        # Back to normal OBD broadcast addressing and no receive filter (best-effort).
        with contextlib.suppress(Exception):
            await self.elm.at("ATCRA", tolerate_unknown=True)  # clear receive filter
            await self.elm.at("ATSH7DF" if self.elm.id_bits == 11 else "ATSH18DB33F1", tolerate_unknown=True)

    async def read_module_dtcs(self, module: UdsModule, status_mask: int = 0xFF, timeout: float = 3.0) -> UdsResult:
        """Read a module's fault codes (service 0x19 0x02). Read-only, always safe.

        ``timeout`` can be lowered for discovery sweeps where most addresses will not answer.
        """
        req = build_read_dtc_request(status_mask)
        try:
            await self._select(module)
            resp = await self.elm.send(req, timeout=timeout)
            data = _hex_to_bytes(resp)
            dtcs = parse_read_dtc_response(data) if data else []
            return UdsResult(module=module.key, request=req, response_raw=resp, dtcs=dtcs)
        finally:
            await self._restore()

    async def clear_module_dtcs(self, module: UdsModule, auth) -> UdsResult:  # noqa: ANN001 - ClearAuthorization
        """Clear a module's stored codes (service 0x14). Requires a server-approved authorisation.

        This never deploys, programs or writes anything but the standard clear-codes service, and the
        SRS/ABS safety gates live in the server's AutoMind Control policy (active-fault refusal, repair
        confirmation, certified device). The caller must pass a policy-approved authorisation.
        """
        if not (
            auth
            and getattr(auth, "approved", False)
            and getattr(auth, "operation_id", "")
            and getattr(auth, "consent_text", "").strip()
        ):
            raise UdsError("not_authorised", "clearing a module needs a server-approved AutoMind Control operation")
        req = build_clear_request()
        try:
            await self._select(module)
            resp = await self.elm.send(req, timeout=5.0)
            ok = parse_clear_response(_hex_to_bytes(resp)) if resp.strip() else False
            return UdsResult(module=module.key, request=req, response_raw=resp, ok=ok)
        finally:
            await self._restore()


__all__ = [
    "UdsModule",
    "UdsDtc",
    "UdsResult",
    "UdsClient",
    "UdsError",
    "build_read_dtc_request",
    "build_clear_request",
    "parse_read_dtc_response",
    "parse_clear_response",
]
