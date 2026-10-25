"""Session data ingestion and the diagnosis → persistence pipeline.

Everything here runs on a *user* connection (RLS applies). The diagnosis
engine is pure: it receives a ``DiagnosticInput`` built from what the session
stored (DTCs, telemetry, manual measurements) or from a recording, so live,
demo and replay data are analysed identically.
"""

from __future__ import annotations

import hashlib
import json
import re
import uuid
from collections.abc import Mapping
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import select, text, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncConnection

from automind.api.deps import Services
from automind.core.crypto import mask_vin
from automind.core.errors import APIError, validation
from automind.db import tables as t
from automind.diagnosis.models import (
    DiagnosisResult,
    DiagnosticInput,
    FreezeFrame,
    InputDTC,
    InputModuleScan,
    Sample,
    UserMeasurement,
    VehicleInfo,
)
from automind.recording.format import Recording

PID_RE = re.compile(r"^[0-9A-F]{4,6}$")
STATUS_SERVICE = {"stored": "03", "pending": "07", "permanent": "0A"}
MAX_SERIES_ROWS = 500_000
TELEMETRY_CHUNK = 1000


# ----------------------------------------------------------------------------- helpers
def ts_window_ok(ts: datetime, now: datetime | None = None) -> bool:
    now = now or datetime.now(UTC)
    return now - timedelta(days=365) <= ts <= now + timedelta(days=1)


def normalize_pid(pid: str) -> str | None:
    p = (pid or "").strip().upper().replace(" ", "")
    if len(p) == 2:
        p = "01" + p
    return p if PID_RE.match(p) else None


def _kb():
    try:
        from automind.diagnosis.kb import get_kb
    except ImportError:  # lead's module not available yet
        return None
    return get_kb()


def kb_describe(code: str) -> dict[str, Any]:
    kb = _kb()
    if kb is None:
        return {}
    d = kb.lookup(code)
    structure = kb.structure(code) if hasattr(kb, "structure") else {}
    out: dict[str, Any] = {"is_generic": structure.get("is_generic")}
    if d:
        out["description_en"] = d.get("en")
        out["description_ar"] = d.get("ar")
        if "is_generic" in d:
            out["is_generic"] = d["is_generic"]
    return out


# ----------------------------------------------------------------------------- sessions
async def insert_session(conn: AsyncConnection, **values: Any) -> Mapping[str, Any]:
    """Insert a diagnostic session and read it back.

    No ``INSERT … RETURNING``: the RLS SELECT policy on diagnostic_sessions is
    ``can_access_session(id)``, a STABLE function whose snapshot cannot see the
    row being inserted, so RETURNING fails with 42501 for normal users.
    """
    sid = values.pop("id", None) or uuid.uuid4()
    await conn.execute(t.diagnostic_sessions.insert().values(id=sid, **values))
    return (await conn.execute(select(t.diagnostic_sessions).where(t.diagnostic_sessions.c.id == sid))).mappings().one()


# ----------------------------------------------------------------------------- ingestion
async def store_dtcs(conn: AsyncConnection, session: Mapping[str, Any], dtcs: list[dict[str, Any]]) -> int:
    seen: set[tuple] = set()
    rows = []
    for d in dtcs:
        code = d["code"].upper()
        key = (code, d["status"], d.get("ecu_address"))
        if key in seen:
            continue
        seen.add(key)
        rows.append(
            {
                "session_id": session["id"],
                "vehicle_id": session["vehicle_id"],
                "code": code,
                "status": d["status"],
                "source_service": d.get("source_service") or STATUS_SERVICE[d["status"]],
                "ecu_address": d.get("ecu_address"),
                "freeze_frame": d.get("freeze_frame"),
                **kb_describe(code),
            }
        )
    if not rows:
        return 0
    # NULL ecu_address does not participate in the unique constraint → skip existing rows explicitly.
    existing = {
        (r.code, r.status, r.ecu_address)
        for r in (
            await conn.execute(
                select(
                    t.diagnostic_trouble_codes.c.code,
                    t.diagnostic_trouble_codes.c.status,
                    t.diagnostic_trouble_codes.c.ecu_address,
                ).where(t.diagnostic_trouble_codes.c.session_id == session["id"])
            )
        ).all()
    }
    rows = [r for r in rows if (r["code"], r["status"], r["ecu_address"]) not in existing]
    if rows:
        cols = {k for r in rows for k in r}
        rows = [{k: r.get(k) for k in cols} for r in rows]
        await conn.execute(pg_insert(t.diagnostic_trouble_codes).on_conflict_do_nothing(), rows)
    return len(rows)


