"""Diagnostic sessions: ingestion, diagnosis, telemetry, reports and shares."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any, Literal

from fastapi import APIRouter, Body, Query, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import func, or_, select, update

from automind.api import pipeline
from automind.api.access import ensure_connection, ensure_device, get_recording, get_session, get_vehicle
from automind.api.audit import audit
from automind.api.deps import CtxDep, CurrentUser, Page, SvcDep, page
from automind.api.serializers import decrypt_vin, recording_meta_out, session_out, share_out
from automind.core.crypto import mask_vin
from automind.core.errors import conflict, forbidden, not_found, validation
from automind.db import tables as t

router = APIRouter(prefix="/sessions", tags=["sessions"])

DataMode = Literal["live", "demo", "replay"]
Lang = Literal["ar", "en"]


class SessionIn(BaseModel):
    data_mode: DataMode
    vehicle_id: uuid.UUID | None = None
    device_id: uuid.UUID | None = None
    connection_id: uuid.UUID | None = None
    demo_scenario_key: str | None = Field(None, max_length=60, pattern=r"^[a-z0-9_]+$")
    source_recording_id: uuid.UUID | None = None
    protocol_name: str | None = Field(None, max_length=100)
    app_platform: str | None = Field(None, max_length=30)
    app_version: str | None = Field(None, max_length=30)

    @model_validator(mode="after")
    def _mode(self) -> SessionIn:
        if self.data_mode == "demo" and not self.demo_scenario_key:
            raise ValueError("demo sessions need demo_scenario_key")
        if self.data_mode == "replay" and not self.source_recording_id:
            raise ValueError("replay sessions need source_recording_id")
        if self.data_mode != "demo" and self.demo_scenario_key:
            raise ValueError("demo_scenario_key is only valid for demo sessions")
        return self


class DtcIn(BaseModel):
    code: str = Field(pattern=r"^[PCBU][0-9A-F]{4}$")
    status: Literal["stored", "pending", "permanent"]
    source_service: Literal["03", "07", "0A"]
    ecu_address: str | None = Field(None, max_length=8, pattern=r"^[0-9A-Fa-f]{2,8}$")
    freeze_frame: dict[str, Any] | None = None


class DtcsIn(BaseModel):
    dtcs: list[DtcIn] = Field(max_length=500)


class SampleIn(BaseModel):
    ts: datetime
    pid: str = Field(pattern=r"^[0-9A-Fa-f]{4,6}$")
    signal: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9_]+$")
    value: float | None
    unit: str | None = Field(None, max_length=20)
    ecu_address: str | None = Field(None, max_length=8)


class TelemetryIn(BaseModel):
    samples: list[SampleIn] = Field(max_length=5000)


class MeasurementIn(BaseModel):
    key: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9_]+$")
    value: float
    unit: str = Field(min_length=1, max_length=20)
    note: str | None = Field(None, max_length=500)


class MeasurementsIn(BaseModel):
    measurements: list[MeasurementIn] = Field(min_length=1, max_length=100)


class CompleteIn(BaseModel):
    mil_on: bool | None = None
    # service 01 PID 01 decoded on the device (readiness monitors) — used by clear-and-verify
    readiness: dict[str, Any] | None = None
    odometer_km: int | None = Field(None, ge=0, le=5_000_000)
    language: Lang = "ar"
    use_llm: bool = False


class DiagnoseIn(BaseModel):
    language: Lang = "ar"
    use_llm: bool = False


class ShareIn(BaseModel):
    organization_id: uuid.UUID
    include_vin: bool = False
    include_live_data: bool = True
    consent_version: str = Field(min_length=1, max_length=50)
    expires_in_days: int = Field(30, ge=1, le=365)


def _visible_cond(user_id: uuid.UUID):
    s = t.diagnostic_sessions.c
    return or_(s.user_id == user_id, s.organization_id.isnot(None) & func.automind.is_org_member(s.organization_id))


def _require_open(session) -> None:
    if session["status"] != "in_progress":
        raise conflict("session is not in progress", {"status": session["status"]})


@router.post("", status_code=201)
async def create_session(body: SessionIn, user: CurrentUser, svc: SvcDep) -> dict:
    async with svc.db.user(user.id) as conn:
        if body.vehicle_id:
            await get_vehicle(conn, body.vehicle_id)
            if not (await conn.execute(select(func.automind.can_write_vehicle(body.vehicle_id)))).scalar():
                raise forbidden("you cannot start a session for this vehicle")
        await ensure_device(conn, body.device_id)
        await ensure_connection(conn, body.connection_id)
        if body.source_recording_id:
            await get_recording(conn, body.source_recording_id)
        row = await pipeline.insert_session(conn, user_id=user.id, **body.model_dump())
    return session_out(row)


@router.get("")
async def list_sessions(
    user: CurrentUser,
    svc: SvcDep,
    p: Page,
    vehicle_id: uuid.UUID | None = None,
    data_mode: DataMode | None = None,
) -> dict:
    cond = _visible_cond(user.id)
    if vehicle_id:
        cond = cond & (t.diagnostic_sessions.c.vehicle_id == vehicle_id)
    if data_mode:
        cond = cond & (t.diagnostic_sessions.c.data_mode == data_mode)
    async with svc.db.user(user.id) as conn:
        total = (await conn.execute(select(func.count()).select_from(t.diagnostic_sessions).where(cond))).scalar_one()
        rows = (
            (
                await conn.execute(
                    select(t.diagnostic_sessions)
                    .where(cond)
                    .order_by(t.diagnostic_sessions.c.started_at.desc())
                    .limit(p.limit)
                    .offset(p.offset)
                )
            )
            .mappings()
            .all()
        )
    return page([session_out(r) for r in rows], total, p)


@router.get("/{session_id}")
async def get_session_ep(session_id: uuid.UUID, user: CurrentUser, svc: SvcDep) -> dict:
    async with svc.db.user(user.id) as conn:
        row = await get_session(conn, session_id)
    return session_out(row)


@router.post("/{session_id}/dtcs", status_code=204)
async def add_dtcs(session_id: uuid.UUID, body: DtcsIn, user: CurrentUser, svc: SvcDep) -> Response:
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id, write=True)
        _require_open(s)
        await pipeline.store_dtcs(conn, s, [d.model_dump() for d in body.dtcs])
        count = (
            await conn.execute(
                select(func.count(func.distinct(t.diagnostic_trouble_codes.c.code))).where(
                    t.diagnostic_trouble_codes.c.session_id == session_id
                )
            )
        ).scalar_one()
        await conn.execute(
            update(t.diagnostic_sessions).where(t.diagnostic_sessions.c.id == session_id).values(dtc_count=min(count, 32767))
        )
    return Response(status_code=204)


@router.post("/{session_id}/telemetry")
async def add_telemetry(session_id: uuid.UUID, body: TelemetryIn, user: CurrentUser, svc: SvcDep) -> dict:
    now = datetime.now(UTC)
    rows = []
    for i, smp in enumerate(body.samples):
        ts = smp.ts if smp.ts.tzinfo else smp.ts.replace(tzinfo=UTC)
        if not pipeline.ts_window_ok(ts, now):
            raise validation("sample timestamp outside the accepted window (-1 year … +1 day)", {"index": i, "field": "ts"})
        rows.append(
            {
                "session_id": session_id,
                "ts": ts,
                "pid": smp.pid.upper(),
                "signal": smp.signal,
                "value": smp.value,
                "unit": smp.unit,
                "ecu_address": smp.ecu_address,
            }
        )
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id, write=True)
        _require_open(s)
        await pipeline.store_telemetry(conn, rows)
    return {"accepted": len(rows)}


@router.post("/{session_id}/recording", status_code=201)
async def attach_recording(session_id: uuid.UUID, user: CurrentUser, svc: SvcDep, payload: dict[str, Any] = Body(...)) -> dict:  # noqa: B008
    rec = pipeline.parse_recording(payload)
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id, write=True)
        if rec.data_mode != s["data_mode"]:
            raise validation(
                "recording data_mode does not match the session",
                {"field": "data_mode", "recording": rec.data_mode, "session": s["data_mode"]},
            )
        _require_open(s)
        row = await pipeline.store_recording(conn, svc, user.id, rec, session=s)
        await pipeline.ingest_recording_into_session(conn, s, rec)
        if not s["protocol_name"] and rec.source.protocol_name:
            await conn.execute(
                update(t.diagnostic_sessions)
                .where(t.diagnostic_sessions.c.id == session_id)
                .values(protocol_name=rec.source.protocol_name)
            )
    return recording_meta_out(row)


@router.post("/{session_id}/measurements", status_code=204)
async def add_measurements(session_id: uuid.UUID, body: MeasurementsIn, user: CurrentUser, svc: SvcDep) -> Response:
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id, write=True, for_update=True)
        summary = dict(s["summary"] or {})
        items = list(summary.get("measurements", []))
        stamp = datetime.now(UTC).isoformat()
        items.extend({**m.model_dump(), "recorded_at": stamp} for m in body.measurements)
        if len(items) > 500:
            raise validation("too many measurements for one session (max 500)")
        summary["measurements"] = items
        await conn.execute(update(t.diagnostic_sessions).where(t.diagnostic_sessions.c.id == session_id).values(summary=summary))
    return Response(status_code=204)


@router.post("/{session_id}/complete")
async def complete_session(session_id: uuid.UUID, user: CurrentUser, svc: SvcDep, body: CompleteIn | None = None) -> dict:
    body = body or CompleteIn()
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id, write=True, for_update=True)
        if s["status"] in ("failed", "cancelled"):
            raise conflict("session cannot be completed", {"status": s["status"]})
        if body.readiness is not None:
            s = await pipeline.store_readiness(conn, s, body.readiness)
        return await pipeline.diagnose_session(
            conn,
            svc,
            s,
            language=body.language,
            use_llm=body.use_llm,
            complete=True,
            mil_on=body.mil_on,
            odometer_km=body.odometer_km,
        )


@router.post("/{session_id}/diagnose")
async def rediagnose(session_id: uuid.UUID, user: CurrentUser, svc: SvcDep, body: DiagnoseIn | None = None) -> dict:
    body = body or DiagnoseIn()
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id, write=True, for_update=True)
        inp = None
        if s["data_mode"] == "replay" and s["source_recording_id"]:
            rec_row = await get_recording(conn, s["source_recording_id"])
            rec = pipeline.parse_recording(rec_row["inline_payload"])
            inp = pipeline.input_from_recording(rec, "replay", pipeline.session_measurements(s) or None)
        return await pipeline.diagnose_session(conn, svc, s, language=body.language, use_llm=body.use_llm, inp=inp)


@router.get("/{session_id}/diagnosis")
async def latest_diagnosis(session_id: uuid.UUID, user: CurrentUser, svc: SvcDep) -> dict:
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id)
    latest = (s["summary"] or {}).get("latest_diagnosis")
    if not latest:
        raise not_found("diagnosis")
    return latest


@router.get("/{session_id}/telemetry")
async def telemetry_series(
    session_id: uuid.UUID, user: CurrentUser, svc: SvcDep, signals: str | None = Query(None, max_length=1000)
) -> dict:
    wanted = [x.strip() for x in signals.split(",") if x.strip()] if signals else None
    tr = t.telemetry_readings.c
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id)
        if not await _live_data_allowed(conn, s, user.id):
            raise forbidden("live data was not shared with your organisation")
        stmt = select(tr.ts, tr.signal, tr.value, tr.unit).where(tr.session_id == session_id)
        if wanted:
            stmt = stmt.where(tr.signal.in_(wanted))
        rows = (await conn.execute(stmt.order_by(tr.ts).limit(pipeline.MAX_SERIES_ROWS))).all()
    base = s["started_at"]
    series: dict[str, list[dict]] = {}
    units: dict[str, str | None] = {}
    for r in rows:
        series.setdefault(r.signal, []).append({"t": int((r.ts - base).total_seconds() * 1000), "v": r.value})
        units.setdefault(r.signal, r.unit)
    return {"session_id": str(session_id), "data_mode": s["data_mode"], "series": series, "units": units}


async def _active_share_for_user(conn, session_id: uuid.UUID) -> Any:
    """The active share (visible through RLS only to members of the target org)."""
    rs = t.report_shares.c
    return (
        (
            await conn.execute(
                select(t.report_shares)
                .where(
                    rs.session_id == session_id,
                    rs.revoked_at.is_(None),
                    rs.expires_at > func.now(),
                    func.automind.is_org_member(rs.shared_with_org_id),
                )
                .limit(1)
            )
        )
        .mappings()
        .first()
    )


async def _live_data_allowed(conn, s, user_id: uuid.UUID) -> bool:
    if s["user_id"] == user_id:
        return True
    share = await _active_share_for_user(conn, s["id"])
    return share is None or bool(share["include_live_data"])


@router.get("/{session_id}/report", response_model=None)
async def report(
    session_id: uuid.UUID,
    user: CurrentUser,
    svc: SvcDep,
    format: Literal["json", "html"] = "json",
    lang: Lang = "ar",
) -> Any:  # noqa: A002
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id)
        latest = (s["summary"] or {}).get("latest_diagnosis")
        if not latest:
            raise not_found("diagnosis")
        is_owner = s["user_id"] == user.id
        share = None if is_owner else await _active_share_for_user(conn, session_id)
        firmware = None
        if s["connection_id"]:
            firmware = (
                await conn.execute(
                    select(t.vehicle_connections.c.adapter_firmware).where(t.vehicle_connections.c.id == s["connection_id"])
                )
            ).scalar()
        if firmware is None:
            # Fall back to the adapter recorded in the session's (or replay source's) recording.
            tr = t.telemetry_recordings.c
            rec_cond = tr.id == s["source_recording_id"] if s["source_recording_id"] else tr.session_id == session_id
            payload = (
                await conn.execute(select(tr.inline_payload).where(rec_cond).order_by(tr.created_at.desc()).limit(1))
            ).scalar()
            if isinstance(payload, dict):
                firmware = (payload.get("source") or {}).get("adapter_firmware")
    vehicle: dict[str, Any] = {}
    if s["vehicle_id"]:
        # Session access was established through RLS above; vehicle basics are read with the
        # system connection because org members reached through a share cannot see the vehicle row.
        async with svc.db.system() as sconn:
            v = (await sconn.execute(select(t.vehicles).where(t.vehicles.c.id == s["vehicle_id"]))).mappings().first()
        if v:
            vehicle = {
                "make": v["make"],
                "model": v["model"],
                "model_year": v["model_year"],
                "engine": v["engine"],
                "fuel_type": v["fuel_type"],
            }
            if is_owner or (share and share["include_vin"]):
                vehicle["vin_masked"] = mask_vin(decrypt_vin(svc.cipher, v))
    from automind.diagnosis.models import DiagnosisResult
    from automind.reports import ReportMeta, render_report_html, render_report_json

    result = DiagnosisResult.model_validate(latest)
    meta = ReportMeta(
        session_id=str(session_id),
        data_mode=s["data_mode"],
        vehicle=vehicle,
        started_at=s["started_at"],
        protocol_name=s["protocol_name"],
        adapter_firmware=firmware,
        source_recording_id=str(s["source_recording_id"]) if s["source_recording_id"] else None,
        demo_scenario=s["demo_scenario_key"],
    )
    if format == "html":
        html = render_report_html(result, meta, lang)
        return HTMLResponse(
            html,
            headers={
                "Content-Security-Policy": "default-src 'none'; style-src 'unsafe-inline'; img-src data:; "
                "font-src data:; frame-ancestors 'none'"
            },
        )
    return {**render_report_json(result, meta), "data_mode": s["data_mode"]}


@router.post("/{session_id}/shares", status_code=201)
async def create_share(session_id: uuid.UUID, body: ShareIn, user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> dict:
    async with svc.db.user(user.id) as conn:
        s = await get_session(conn, session_id)
        if s["user_id"] != user.id:
            raise forbidden("only the session owner can share it")
        org = (
            await conn.execute(
                select(t.organizations.c.id, t.organizations.c.status).where(t.organizations.c.id == body.organization_id)
            )
        ).first()
        if org is None or org.status != "active":
            raise not_found("organization")
        now = datetime.now(UTC)
        row = (
            (
                await conn.execute(
                    t.report_shares.insert()
                    .values(
                        session_id=session_id,
                        owner_user_id=user.id,
                        shared_with_org_id=body.organization_id,
                        include_vin=body.include_vin,
                        include_live_data=body.include_live_data,
                        consent_version=body.consent_version,
                        granted_at=now,
                        expires_at=now + timedelta(days=body.expires_in_days),
                    )
                    .returning(t.report_shares)
                )
            )
            .mappings()
            .one()
        )
        await conn.execute(
            t.user_consents.insert().values(
                user_id=user.id,
                purpose="share_with_workshop",
                document_version=body.consent_version,
                granted=True,
                ip_address=ctx.ip,
            )
        )
        await audit(
            conn,
            ctx,
            "share.create",
            actor=user.id,
            entity_type="report_share",
            entity_id=row["id"],
            metadata={
                "session_id": str(session_id),
                "organization_id": str(body.organization_id),
                "include_vin": body.include_vin,
                "expires_in_days": body.expires_in_days,
            },
        )
    return share_out(row)


@router.delete("/{session_id}/shares/{share_id}", status_code=204)
async def revoke_share(session_id: uuid.UUID, share_id: uuid.UUID, user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> Response:
    async with svc.db.user(user.id) as conn:
        rs = t.report_shares.c
        row = (
            (
                await conn.execute(
                    select(t.report_shares).where(rs.id == share_id, rs.session_id == session_id, rs.owner_user_id == user.id)
                )
            )
            .mappings()
            .first()
        )
        if row is None:
            raise not_found("share")
        if row["revoked_at"] is None:
            await conn.execute(update(t.report_shares).where(rs.id == share_id).values(revoked_at=datetime.now(UTC)))
            await audit(
                conn,
                ctx,
                "share.revoke",
                actor=user.id,
                entity_type="report_share",
                entity_id=share_id,
                metadata={"session_id": str(session_id)},
            )
    return Response(status_code=204)
