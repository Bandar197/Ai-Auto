"""Build a DiagnosticInput from the different data sources."""

from __future__ import annotations

from collections.abc import Iterable
from typing import Literal

from automind.diagnosis.models import (
    DiagnosticInput,
    FreezeFrame,
    InputDTC,
    InputModuleScan,
    Sample,
    UserMeasurement,
    VehicleInfo,
)
from automind.recording.format import Recording


def from_recording(
    rec: Recording,
    data_mode: Literal["live", "demo", "replay"] | None = None,
    measurements: Iterable[UserMeasurement | dict] | None = None,
    vehicle: VehicleInfo | None = None,
) -> DiagnosticInput:
    """`data_mode=None` keeps the recording's own mode; pass 'replay' when re-analysing a stored recording."""
    series: dict[str, list[Sample]] = {}
    for s in rec.samples:
        for k, v in s.values.items():
            if v is not None:
                series.setdefault(k, []).append(Sample(t_ms=s.t_ms, value=float(v)))
    mil = None
    if "mil_on" in series and series["mil_on"]:
        mil = bool(series["mil_on"][-1].value)
    ms = [m if isinstance(m, UserMeasurement) else UserMeasurement(**m) for m in (measurements or [])]
    return DiagnosticInput(
        data_mode=data_mode or rec.data_mode,
        vehicle=vehicle or VehicleInfo(make=rec.vehicle.make, model=rec.vehicle.model, model_year=rec.vehicle.model_year),
        dtcs=[InputDTC(code=d.code, status=d.status, ecu=d.ecu) for d in rec.dtcs],
        freeze_frames=[FreezeFrame(dtc=f.dtc, values=f.values) for f in rec.freeze_frames],
        series=series,
        units=rec.units(),
        supported_signals=sorted(series),
        measurements=ms,
        mil_on=mil,
        duration_ms=rec.duration_ms,
        module_scans=[
            InputModuleScan(
                key=m.key, name_en=m.name_en, name_ar=m.name_ar, category=m.category,
                address=m.address, outcome=m.outcome,
                codes=[InputDTC(code=c.code, status=c.status, ecu=c.ecu) for c in m.codes],
            )
            for m in rec.module_scans
        ],
    )
