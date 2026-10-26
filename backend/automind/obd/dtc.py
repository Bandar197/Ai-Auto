"""SAE J2012 DTC byte decoding."""

from __future__ import annotations

_SYSTEM = "PCBU"


def decode_dtc(b1: int, b2: int) -> str | None:
    """Decode two DTC bytes; returns None for the 0x0000 filler."""
    if b1 == 0 and b2 == 0:
        return None
    letter = _SYSTEM[(b1 >> 6) & 0x03]
    d1 = (b1 >> 4) & 0x03
    return f"{letter}{d1}{b1 & 0x0F:X}{b2:02X}"


def encode_dtc(code: str) -> tuple[int, int]:
    code = code.strip().upper()
    if len(code) != 5 or code[0] not in _SYSTEM:
        raise ValueError(f"invalid DTC {code!r}")
    sys_bits = _SYSTEM.index(code[0])
    d1 = int(code[1], 16)
    if d1 > 3:
        raise ValueError(f"invalid DTC {code!r}")
    b1 = (sys_bits << 6) | (d1 << 4) | int(code[2], 16)
    b2 = int(code[3:5], 16)
    return b1, b2


def decode_dtc_list(data: bytes) -> list[str]:
    out: list[str] = []
    for i in range(0, len(data) - 1, 2):
        c = decode_dtc(data[i], data[i + 1])
        if c:
            out.append(c)
    return out
