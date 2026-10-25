"""Session recording format v1 (see shared/schemas/recording.v1.schema.json)."""

from __future__ import annotations

import json
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, Field

FORMAT_ID = "automind.recording.v1"


class RecSource(BaseModel):
    kind: Literal["elm327_wifi", "elm327_ble", "elm327_serial", "simulator"]
    adapter_firmware: str | None = None
    protocol_code: str | None = None
    protocol_name: str | None = None
    demo_scenario: str | None = None
    app: str | None = None


class RecVehicle(BaseModel):
    vin: str | None = None
    make: str | None = None
    model: str | None = None
    model_year: int | None = None


class RecDTC(BaseModel):
    code: str = Field(pattern=r"^[PCBU][0-9A-F]{4}$")
    status: Literal["stored", "pending", "permanent"]
    ecu: str | None = None


class RecFreezeFrame(BaseModel):
    dtc: str | None = None
    frame: int = 0
    values: dict[str, float | None] = Field(default_factory=dict)


class RecSignal(BaseModel):
    key: str
    pid: str
    unit: str | None = None


class RecSample(BaseModel):
    t_ms: int = Field(ge=0)
    pid: str
    ecu: str | None = None
    raw: str | None = None
    values: dict[str, float | None]


class RecEvent(BaseModel):
    t_ms: int
    type: Literal["connection_lost", "reconnected", "ecu_no_response", "note"]
    detail: str | None = None


class RecModuleScan(BaseModel):
    """An honest per-module read outcome (SRS/ABS/body over UDS, or any ECU).

    ``outcome`` is recorded verbatim; a module that did not answer (``no_response``)
    or refused (``refused``) is never recorded as "no faults".
    """

    key: str
    name_en: str
    name_ar: str
    category: str = "other"
    address: str | None = None
    outcome: Literal["read_codes", "read_no_codes", "refused", "no_response"]
    codes: list[RecDTC] = Field(default_factory=list)


class Recording(BaseModel):
    format: Literal["automind.recording.v1"] = FORMAT_ID
    recording_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    data_mode: Literal["live", "demo"]
    source: RecSource
    vehicle: RecVehicle = Field(default_factory=RecVehicle)
    supported_pids: dict[str, list[str]] = Field(default_factory=dict)
    ecus: list[str] = Field(default_factory=list)
    dtcs: list[RecDTC] = Field(default_factory=list)
    freeze_frames: list[RecFreezeFrame] = Field(default_factory=list)
    # service 01 PID 01 at scan time: {"mil_on", "dtc_count", "ignition", "monitors": {name: {available, complete}}}
    readiness: dict | None = None
    duration_ms: int = Field(0, ge=0)
    signals: list[RecSignal] = Field(default_factory=list)
    samples: list[RecSample] = Field(default_factory=list)
    events: list[RecEvent] = Field(default_factory=list)
    # Non-powertrain module reads (airbag/ABS/body/…) with their honest outcomes.
    module_scans: list[RecModuleScan] = Field(default_factory=list)

    # ------------------------------------------------------------------ io
    def to_json(self, *, indent: int | None = None) -> str:
        return self.model_dump_json(indent=indent)

    def save(self, path: str | Path, *, indent: int | None = 1) -> Path:
        p = Path(path)
        p.write_text(self.to_json(indent=indent), encoding="utf-8")
        return p

    @classmethod
    def load(cls, path: str | Path) -> Recording:
        return cls.model_validate_json(Path(path).read_text(encoding="utf-8"))

    @classmethod
    def from_obj(cls, obj: dict[str, Any] | str | bytes) -> Recording:
        if isinstance(obj, (str, bytes)):
            obj = json.loads(obj)
        return cls.model_validate(obj)

    # ------------------------------------------------------------------ helpers
    def series(self) -> dict[str, list[tuple[int, float]]]:
        out: dict[str, list[tuple[int, float]]] = {}
        for s in self.samples:
            for k, v in s.values.items():
                if v is not None:
                    out.setdefault(k, []).append((s.t_ms, float(v)))
        return out

    def units(self) -> dict[str, str]:
        return {s.key: s.unit for s in self.signals if s.unit}
