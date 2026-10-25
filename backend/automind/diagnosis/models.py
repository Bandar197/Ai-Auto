"""Data contracts of the diagnosis engine.

These models are the source of truth for `diagnosis_result` in docs/API.md.
The engine never fetches data itself: callers (API, CLI, tests) build a
`DiagnosticInput` from a live session, a demo simulation or a replayed
recording, which guarantees identical analysis in all three modes.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Literal

from pydantic import BaseModel, Field

DataMode = Literal["live", "demo", "replay"]
Severity = Literal["info", "low", "medium", "high", "critical"]
FindingStatus = Literal["suspected", "likely", "confirmed", "ruled_out", "inconclusive"]
System = Literal[
    "engine", "fuel", "ignition", "air_intake", "cooling", "charging",
    "emissions", "transmission", "ac", "electrical", "network", "other",
]
Assessment = Literal["normal", "abnormal", "inconclusive", "supports", "contradicts"]
# Honest per-module read outcome. A module that did not answer or refused is never
# collapsed into "no faults": only read_codes / read_no_codes mean the module was read.
ModuleOutcome = Literal["read_codes", "read_no_codes", "refused", "no_response"]
EvidenceKind = Literal[
    "dtc", "pid_reading", "pid_statistic", "freeze_frame",
    "user_measurement", "technician_note", "kb_reference", "missing_data",
]


class Bilingual(BaseModel):
    en: str
    ar: str


# --------------------------------------------------------------------------- input
class InputDTC(BaseModel):
    code: str
    status: Literal["stored", "pending", "permanent"] = "stored"
    ecu: str | None = None


class FreezeFrame(BaseModel):
    dtc: str | None = None
    values: dict[str, float | None] = Field(default_factory=dict)


class Sample(BaseModel):
    t_ms: int
    value: float


class UserMeasurement(BaseModel):
    key: str  # e.g. "ac_low_side_pressure"
    value: float
    unit: str
    note: str | None = None


class VehicleInfo(BaseModel):
    make: str | None = None
    model: str | None = None
    model_year: int | None = None
    engine: str | None = None
    fuel_type: str | None = None


class InputModuleScan(BaseModel):
    """An honest per-module read outcome (SRS/ABS/body/… over UDS, or any ECU).

    ``outcome`` is carried verbatim from the scan: a module that did not answer
    (``no_response``) or refused (``refused``, e.g. a security gateway) is reported
    as such and never shown as "no faults". Only ``read_codes`` / ``read_no_codes``
    mean the module was actually read.
    """

    key: str
    name_en: str
    name_ar: str
    category: str = "other"  # airbag / abs / body / network / …
    address: str | None = None  # CAN request id if known, e.g. "7D0"
    outcome: ModuleOutcome
    codes: list[InputDTC] = Field(default_factory=list)


class DiagnosticInput(BaseModel):
    data_mode: DataMode
    vehicle: VehicleInfo = Field(default_factory=VehicleInfo)
    dtcs: list[InputDTC] = Field(default_factory=list)
    freeze_frames: list[FreezeFrame] = Field(default_factory=list)
    # signal key (see shared/obd/pids.json output keys) -> time series
    series: dict[str, list[Sample]] = Field(default_factory=dict)
    units: dict[str, str] = Field(default_factory=dict)
    supported_signals: list[str] = Field(default_factory=list)
    measurements: list[UserMeasurement] = Field(default_factory=list)
    mil_on: bool | None = None
    duration_ms: int = 0
    # Non-powertrain module reads (airbag/ABS/body/…) with their honest outcomes.
    module_scans: list[InputModuleScan] = Field(default_factory=list)


# --------------------------------------------------------------------------- output
class Evidence(BaseModel):
    id: str
    kind: EvidenceKind
    is_measured: bool  # True = observed data; False = inference / reference / missing
    signal: str | None = None
    observed_value: float | None = None
    observed_text: str | None = None
    unit: str | None = None
    expected_min: float | None = None
    expected_max: float | None = None
    expected_context: str | None = None
    assessment: Assessment
    weight: float = Field(0.5, ge=0, le=1)
    note_en: str | None = None
    note_ar: str | None = None


class Cause(BaseModel):
    key: str
    title_en: str
    title_ar: str
    likelihood: float = Field(ge=0, le=1)
    rank: int = 0
    supporting_evidence: list[str] = Field(default_factory=list)
    contradicting_evidence: list[str] = Field(default_factory=list)


class TestStep(BaseModel):
    __test__ = False  # not a pytest class
    key: str
    title_en: str
    title_ar: str
    how_en: str
    how_ar: str
    expected_en: str | None = None
    expected_ar: str | None = None
    tools: list[str] = Field(default_factory=list)


class Action(BaseModel):
    title_en: str
    title_ar: str
    after_test: str | None = None


class PartCandidate(BaseModel):
    name_en: str
    name_ar: str
    category: str
    requires_confirmation: bool = True
    condition_en: str
    condition_ar: str


class MissingData(BaseModel):
    signal: str | None = None
    description_en: str
    description_ar: str


class Finding(BaseModel):
    id: str
    rule_id: str
    rule_version: str
    system: System
    title_en: str
    title_ar: str
    severity: Severity
    status: FindingStatus
    confidence: float = Field(ge=0, le=1)
    related_dtcs: list[str] = Field(default_factory=list)
    causes: list[Cause] = Field(default_factory=list)
    evidence: list[Evidence] = Field(default_factory=list)
    tests: list[TestStep] = Field(default_factory=list)
    actions: list[Action] = Field(default_factory=list)
    parts_candidates: list[PartCandidate] = Field(default_factory=list)
    missing_data: list[MissingData] = Field(default_factory=list)


class DTCResult(BaseModel):
    code: str
    status: str
    ecu: str | None = None
    description_en: str | None = None
    description_ar: str | None = None
    system: str | None = None
    severity: Severity = "medium"
    known: bool = False  # False → code not in the knowledge base (no description invented)


class SystemStatus(BaseModel):
    system: System
    status: Literal["ok", "warning", "fault", "unknown"]
    note_en: str
    note_ar: str


class ModuleCode(BaseModel):
    code: str
    description_en: str | None = None
    description_ar: str | None = None
    known: bool = False  # False → not in the knowledge base (no description invented)


class ModuleScanResult(BaseModel):
    """Report view of a module read — the outcome drives how it is shown.

    ``read_ok`` is True only for ``read_codes``/``read_no_codes``; a ``refused`` or
    ``no_response`` module is never rendered as healthy.
    """

    key: str
    name_en: str
    name_ar: str
    category: str = "other"
    address: str | None = None
    outcome: ModuleOutcome
    read_ok: bool
    codes: list[ModuleCode] = Field(default_factory=list)


class DataQuality(BaseModel):
    signals: list[str] = Field(default_factory=list)
    sample_count: int = 0
    duration_s: float = 0
    conditions_seen: list[str] = Field(default_factory=list)
    warnings: list[Bilingual] = Field(default_factory=list)


class LLMNarrative(BaseModel):
    model: str
    prompt_version: str
    narrative_en: str
    narrative_ar: str
    input_tokens: int = 0
    output_tokens: int = 0
    latency_ms: int = 0


class DiagnosisResult(BaseModel):
    engine_version: str
    kb_version: str
    data_mode: DataMode
    generated_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    health_score: int = Field(ge=0, le=100)
    health_band: Literal["good", "fair", "attention", "critical"]
    summary: Bilingual
    technician_summary: Bilingual
    dtcs: list[DTCResult] = Field(default_factory=list)
    findings: list[Finding] = Field(default_factory=list)
    system_status: list[SystemStatus] = Field(default_factory=list)
    module_scans: list[ModuleScanResult] = Field(default_factory=list)
    data_quality: DataQuality = Field(default_factory=DataQuality)
    disclaimers: list[Bilingual] = Field(default_factory=list)
    llm: LLMNarrative | None = None
    input_sha256: str = ""
