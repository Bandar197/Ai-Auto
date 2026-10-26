"""SAE J1979 service 01 PID table (shared/obd/pids.json) and decoders."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from functools import lru_cache
from typing import Any

from automind.shared_paths import shared_dir


@dataclass(frozen=True)
class OutputDef:
    key: str
    name_en: str
    name_ar: str
    unit: str
    start: int
    length: int
    scale: float
    offset: float
    signed: bool
    min: float
    max: float


@dataclass(frozen=True)
class PidDef:
    pid: str  # two hex chars, upper case, e.g. "0C"
    service: str
    name_en: str
    name_ar: str
    bytes: int
    kind: str
    category: str
    outputs: tuple[OutputDef, ...] = field(default_factory=tuple)

    @property
    def code(self) -> str:
        """service + pid, e.g. '010C'."""
        return f"{self.service}{self.pid}"


@lru_cache(maxsize=1)
def load_pid_table() -> dict[str, Any]:
    return json.loads((shared_dir() / "obd" / "pids.json").read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def pid_defs() -> dict[str, PidDef]:
    out: dict[str, PidDef] = {}
    for p in load_pid_table()["pids"]:
        outs = tuple(OutputDef(**o) for o in p.get("outputs", []))
        d = PidDef(
            pid=p["pid"].upper(), service=p["service"], name_en=p["name_en"], name_ar=p["name_ar"],
            bytes=p["bytes"], kind=p["kind"], category=p["category"], outputs=outs,
        )
        out[d.pid] = d
    return out


@lru_cache(maxsize=1)
def signal_index() -> dict[str, tuple[PidDef, OutputDef]]:
    """signal key -> (pid, output)."""
    idx: dict[str, tuple[PidDef, OutputDef]] = {}
    for d in pid_defs().values():
        for o in d.outputs:
            idx[o.key] = (d, o)
    return idx


def enums() -> dict[str, dict[str, Any]]:
    return load_pid_table()["enums"]


def _raw(data: bytes, start: int, length: int, signed: bool) -> int | None:
    if start + length > len(data):
        return None
    return int.from_bytes(data[start:start + length], "big", signed=signed)


def decode_supported_bitmask(base_pid: int, data: bytes) -> list[str]:
    """Bitmask of PIDs base+1 .. base+0x20. Returns hex PID strings."""
    out: list[str] = []
    if len(data) < 4:
        return out
    mask = int.from_bytes(data[:4], "big")
    for i in range(32):
        if mask & (1 << (31 - i)):
            out.append(f"{base_pid + i + 1:02X}")
    return out


_SPARK_MONITORS = ["misfire", "fuel_system", "components"]
_SPARK_EXTENDED = [
    "catalyst", "heated_catalyst", "evap_system", "secondary_air",
    "ac_refrigerant", "o2_sensor", "o2_sensor_heater", "egr_system",
]
_DIESEL_EXTENDED = [
    "nmhc_catalyst", "nox_scr", None, "boost_pressure", None, "exhaust_gas_sensor", "pm_filter", "egr_vvt",
]


def decode_monitor_status(data: bytes) -> dict[str, Any]:
    """PID 01: MIL, DTC count and readiness monitors (available / complete)."""
    if len(data) < 4:
        return {}
    a, b, c, d = data[0], data[1], data[2], data[3]
    compression = bool(b & 0x08)
    monitors: dict[str, dict[str, bool]] = {}
    for i, name in enumerate(_SPARK_MONITORS):
        if b & (1 << i):
            monitors[name] = {"available": True, "complete": not bool(b & (1 << (i + 4)))}
    names = _DIESEL_EXTENDED if compression else _SPARK_EXTENDED
    for i, name in enumerate(names):
        if name and c & (1 << i):
            monitors[name] = {"available": True, "complete": not bool(d & (1 << i))}
    return {
        "mil_on": bool(a & 0x80),
        "dtc_count": a & 0x7F,
        "ignition": "compression" if compression else "spark",
        "monitors": monitors,
    }


def decode_pid(pid: str, data: bytes) -> dict[str, float | None]:
    """Decode the data bytes (after '41 <pid>') into {signal_key: value}.

    Unknown/unsupported kinds return {}. Values outside the PID's defined range
    are returned as-is (the diagnosis layer flags implausible data).
    """
    d = pid_defs().get(pid.upper())
    if d is None:
        return {}
    if d.kind == "monitor_status":
        ms = decode_monitor_status(data)
        if not ms:
            return {}
        return {"mil_on": 1.0 if ms["mil_on"] else 0.0, "dtc_count": float(ms["dtc_count"])}
    if d.kind in ("supported_bitmask", "dtc", "bitmask_raw") and not d.outputs:
        return {}
    values: dict[str, float | None] = {}
    for o in d.outputs:
        raw = _raw(data, o.start, o.length, o.signed)
        if raw is None:
            values[o.key] = None
            continue
        # O2 narrow-band sensor trim byte 0xFF means "not used for trim".
        if o.key.endswith("_stft") and o.key.startswith("o2_") and raw == 0xFF:
            values[o.key] = None
            continue
        values[o.key] = round(raw * o.scale + o.offset, 4)
    return values


def fuel_system_label(value: float | None) -> str | None:
    if value is None:
        return None
    return enums()["fuel_system_status"].get(str(int(value)))