async def store_telemetry(conn: AsyncConnection, rows: list[dict[str, Any]]) -> int:
    for i in range(0, len(rows), TELEMETRY_CHUNK):
        await conn.execute(pg_insert(t.telemetry_readings).on_conflict_do_nothing(), rows[i : i + TELEMETRY_CHUNK])
    return len(rows)


def recording_dtc_rows(rec: Recording) -> list[dict[str, Any]]:
    frames = {f.dtc: f.values for f in rec.freeze_frames if f.dtc}
    return [
        {
            "code": d.code,
            "status": d.status,
            "ecu_address": d.ecu,
            "freeze_frame": ({"values": frames[d.code]} if d.code in frames else None),
        }
        for d in rec.dtcs
    ]


def recording_telemetry_rows(rec: Recording, session_id: uuid.UUID, started_at: datetime) -> list[dict[str, Any]]:
    units = rec.units()
    now = datetime.now(UTC)
    rows = []
    for s in rec.samples:
        pid = normalize_pid(s.pid)
        if pid is None:
            continue
        ts = started_at + timedelta(milliseconds=s.t_ms)
        if not ts_window_ok(ts, now):
            continue
        for signal, value in s.values.items():
            if value is None:
                continue
            rows.append(
                {
                    "session_id": session_id,
                    "ts": ts,
                    "pid": pid,
                    "signal": signal,
                    "value": float(value),
                    "unit": units.get(signal),
                    "ecu_address": s.ecu,
                }
            )
    return rows


def parse_recording(payload: Any) -> Recording:
    try:
        return Recording.from_obj(payload)
    except Exception as exc:  # pydantic.ValidationError / JSON errors
        errors = []
        if hasattr(exc, "errors"):
            errors = [{"loc": [str(p) for p in e.get("loc", ())], "msg": e.get("msg", "")} for e in exc.errors()[:20]]
        raise validation("invalid recording (automind.recording.v1)", {"errors": errors}) from exc


