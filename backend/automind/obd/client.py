"""High-level OBD-II client on top of an ELM327.

Keeps the two links separate, because users routinely confuse them:
  * adapter link  — this device ↔ the OBD adapter (Wi-Fi/BLE/USB)
  * ECU link      — the adapter ↔ the vehicle's computers (CAN/K-line/J1850)
"""

from __future__ import annotations

import asyncio
import enum
import logging
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime

from automind.obd.dtc import decode_dtc_list
from automind.obd.elm327 import AdapterInfo, Elm327
from automind.obd.errors import (
    AdapterError,
    AdapterTimeout,
    EcuNoResponse,
    NotSupported,
    ObdError,
    PolicyViolation,
    TransportError,
)
from automind.obd.frames import EcuMessage, to_hex
from automind.obd.pids import decode_monitor_status, decode_pid, decode_supported_bitmask
from automind.obd.transport.base import Transport

log = logging.getLogger("automind.obd.client")

PRIMARY_ECUS = ("7E8", "18DAF110", "10")


class AdapterState(enum.StrEnum):
    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    CONNECTED = "connected"
    ERROR = "error"


class EcuState(enum.StrEnum):
    UNKNOWN = "unknown"
    SEARCHING = "searching"
    CONNECTED = "connected"
    NO_RESPONSE = "no_response"
    BUS_ERROR = "bus_error"


@dataclass
class ConnectionReport:
    """Mirrors the `POST /connections` payload."""

    transport: str
    adapter_status: str = "error"  # connected|unreachable|timeout|rejected|error
    ecu_status: str = "not_attempted"  # connected|no_response|bus_error|not_attempted|error
    protocol_code: str | None = None
    protocol_name: str | None = None
    adapter_firmware: str | None = None
    adapter_description: str | None = None
    battery_voltage: float | None = None
    is_simulator: bool = False
    attempts: int = 0
    latency_ms: int | None = None
    error_code: str | None = None
    error_message: str | None = None
    started_at: datetime = field(default_factory=lambda: datetime.now(UTC))
    ended_at: datetime | None = None

    @property
    def ok(self) -> bool:
        return self.adapter_status == "connected" and self.ecu_status == "connected"

    def as_dict(self) -> dict:
        d = self.__dict__.copy()
        d["started_at"] = self.started_at.isoformat()
        d["ended_at"] = self.ended_at.isoformat() if self.ended_at else None
        return d


@dataclass
class PidReading:
    pid: str  # '010C'
    ecu: str | None
    values: dict[str, float | None]
    raw: str
    t: float  # monotonic seconds


@dataclass
class DtcEntry:
    code: str
    status: str  # stored|pending|permanent
    ecu: str | None
    service: str  # '03'|'07'|'0A'


@dataclass
class ClearAuthorization:
    """Proof that the server's AutoMind Control policy approved service 04."""

    operation_id: str
    approved: bool
    consent_text: str


