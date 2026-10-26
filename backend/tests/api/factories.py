"""Test data builders."""

from __future__ import annotations

import uuid
from typing import Any

VALID_VIN = "2C3CDZAG7JH101234"


def make_recording(
    data_mode: str = "live",
    *,
    dtcs: list[str] | None = None,
    seconds: int = 30,
    rpm: float = 780.0,
    map_kpa: float = 62.0,
    coolant: float = 90.0,
    vin: str | None = None,
) -> dict[str, Any]:
    """A small but realistic recording v1 (warm idle, optional DTCs)."""
    samples = []
    for i in range(seconds):
        t = i * 1000
        samples.append({"t_ms": t, "pid": "010C", "ecu": "7E8", "raw": None, "values": {"engine_rpm": rpm + (i % 3) * 5}})
        samples.append({"t_ms": t + 100, "pid": "010B", "ecu": "7E8", "values": {"map_kpa": map_kpa}})
        samples.append({"t_ms": t + 200, "pid": "0105", "ecu": "7E8", "values": {"coolant_temp_c": coolant}})
        samples.append({"t_ms": t + 300, "pid": "010D", "ecu": "7E8", "values": {"vehicle_speed_kmh": 0.0}})
    return {
        "format": "automind.recording.v1",
        "recording_id": str(uuid.uuid4()),
        "created_at": "2026-10-20T10:00:00Z",
        "data_mode": data_mode,
        "source": {
            "kind": "simulator" if data_mode == "demo" else "elm327_wifi",
            "adapter_firmware": "ELM327 v1.5",
            "protocol_code": "6",
            "protocol_name": "ISO 15765-4 (CAN 11/500)",
            "demo_scenario": "p0106_map_sensor" if data_mode == "demo" else None,
        },
        "vehicle": {"vin": vin, "make": "Toyota", "model": "Camry", "model_year": 2018},
        "supported_pids": {"01": ["05", "0B", "0C", "0D"]},
        "ecus": ["7E8"],
        "dtcs": [{"code": c, "status": "stored", "ecu": "7E8"} for c in (dtcs or [])],
        "freeze_frames": [],
        "duration_ms": seconds * 1000,
        "signals": [
            {"key": "engine_rpm", "pid": "010C", "unit": "rpm"},
            {"key": "map_kpa", "pid": "010B", "unit": "kPa"},
            {"key": "coolant_temp_c", "pid": "0105", "unit": "°C"},
            {"key": "vehicle_speed_kmh", "pid": "010D", "unit": "km/h"},
        ],
        "samples": samples,
        "events": [],
    }


async def make_org(db, name: str = "Workshop", kind: str = "workshop") -> uuid.UUID:
    return await db.fetchval(
        "insert into automind.organizations (name, kind, status) values ($1, $2, 'active') returning id", name, kind
    )


async def add_member(db, org_id, user_id, role: str = "technician") -> None:
    await db.execute(
        "insert into automind.organization_members (organization_id, user_id, role) values ($1,$2,$3)",
        org_id,
        uuid.UUID(str(user_id)),
        role,
    )