def recording_payload(rec: Recording) -> tuple[dict[str, Any], bytes]:
    """JSON payload to store. The VIN is never stored in clear text inside recordings."""
    data = rec.model_dump(mode="json")
    vin = (data.get("vehicle") or {}).get("vin")
    if vin:
        data["vehicle"]["vin"] = mask_vin(vin)
    raw = json.dumps(data, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return data, raw


async def store_recording(
    conn: AsyncConnection,
    svc: Services,
    user_id: uuid.UUID,
    rec: Recording,
    *,
    session: Mapping[str, Any] | None = None,
    data_mode: str | None = None,
) -> Mapping[str, Any]:
    data, raw = recording_payload(rec)
    if len(raw) >= svc.settings.max_inline_recording_bytes:
        raise APIError(
            413,
            "payload_too_large",
            "recordings of 1 MB or more need object storage, which is not available yet",
            {"size_bytes": len(raw), "max_bytes": svc.settings.max_inline_recording_bytes},
        )
    signals = [s.key for s in rec.signals] or sorted(rec.series())
    return (
        (
            await conn.execute(
                t.telemetry_recordings.insert()
                .values(
                    session_id=session["id"] if session else None,
                    user_id=user_id,
                    vehicle_id=session["vehicle_id"] if session else None,
                    data_mode=data_mode or rec.data_mode,
                    duration_ms=rec.duration_ms,
                    sample_count=len(rec.samples),
                    signals=signals,
                    inline_payload=data,
                    size_bytes=len(raw),
                    sha256=hashlib.sha256(raw).hexdigest(),
                )
                .returning(t.telemetry_recordings)
            )
        )
        .mappings()
        .one()
    )


async def store_readiness(conn: AsyncConnection, session: Mapping[str, Any], readiness: dict[str, Any]) -> Mapping[str, Any]:
    """Keep the readiness-monitor snapshot in the session summary; returns the updated row mapping."""
    summary = dict(session["summary"] or {})
    summary["readiness"] = readiness
    await conn.execute(
        update(t.diagnostic_sessions).where(t.diagnostic_sessions.c.id == session["id"]).values(summary=summary)
    )
    return {**dict(session), "summary": summary}


async def ingest_recording_into_session(conn: AsyncConnection, session: Mapping[str, Any], rec: Recording) -> None:
    """Derive DTC and telemetry rows from a recording unless they were uploaded separately."""
    if rec.readiness:
        await store_readiness(conn, session, rec.readiness)
    has_dtcs = (
        await conn.execute(
            select(t.diagnostic_trouble_codes.c.id).where(t.diagnostic_trouble_codes.c.session_id == session["id"]).limit(1)
        )
    ).first()
    if not has_dtcs:
        await store_dtcs(conn, session, recording_dtc_rows(rec))
    has_tel = (
        await conn.execute(select(t.telemetry_readings.c.ts).where(t.telemetry_readings.c.session_id == session["id"]).limit(1))
    ).first()
    if not has_tel:
        await store_telemetry(conn, recording_telemetry_rows(rec, session["id"], session["started_at"]))
    # Non-powertrain module reads have no dedicated table; carry their honest outcomes
    # in the session summary so the live /complete path reports them (migration-free).
    if rec.module_scans:
        summary = dict(session["summary"] or {})
        if "module_scans" not in summary:
            summary["module_scans"] = [m.model_dump(mode="json") for m in rec.module_scans]
            await conn.execute(
                update(t.diagnostic_sessions)
                .where(t.diagnostic_sessions.c.id == session["id"])
                .values(summary=summary)
            )


# ----------------------------------------------------------------------------- diagnostic input
async def vehicle_info(conn: AsyncConnection, vehicle_id: uuid.UUID | None) -> VehicleInfo:
    if vehicle_id is None:
        return VehicleInfo()
    v = (
        (
            await conn.execute(
                select(
                    t.vehicles.c.make,
                    t.vehicles.c.model,
                    t.vehicles.c.model_year,
                    t.vehicles.c.engine,
                    t.vehicles.c.fuel_type,
                ).where(t.vehicles.c.id == vehicle_id)
            )
        )
        .mappings()
        .first()
    )
    return VehicleInfo(**v) if v else VehicleInfo()


def session_measurements(session: Mapping[str, Any]) -> list[UserMeasurement]:
    out = []
    for m in (session["summary"] or {}).get("measurements", []):
        try:
            out.append(UserMeasurement(**{k: m.get(k) for k in ("key", "value", "unit", "note")}))
        except Exception:  # noqa: BLE001,S112 - skip malformed legacy rows
            continue
    return out


def session_module_scans(session: Mapping[str, Any]) -> list[InputModuleScan]:
    """Module reads stored in the session summary (by recording ingestion)."""
    out = []
    for m in (session["summary"] or {}).get("module_scans", []):
        try:
            out.append(InputModuleScan.model_validate(m))
        except Exception:  # noqa: BLE001,S112 - skip malformed rows, never fail the diagnosis
            continue
    return out


async def build_input_from_db(conn: AsyncConnection, session: Mapping[str, Any], mil_on: bool | None = None) -> DiagnosticInput:
    sid = session["id"]
    dtc_rows = (
        (
            await conn.execute(
                select(t.diagnostic_trouble_codes)
                .where(t.diagnostic_trouble_codes.c.session_id == sid)
                .order_by(t.diagnostic_trouble_codes.c.detected_at)
            )
        )
        .mappings()
        .all()
    )
    dtcs = [InputDTC(code=r["code"], status=r["status"], ecu=r["ecu_address"]) for r in dtc_rows]
    frames = []
    for r in dtc_rows:
        ff = r["freeze_frame"]
        if isinstance(ff, dict):
            values = ff.get("values", ff)
            clean = {k: (float(v) if isinstance(v, (int, float)) else None) for k, v in values.items() if isinstance(k, str)}
            frames.append(FreezeFrame(dtc=r["code"], values=clean))

    tel = (
        await conn.execute(
            select(
                t.telemetry_readings.c.ts,
                t.telemetry_readings.c.signal,
                t.telemetry_readings.c.value,
                t.telemetry_readings.c.unit,
            )
            .where(t.telemetry_readings.c.session_id == sid, t.telemetry_readings.c.value.isnot(None))
            .order_by(t.telemetry_readings.c.ts)
            .limit(MAX_SERIES_ROWS)
        )
    ).all()
    series: dict[str, list[Sample]] = {}
    units: dict[str, str] = {}
    duration = 0
    if tel:
        base = min(session["started_at"], tel[0].ts)
        for r in tel:
            ms = int((r.ts - base).total_seconds() * 1000)
            series.setdefault(r.signal, []).append(Sample(t_ms=ms, value=r.value))
            if r.unit:
                units.setdefault(r.signal, r.unit)
            duration = max(duration, ms)
    return DiagnosticInput(
        data_mode=session["data_mode"],
        vehicle=await vehicle_info(conn, session["vehicle_id"]),
        dtcs=dtcs,
        freeze_frames=frames,
        series=series,
        units=units,
        supported_signals=sorted(series),
        measurements=session_measurements(session),
        mil_on=mil_on if mil_on is not None else session["mil_on"],
        duration_ms=duration,
        module_scans=session_module_scans(session),
    )


# ----------------------------------------------------------------------------- diagnosis
async def run_engine(svc: Services, inp: DiagnosticInput, language: str, use_llm: bool) -> DiagnosisResult:
    from automind.diagnosis.engine import diagnose_async

    llm_enabled = bool(use_llm and svc.settings.anthropic_api_key)
    client = None
    if llm_enabled:
        import anthropic

        key = svc.settings.anthropic_api_key.get_secret_value()  # type: ignore[union-attr]
        client = anthropic.AsyncAnthropic(api_key=key)
    return await diagnose_async(inp, language=language, use_llm=llm_enabled, llm_client=client)


def _llm_cost(llm) -> float | None:
    try:
        from automind.diagnosis.llm import estimate_cost_usd
    except ImportError:
        return None
    try:
        return estimate_cost_usd(llm.model, llm.input_tokens, llm.output_tokens)
    except Exception:  # noqa: BLE001 - unknown model pricing: leave cost empty rather than guess
        return None


def _input_sha(inp: DiagnosticInput, result: DiagnosisResult) -> str:
    if result.input_sha256:
        return result.input_sha256
    return hashlib.sha256(inp.model_dump_json().encode()).hexdigest()


def _clip01(v: float | None) -> float | None:
    return None if v is None else max(0.0, min(1.0, round(float(v), 3)))


async def persist_diagnosis(
    conn: AsyncConnection,
    session: Mapping[str, Any],
    inp: DiagnosticInput,
    result: DiagnosisResult,
    language: str,
    *,
    complete: bool = False,
    mil_on: bool | None = None,
    odometer_km: int | None = None,
) -> dict[str, Any]:
    sid = session["id"]
    result_json = result.model_dump(mode="json")
    llm = result.llm

    diag_id = (
        await conn.execute(
            t.ai_diagnoses.insert()
            .values(
                session_id=sid,
                engine="hybrid" if llm else "rules",
                engine_version=result.engine_version,
                model=llm.model if llm else None,
                prompt_version=llm.prompt_version if llm else None,
                language=language,
                input_sha256=_input_sha(inp, result),
                summary_owner=getattr(result.summary, language),
                summary_technician=getattr(result.technician_summary, language),
                probable_causes=sorted(
                    ({"finding": f.rule_id, **c.model_dump(mode="json")} for f in result.findings for c in f.causes),
                    key=lambda c: -c["likelihood"],
                ),
                recommended_tests=[{"finding": f.rule_id, **x.model_dump(mode="json")} for f in result.findings for x in f.tests],
                repair_actions=[{"finding": f.rule_id, **x.model_dump(mode="json")} for f in result.findings for x in f.actions],
                parts_candidates=[
                    {"finding": f.rule_id, **x.model_dump(mode="json")} for f in result.findings for x in f.parts_candidates
                ],
                missing_data=[
                    {"finding": f.rule_id, **x.model_dump(mode="json")} for f in result.findings for x in f.missing_data
                ],
                overall_confidence=_clip01(max((f.confidence for f in result.findings), default=None)),
                input_tokens=llm.input_tokens if llm else None,
                output_tokens=llm.output_tokens if llm else None,
                latency_ms=llm.latency_ms if llm else None,
                cost_usd=_llm_cost(llm) if llm else None,
                status="completed",
            )
            .returning(t.ai_diagnoses.c.id)
        )
    ).scalar_one()

    evidence_rows: list[dict[str, Any]] = []
    for f in result.findings:
        fid = (
            await conn.execute(
                t.diagnostic_findings.insert()
                .values(
                    session_id=sid,
                    rule_id=f.rule_id,
                    rule_version=f.rule_version,
                    system=f.system,
                    title_en=f.title_en,
                    title_ar=f.title_ar,
                    severity=f.severity,
                    status=f.status,
                    confidence=_clip01(f.confidence),
                    related_dtcs=f.related_dtcs,
                    details={
                        "finding_key": f.id,
                        "diagnosis_id": str(diag_id),
                        "causes": [c.model_dump(mode="json") for c in f.causes],
                        "tests": [x.model_dump(mode="json") for x in f.tests],
                        "actions": [x.model_dump(mode="json") for x in f.actions],
                        "parts_candidates": [x.model_dump(mode="json") for x in f.parts_candidates],
                        "missing_data": [x.model_dump(mode="json") for x in f.missing_data],
                    },
                )
                .returning(t.diagnostic_findings.c.id)
            )
        ).scalar_one()
        for e in f.evidence:
            evidence_rows.append(
                {
                    "session_id": sid,
                    "finding_id": fid,
                    "diagnosis_id": diag_id,
                    "kind": e.kind,
                    "is_measured": e.is_measured,
                    "signal": e.signal,
                    "observed_value": e.observed_value,
                    "observed_text": e.observed_text,
                    "unit": e.unit,
                    "expected_min": e.expected_min,
                    "expected_max": e.expected_max,
                    "expected_context": e.expected_context,
                    "assessment": e.assessment,
                    "weight": _clip01(e.weight),
                    "note_en": e.note_en,
                    "note_ar": e.note_ar,
                }
            )
    if evidence_rows:
        await conn.execute(t.diagnosis_evidence.insert(), evidence_rows)

    summary = dict(session["summary"] or {})
    summary["latest_diagnosis"] = result_json
    summary["latest_diagnosis_id"] = str(diag_id)
    values: dict[str, Any] = {
        "health_score": result.health_score,
        "summary": summary,
        "dtc_count": min(len(result.dtcs), 32767),
        "engine_version": result.engine_version,
        "kb_version": result.kb_version,
    }
    if mil_on is not None:
        values["mil_on"] = mil_on
    elif inp.mil_on is not None:
        values["mil_on"] = inp.mil_on
    if odometer_km is not None:
        values["odometer_km"] = odometer_km
    if complete:
        values["status"] = "completed"
        if session["completed_at"] is None:
            values["completed_at"] = datetime.now(UTC)
    await conn.execute(update(t.diagnostic_sessions).where(t.diagnostic_sessions.c.id == sid).values(**values))
    await conn.execute(text("select automind.refresh_session_aggregates(:sid)"), {"sid": sid})
    return result_json


async def diagnose_session(
    conn: AsyncConnection,
    svc: Services,
    session: Mapping[str, Any],
    *,
    language: str,
    use_llm: bool,
    complete: bool = False,
    mil_on: bool | None = None,
    odometer_km: int | None = None,
    inp: DiagnosticInput | None = None,
) -> dict[str, Any]:
    if inp is None:
        inp = await build_input_from_db(conn, session, mil_on=mil_on)
    result = await run_engine(svc, inp, language, use_llm)
    return await persist_diagnosis(
        conn, session, inp, result, language, complete=complete, mil_on=mil_on, odometer_km=odometer_km
    )


def input_from_recording(
    rec: Recording, data_mode: str | None, measurements: list[UserMeasurement] | None = None
) -> DiagnosticInput:
    from automind.diagnosis.input_builder import from_recording

    return from_recording(rec, data_mode=data_mode, measurements=measurements)