class ObdClient:
    def __init__(
        self,
        transport: Transport,
        *,
        protocol: str = "0",
        timeout: float = 2.5,
        on_state: Callable[[AdapterState, EcuState, str], None] | None = None,
    ):
        self.transport = transport
        self.elm = Elm327(transport, timeout=timeout)
        self.protocol = protocol
        self.adapter_state = AdapterState.DISCONNECTED
        self.ecu_state = EcuState.UNKNOWN
        self.info = AdapterInfo()
        self.supported: dict[str, dict[str, set[str]]] = {}  # service -> ecu -> pids
        self.ecus: list[str] = []
        self.primary_ecu: str | None = None
        self._on_state = on_state
        self.last_report: ConnectionReport | None = None

    # ------------------------------------------------------------------ state
    def _set(self, a: AdapterState | None = None, e: EcuState | None = None, msg: str = "") -> None:
        if a:
            self.adapter_state = a
        if e:
            self.ecu_state = e
        if self._on_state:
            try:
                self._on_state(self.adapter_state, self.ecu_state, msg)
            except Exception:  # pragma: no cover - UI callbacks must not break IO
                log.exception("state callback failed")

    @property
    def is_simulator(self) -> bool:
        return self.info.is_simulator

    # ------------------------------------------------------------------ connect
    async def connect(self, retries: int = 3, backoff: float = 1.0) -> ConnectionReport:
        rep = ConnectionReport(transport=self.transport.kind)
        t0 = time.monotonic()
        for attempt in range(1, retries + 1):
            rep.attempts = attempt
            try:
                await self._connect_once(rep)
                break
            except TransportError as e:
                rep.adapter_status, rep.error_code, rep.error_message = "unreachable", e.code, str(e)
                self._set(AdapterState.ERROR, EcuState.UNKNOWN, str(e))
            except AdapterTimeout as e:
                rep.adapter_status, rep.error_code, rep.error_message = "timeout", e.code, str(e)
                self._set(AdapterState.ERROR, EcuState.UNKNOWN, str(e))
            except EcuNoResponse as e:
                # Adapter is fine; the car did not answer. Retrying rarely helps
                # (ignition off, wrong protocol) but we try once more.
                rep.ecu_status = "bus_error" if "error" in e.code else "no_response"
                rep.error_code, rep.error_message = e.code, e.raw or e.code
                self._set(e=EcuState.BUS_ERROR if rep.ecu_status == "bus_error" else EcuState.NO_RESPONSE,
                          msg="adapter reachable but no ECU response — is the ignition on?")
            except AdapterError as e:
                rep.adapter_status, rep.error_code, rep.error_message = "error", e.code, str(e)
                self._set(AdapterState.ERROR, msg=str(e))
            if attempt < retries:
                await self._safe_close()
                await asyncio.sleep(backoff * attempt)
        rep.latency_ms = int((time.monotonic() - t0) * 1000)
        rep.ended_at = datetime.now(UTC)
        self.last_report = rep
        return rep

    async def _connect_once(self, rep: ConnectionReport) -> None:
        self._set(AdapterState.CONNECTING, EcuState.UNKNOWN, f"connecting to adapter {self.transport.description}")
        if not self.transport.is_open:
            await self.transport.open()
        self.info = await self.elm.initialize(self.protocol)
        rep.adapter_status = "connected"
        rep.adapter_firmware = self.info.firmware
        rep.adapter_description = self.info.description
        rep.battery_voltage = self.info.voltage
        rep.is_simulator = self.info.is_simulator
        self._set(AdapterState.CONNECTED, EcuState.SEARCHING, "adapter connected; searching vehicle protocol")
        # First request triggers the protocol search; parse properly only after
        # we know the protocol family (CAN vs legacy framing).
        await self.elm.query("0100")
        rep.protocol_code, rep.protocol_name = await self.elm.read_protocol()
        resp = await self.elm.query("0100")
        self._ingest_supported("01", 0x00, resp.messages)
        await self._walk_supported("01")
        rep.ecu_status = "connected"
        rep.error_code = rep.error_message = None
        self._set(e=EcuState.CONNECTED, msg=f"vehicle connected via {rep.protocol_name}")

    async def _safe_close(self) -> None:
        try:
            await self.transport.close()
        except Exception:  # noqa: S110
            pass

    async def close(self) -> None:
        await self._safe_close()
        self._set(AdapterState.DISCONNECTED, EcuState.UNKNOWN, "disconnected")

    # ------------------------------------------------------------------ supported PIDs
    def _ingest_supported(self, service: str, base: int, msgs: list[EcuMessage]) -> None:
        resp_sid = int(service, 16) + 0x40
        svc = self.supported.setdefault(service, {})
        for m in msgs:
            if len(m.data) >= 6 and m.data[0] == resp_sid and m.data[1] == base:
                pids = decode_supported_bitmask(base, m.data[2:6])
                svc.setdefault(m.ecu or "", set()).update(pids)
                if m.ecu not in self.ecus:
                    self.ecus.append(m.ecu or "")
        if service == "01" and self.primary_ecu is None and self.ecus:
            self.primary_ecu = next((e for e in PRIMARY_ECUS if e in self.ecus), self.ecus[0])

    async def _walk_supported(self, service: str) -> None:
        base = 0x00
        while True:
            pids = set().union(*self.supported.get(service, {}).values()) if self.supported.get(service) else set()
            nxt = f"{base + 0x20:02X}"
            if nxt not in pids or base + 0x20 > 0xE0:
                return
            base += 0x20
            try:
                resp = await self.elm.query(f"{service}{base:02X}")
            except EcuNoResponse:
                return
            self._ingest_supported(service, base, resp.messages)

    def supported_pids(self, service: str = "01", ecu: str | None = None) -> set[str]:
        svc = self.supported.get(service, {})
        if ecu is not None:
            return set(svc.get(ecu, set()))
        return set().union(*svc.values()) if svc else set()

    def is_supported(self, pid: str, service: str = "01") -> bool:
        return pid.upper() in self.supported_pids(service)

    # ------------------------------------------------------------------ service 01
    async def read_pid(self, pid: str, *, check_supported: bool = True) -> PidReading:
        pid = pid.upper()
        if check_supported and not self.is_supported(pid):
            raise NotSupported(f"PID 01{pid} not reported as supported by the vehicle")
        resp = await self.elm.query(f"01{pid}")
        pid_b = int(pid, 16)
        cands = [m for m in resp.messages if len(m.data) >= 2 and m.data[0] == 0x41 and m.data[1] == pid_b]
        if not cands:
            raise EcuNoResponse("no_data", resp.raw)
        msg = next((m for m in cands if m.ecu == self.primary_ecu), cands[0])
        return PidReading(f"01{pid}", msg.ecu, decode_pid(pid, msg.data[2:]), to_hex(msg.data), time.monotonic())

    async def monitor_status(self) -> dict:
        resp = await self.elm.query("0101")
        cands = [m for m in resp.messages if len(m.data) >= 6 and m.data[0] == 0x41 and m.data[1] == 0x01]
        if not cands:
            return {}
        msg = next((m for m in cands if m.ecu == self.primary_ecu), cands[0])
        return decode_monitor_status(msg.data[2:6])

    # ------------------------------------------------------------------ DTCs
    async def read_dtcs(self, service: str = "03") -> list[DtcEntry]:
        status = {"03": "stored", "07": "pending", "0A": "permanent"}[service]
        resp_sid = int(service, 16) + 0x40
        try:
            resp = await self.elm.query(service)
        except EcuNoResponse as e:
            if e.code == "no_data":
                return []  # e.g. service 0A unsupported or no codes
            raise
        out: list[DtcEntry] = []
        seen: set[tuple[str, str | None]] = set()
        for m in resp.messages:
            if not m.data or m.data[0] != resp_sid:
                continue
            body = m.data[1:]
            if self.elm.family == "can" and body:
                count = body[0]
                codes = decode_dtc_list(body[1:1 + 2 * count])
            else:
                codes = decode_dtc_list(body)
            for c in codes:
                if (c, m.ecu) not in seen:
                    seen.add((c, m.ecu))
                    out.append(DtcEntry(c, status, m.ecu, service))
        return out

    async def read_all_dtcs(self) -> list[DtcEntry]:
        out: list[DtcEntry] = []
        for svc in ("03", "07", "0A"):
            try:
                out.extend(await self.read_dtcs(svc))
            except (EcuNoResponse, AdapterError) as e:
                log.info("service %s unavailable: %s", svc, e)
        return out

    # ------------------------------------------------------------------ freeze frame
    async def read_freeze_frame(self, frame: int = 0) -> dict:
        """Service 02. Only PIDs the ECU reports as supported in the frame are read."""
        result: dict = {"frame": frame, "dtc": None, "values": {}}
        try:
            resp = await self.elm.query(f"0200{frame:02X}")
        except EcuNoResponse:
            return result
        supported: set[str] = set()
        for m in resp.messages:
            if len(m.data) >= 7 and m.data[0] == 0x42 and m.data[1] == 0x00:
                supported |= set(decode_supported_bitmask(0, m.data[3:7]))
        if "02" in supported:
            try:
                r = await self.elm.query(f"0202{frame:02X}")
                for m in r.messages:
                    if len(m.data) >= 5 and m.data[0] == 0x42 and m.data[1] == 0x02:
                        codes = decode_dtc_list(m.data[3:5])
                        result["dtc"] = codes[0] if codes else None
                        break
            except EcuNoResponse:
                pass
        if result["dtc"] is None:
            return result  # no freeze frame stored
        for pid in sorted(supported - {"00", "01", "02", "20", "40", "60", "80", "A0", "C0"}):
            try:
                r = await self.elm.query(f"02{pid}{frame:02X}")
            except (EcuNoResponse, AdapterError):
                continue
            for m in r.messages:
                if len(m.data) >= 4 and m.data[0] == 0x42 and m.data[1] == int(pid, 16):
                    result["values"].update(decode_pid(pid, m.data[3:]))
                    break
        return result

    # ------------------------------------------------------------------ service 09
    async def read_vin(self) -> str | None:
        try:
            resp = await self.elm.query("0902", timeout=5.0)
        except (EcuNoResponse, AdapterError):
            return None
        for m in resp.messages:
            if len(m.data) >= 3 and m.data[0] == 0x49 and m.data[1] == 0x02:
                body = m.data[2:]
                if self.elm.family == "can" and body and body[0] == 0x01:
                    body = body[1:]
                txt = "".join(chr(b) for b in body if 0x30 <= b <= 0x5A)
                if len(txt) >= 17:
                    vin = txt[-17:]
                    if not any(ch in vin for ch in "IOQ"):
                        return vin
        return None

    async def read_voltage(self) -> float | None:
        import re

        rv = await self.elm.at("ATRV", tolerate_unknown=True)
        m = re.search(r"(\d+(?:\.\d+)?)\s*V", rv.upper())
        return float(m.group(1)) if m else None

    # ------------------------------------------------------------------ service 04 (write)
    async def clear_dtcs(self, auth: ClearAuthorization) -> dict:
        """Clear DTCs — only with a server-approved authorization, engine off, vehicle stopped."""
        if not (auth and auth.approved and auth.operation_id and auth.consent_text.strip()):
            raise PolicyViolation("service 04 requires an approved AutoMind Control operation with consent")
        rpm = speed = None
        if self.is_supported("0C"):
            rpm = (await self.read_pid("0C")).values.get("engine_rpm")
        if self.is_supported("0D"):
            speed = (await self.read_pid("0D")).values.get("vehicle_speed")
        if rpm is not None and rpm > 0:
            raise PolicyViolation("engine must be off (RPM reported > 0)")
        if speed is not None and speed > 0:
            raise PolicyViolation("vehicle must be stationary")
        resp = await self.elm.query("04", timeout=5.0)
        ok = any(m.data[:1] == b"\x44" for m in resp.messages)
        return {"ok": ok, "request": "04", "response": resp.raw, "rpm": rpm, "speed": speed}


__all__ = [
    "AdapterState", "ClearAuthorization", "ConnectionReport", "DtcEntry", "EcuState",
    "ObdClient", "ObdError", "PidReading",
]
