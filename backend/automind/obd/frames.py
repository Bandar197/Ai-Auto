"""Parse ELM327 response text into per-ECU message payloads.

Handles (with ATH1 = headers on, the mode AutoMind uses):
  * CAN 11-bit   "7E8 06 41 00 BE 3F A8 13 00"
  * CAN 29-bit   "18 DA F1 10 06 41 00 BE 3F A8 13"
  * ISO-TP multi-frame (first frame 0x1N + consecutive 0x2N) reassembly
  * J1850 / ISO 9141-2 / ISO 14230-4 "48 6B 10 41 00 BE 3F A8 13 C2"
    (3 header bytes, trailing checksum)
And with headers off (fallback for adapters that ignore ATH1):
  * single line "41 00 BE 3F A8 13"
  * CAN multi-frame "014" / "0: 49 02 01 31 43 34" / "1: ..."
Spaces may be on or off.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

_HEX = re.compile(r"^[0-9A-F]+$")


@dataclass
class EcuMessage:
    ecu: str | None  # '7E8', '18DAF110', '10' (legacy source address) or None (headers off)
    data: bytes  # payload starting with the response service byte (e.g. 0x41)
    frames: int = 1


@dataclass
class _IsoTp:
    expected: int
    buf: bytearray = field(default_factory=bytearray)
    next_seq: int = 1
    frames: int = 1


def _tokens(line: str) -> list[str]:
    line = line.strip().upper()
    if " " in line:
        return [t for t in line.split() if t]
    # spaces off: CAN 11-bit header is 3 hex chars, then byte pairs
    if len(line) % 2 == 1 and len(line) >= 3:
        head, rest = line[:3], line[3:]
        return [head] + [rest[i:i + 2] for i in range(0, len(rest), 2)]
    return [line[i:i + 2] for i in range(0, len(line), 2)]


def _is_hex_tokens(toks: list[str]) -> bool:
    return bool(toks) and all(_HEX.match(t) for t in toks)


def parse_response(
    text: str,
    *,
    headers: bool = True,
    protocol_family: str = "can",
    can_id_bits: int = 11,
) -> list[EcuMessage]:
    """Parse the text between a command and the '>' prompt.

    `text` must already have the echo, 'SEARCHING...' and error strings removed.
    Returns messages grouped per ECU (multi-frame responses reassembled).
    """
    lines = [ln.strip() for ln in text.replace("\n", "\r").split("\r") if ln.strip()]
    if not lines:
        return []

    if not headers:
        return _parse_headers_off(lines)

    if protocol_family == "can":
        return _parse_can(lines, can_id_bits)
    return _parse_legacy(lines)


def _parse_can(lines: list[str], id_bits: int) -> list[EcuMessage]:  # noqa: ARG001 - auto-detected
    pending: dict[str, _IsoTp] = {}
    done: list[EcuMessage] = []
    for line in lines:
        toks = _tokens(line)
        if not _is_hex_tokens(toks):
            continue
        # A 3-char first token is an 11-bit id; otherwise a 29-bit id spans 4 bytes.
        if len(toks[0]) == 3:
            ecu, body = toks[0], toks[1:]
        elif len(toks) >= 5:
            ecu, body = "".join(toks[:4]), toks[4:]
        else:
            continue
        if not body:
            continue
        data = bytes(int(t, 16) for t in body)
        pci = data[0]
        ftype = pci >> 4
        if ftype == 0x0:  # single frame
            n = pci & 0x0F
            if n == 0 or n > len(data) - 1:
                n = len(data) - 1
            done.append(EcuMessage(ecu, data[1:1 + n]))
        elif ftype == 0x1:  # first frame
            if len(data) < 2:
                continue
            total = ((pci & 0x0F) << 8) | data[1]
            st = _IsoTp(expected=total)
            st.buf.extend(data[2:])
            pending[ecu] = st
        elif ftype == 0x2:  # consecutive frame
            st = pending.get(ecu)
            if st is None:
                continue
            seq = pci & 0x0F
            if seq != st.next_seq:
                # out of order / lost frame: drop the whole message (never guess bytes)
                pending.pop(ecu, None)
                continue
            st.buf.extend(data[1:])
            st.next_seq = (st.next_seq + 1) & 0x0F
            st.frames += 1
            if len(st.buf) >= st.expected:
                done.append(EcuMessage(ecu, bytes(st.buf[: st.expected]), st.frames))
                pending.pop(ecu, None)
        # flow control (0x3) frames are not shown by the ELM327
    return _merge_same_ecu(done)


def _parse_legacy(lines: list[str]) -> list[EcuMessage]:
    """J1850 / ISO 9141 / KWP: [prio][target][source] data... [checksum]."""
    out: list[EcuMessage] = []
    for line in lines:
        toks = _tokens(line)
        if not _is_hex_tokens(toks) or len(toks) < 5:
            continue
        b = bytes(int(t, 16) for t in toks)
        src = f"{b[2]:02X}"
        out.append(EcuMessage(src, b[3:-1]))
    return _merge_legacy(out)


def _merge_legacy(msgs: list[EcuMessage]) -> list[EcuMessage]:
    """Legacy protocols split long answers (e.g. mode 03, 09) over several
    frames from the same ECU, each repeating the service byte (+ message
    counter for mode 09). Concatenate them per ECU."""
    by_ecu: dict[str, list[bytes]] = {}
    order: list[str] = []
    for m in msgs:
        key = m.ecu or ""
        if key not in by_ecu:
            by_ecu[key] = []
            order.append(key)
        by_ecu[key].append(m.data)
    out: list[EcuMessage] = []
    for key in order:
        parts = by_ecu[key]
        if len(parts) == 1:
            out.append(EcuMessage(key, parts[0]))
            continue
        svc = parts[0][0]
        if svc == 0x49:  # 49 PID COUNTER data...
            merged = bytearray(parts[0][:2])
            for p in sorted(parts, key=lambda x: x[2] if len(x) > 2 else 0):
                merged.extend(p[3:])
            out.append(EcuMessage(key, bytes(merged), len(parts)))
        elif svc in (0x43, 0x47, 0x4A):
            merged = bytearray([svc])
            for p in parts:
                merged.extend(p[1:])
            out.append(EcuMessage(key, bytes(merged), len(parts)))
        else:
            for p in parts:
                out.append(EcuMessage(key, p))
    return out


def _parse_headers_off(lines: list[str]) -> list[EcuMessage]:
    # CAN multi-frame without headers: "014", "0: ..", "1: ..".
    if re.fullmatch(r"[0-9A-F]{3}", lines[0].upper()) and any(":" in ln for ln in lines[1:]):
        total = int(lines[0], 16)
        buf = bytearray()
        for ln in lines[1:]:
            if ":" not in ln:
                continue
            _, rest = ln.split(":", 1)
            toks = _tokens(rest)
            if _is_hex_tokens(toks):
                buf.extend(int(t, 16) for t in toks)
        return [EcuMessage(None, bytes(buf[:total]), len(lines) - 1)]
    out: list[EcuMessage] = []
    for ln in lines:
        toks = _tokens(ln)
        if _is_hex_tokens(toks):
            out.append(EcuMessage(None, bytes(int(t, 16) for t in toks)))
    return out


def _merge_same_ecu(msgs: list[EcuMessage]) -> list[EcuMessage]:
    # Each ECU normally answers once per request; keep order, keep duplicates
    # (some ECUs answer twice) — callers pick the first per ECU.
    return msgs


def first_per_ecu(msgs: list[EcuMessage]) -> dict[str | None, EcuMessage]:
    out: dict[str | None, EcuMessage] = {}
    for m in msgs:
        out.setdefault(m.ecu, m)
    return out


def to_hex(data: bytes) -> str:
    return " ".join(f"{b:02X}" for b in data)
