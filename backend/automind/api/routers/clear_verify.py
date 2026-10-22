"""Clear-and-verify: did the codes cleared through AutoMind Control come back?"""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field
from sqlalchemy import func, select

from automind.api.access import get_vehicle
from automind.api.deps import CurrentUser, SvcDep
from automind.core.errors import not_found
from automind.db import tables as t
from automind.diagnosis.models import InputDTC
from automind.diagnosis.recurrence import ClearRecord, ScanSnapshot, assess_after_clear

router = APIRouter(tags=["clear-verification"])


class ClearVerificationIn(BaseModel):
    record: ClearRecord
    checks: list[ScanSnapshot] = Field(default_factory=list, max_length=200)


@router.post("/diagnosis/clear-verification")
async def verify_stateless(body: ClearVerificationIn, user: CurrentUser) -> dict:  # noqa: ARG001 - auth required
    return assess_after_clear(body.record, body.checks).model_dump(mode="json")


async def _last_value(conn, session_id: uuid.UUID, signal: str) -> float | None:
    tr = t.telemetry_readings.c
    return (
        await conn.execute(
            select(tr.value).where(tr.session_id == session_id, tr.signal == signal).order_by(tr.ts.desc()).limit(1)
        )
    ).scalar_one_or_none()


async def session_snapshot(conn, s: Mapping[str, Any]) -> ScanSnapshot:
    dc = t.diagnostic_trouble_codes.c
    rows = (await conn.execute(select(dc.code, dc.status, dc.ecu_address).where(dc.session_id == s["id"]))).all()
    tr = t.telemetry_readings.c
    max_rpm = (
        await conn.execute(select(func.max(tr.value)).where(tr.session_id == s["id"], tr.signal == "engine_rpm"))
    ).scalar_one_or_none()
    return ScanSnapshot(
        taken_at=s["completed_at"] or s["started_at"],
        session_id=str(s["id"]),
        dtcs=[InputDTC(code=r.code, status=r.status, ecu=r.ecu_address) for r in rows],
        readiness=(s["summary"] or {}).get("readiness"),
        warmups_since_clear=await _last_value(conn, s["id"], "warmups_since_clear"),
        distance_since_clear_km=await _last_value(conn, s["id"], "distance_since_clear"),
        engine_running=(max_rpm > 300) if max_rpm is not None else None,
    )


@router.get("/vehicles/{vehicle_id}/clear-verification")
async def verify_vehicle(vehicle_id: uuid.UUID, user: CurrentUser, svc: SvcDep) -> dict:
    co, sp, ds = t.control_operations.c, t.service_procedures.c, t.diagnostic_sessions.c
    async with svc.db.user(user.id) as conn:
        await get_vehicle(conn, vehicle_id)  # 404 when not visible
        op = (
            (
                await conn.execute(
                    select(t.control_operations)
                    .join(t.service_procedures, sp.id == co.procedure_id)
                    .where(co.vehicle_id == vehicle_id, co.status == "succeeded", sp.key == "clear_dtcs",
                           co.session_id.is_not(None))
                    .order_by(co.finished_at.desc())
                    .limit(1)
                )
            )
            .mappings()
            .first()
        )
        if op is None:
            raise not_found("clear operation")
        before_s = (await conn.execute(select(t.diagnostic_sessions).where(ds.id == op["session_id"]))).mappings().first()
        if before_s is None:
            raise not_found("session")
        before = await session_snapshot(conn, before_s)
        cleared_at = op["finished_at"] or op["created_at"]
        later = (
            (
                await conn.execute(
                    select(t.diagnostic_sessions)
                    .where(ds.vehicle_id == vehicle_id, ds.started_at > cleared_at, ds.id != op["session_id"],
                           ds.data_mode == op["data_mode"])
                    .order_by(ds.started_at)
                    .limit(50)
                )
            )
            .mappings()
            .all()
        )
        checks = [await session_snapshot(conn, s) for s in later]
    record = ClearRecord(cleared_at=cleared_at, before=before, operation_id=str(op["id"]), data_mode=op["data_mode"])
    out = assess_after_clear(record, checks).model_dump(mode="json")
    out["operation_id"] = str(op["id"])
    return out
