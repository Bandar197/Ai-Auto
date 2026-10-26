"""AutoMind Control: the server authorises, the device executes and reports back."""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any, Literal

from fastapi import APIRouter, Response
from pydantic import BaseModel, Field
from sqlalchemy import select, update

from automind.api.access import ensure_device, get_session, get_vehicle
from automind.api.audit import audit
from automind.api.deps import CtxDep, CurrentUser, SvcDep
from automind.control.policy import (
    AllowlistEntry,
    Conditions,
    ControlRequest,
    DeviceCtx,
    Procedure,
    VehicleCtx,
    evaluate,
)
from automind.core.errors import APIError, conflict, not_found, validation
from automind.db import tables as t

router = APIRouter(prefix="/control", tags=["control"])


class ConditionsIn(BaseModel):
    engine_running: bool
    vehicle_speed_kmh: float = Field(ge=0, le=500)
    active_faults: int | None = Field(None, ge=0, le=500)
    repair_confirmed: bool | None = None


class OperationIn(BaseModel):
    procedure_key: str = Field(min_length=1, max_length=60, pattern=r"^[a-z0-9_]+$")
    vehicle_id: uuid.UUID | None = None
    session_id: uuid.UUID | None = None
    device_id: uuid.UUID | None = None
    data_mode: Literal["live", "demo", "replay"]
    consent_text: str = Field(min_length=1, max_length=2000)
    confirmed: bool
    conditions: ConditionsIn
    ecu_address: str | None = Field(None, max_length=8)


class OperationResultIn(BaseModel):
    status: Literal["succeeded", "failed"]
    request_frames: list[str] = Field(default_factory=list, max_length=500)
    response_frames: list[str] = Field(default_factory=list, max_length=500)
    result: dict[str, Any] | None = None


def _procedure(r: Mapping[str, Any]) -> Procedure:
    return Procedure(
        key=r["key"],
        risk_level=r["risk_level"],
        safety_category=r["safety_category"],
        enabled_by_default=r["enabled_by_default"],
        is_prohibited=r["is_prohibited"],
        required_engine_state=r["required_engine_state"],
        obd_service=r["obd_service"],
        level=r["level"],
    )


async def _allowlist(conn, procedure_id: uuid.UUID) -> list[AllowlistEntry]:
    rows = (
        (
            await conn.execute(
                select(t.procedure_allowlist).where(
                    t.procedure_allowlist.c.procedure_id == procedure_id,
                    t.procedure_allowlist.c.active.is_(True),
                )
            )
        )
        .mappings()
        .all()
    )
    return [
        AllowlistEntry(
            active=r["active"],
            make=r["make"],
            model=r["model"],
            year_from=r["year_from"],
            year_to=r["year_to"],
            ecu_address=r["ecu_address"],
            adapter_type=r["adapter_type"],
            requires_certified_device=r["requires_certified_device"],
        )
        for r in rows
    ]


def _vehicle_ctx(v) -> VehicleCtx | None:
    return VehicleCtx(make=v["make"], model=v["model"], model_year=v["model_year"]) if v else None


def _device_ctx(d) -> DeviceCtx | None:
    return DeviceCtx(adapter_type=d["adapter_type"], is_certified=d["is_certified"]) if d else None


@router.get("/procedures")
async def list_procedures(
    user: CurrentUser, svc: SvcDep, vehicle_id: uuid.UUID | None = None, device_id: uuid.UUID | None = None
) -> list[dict]:
    async with svc.db.user(user.id) as conn:
        vehicle = await get_vehicle(conn, vehicle_id) if vehicle_id else None
        device = await ensure_device(conn, device_id)
        procs = (
            (await conn.execute(select(t.service_procedures).order_by(t.service_procedures.c.level, t.service_procedures.c.key)))
            .mappings()
            .all()
        )
        out = []
        for r in procs:
            proc = _procedure(r)
            # Static availability: assume the runtime preconditions will be met.
            engine = proc.required_engine_state == "running"
            req = ControlRequest(
                data_mode="live",
                confirmed=True,
                consent_text="availability-check",
                conditions=Conditions(engine_running=engine and proc.key not in ("clear_dtcs", "clear_srs_dtcs"),
                                      vehicle_speed_kmh=0, active_faults=0, repair_confirmed=True),
            )
            allow = await _allowlist(conn, r["id"]) if not (proc.enabled_by_default or proc.is_prohibited) else []
            d = evaluate(proc, req, vehicle=_vehicle_ctx(vehicle), device=_device_ctx(device), allowlist=allow)
            out.append(
                {
                    "key": r["key"],
                    "level": r["level"],
                    "name_en": r["name_en"],
                    "name_ar": r["name_ar"],
                    "description_en": r["description_en"],
                    "description_ar": r["description_ar"],
                    "risk_level": r["risk_level"],
                    "safety_category": r["safety_category"],
                    "required_engine_state": r["required_engine_state"],
                    "available": d.approved,
                    "reason_en": d.reason_en,
                    "reason_ar": d.reason_ar,
                    "preconditions": r["preconditions"],
                }
            )
    return out


@router.post("/operations", status_code=201)
async def request_operation(body: OperationIn, user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> dict:
    async with svc.db.user(user.id) as conn:
        proc_row = (
            (await conn.execute(select(t.service_procedures).where(t.service_procedures.c.key == body.procedure_key)))
            .mappings()
            .first()
        )
        if proc_row is None:
            raise not_found("procedure")
        vehicle = await get_vehicle(conn, body.vehicle_id) if body.vehicle_id else None
        device = await ensure_device(conn, body.device_id)
        if proc_row["key"] in ("clear_dtcs", "clear_srs_dtcs") and body.data_mode == "live" and not body.session_id:
            # The codes + freeze frame must be saved first: clearing erases them and they are
            # needed to verify afterwards whether the fault comes back.
            raise validation(
                "save a scan (session with its trouble codes) before clearing", {"field": "session_id"}
            )
        if body.session_id:
            s = await get_session(conn, body.session_id, write=True)
            if s["data_mode"] != body.data_mode:
                raise validation("data_mode does not match the session", {"field": "data_mode"})
            if vehicle is None and s["vehicle_id"]:
                vehicle = await get_vehicle(conn, s["vehicle_id"])
        proc = _procedure(proc_row)
        allow = await _allowlist(conn, proc_row["id"])
        req = ControlRequest(
            data_mode=body.data_mode,
            confirmed=body.confirmed,
            consent_text=body.consent_text,
            conditions=Conditions(
                engine_running=body.conditions.engine_running,
                vehicle_speed_kmh=body.conditions.vehicle_speed_kmh,
                active_faults=body.conditions.active_faults,
                repair_confirmed=body.conditions.repair_confirmed,
            ),
            ecu_address=body.ecu_address,
        )
        d = evaluate(proc, req, vehicle=_vehicle_ctx(vehicle), device=_device_ctx(device), allowlist=allow)
        now = datetime.now(UTC)
        decision = {
            "approved": d.approved,
            "simulated": d.simulated,
            "code": d.code,
            "commands": list(d.commands),
            "conditions": body.conditions.model_dump(),
        }
        op_id = (
            await conn.execute(
                t.control_operations.insert()
                .values(
                    user_id=user.id,
                    vehicle_id=vehicle["id"] if vehicle else None,
                    session_id=body.session_id,
                    device_id=body.device_id,
                    procedure_id=proc_row["id"],
                    data_mode=body.data_mode,
                    consent_text=body.consent_text,
                    consented_at=now,
                    status="requested" if d.approved else "rejected_policy",
                    rejection_reason=None if d.approved else f"{d.code}: {d.reason_en}",
                    result={"decision": decision},
                )
                .returning(t.control_operations.c.id)
            )
        ).scalar_one()
        await audit(
            conn,
            ctx,
            "control.request",
            actor=user.id,
            entity_type="control_operation",
            entity_id=op_id,
            outcome="success" if d.approved else "denied",
            metadata={"procedure": body.procedure_key, "data_mode": body.data_mode, **decision},
        )
    out: dict[str, Any] = {
        "id": str(op_id),
        "status": "approved" if d.approved else "rejected_policy",
        "procedure_key": body.procedure_key,
        "data_mode": body.data_mode,
        "simulated": d.simulated,
    }
    if d.approved:
        if d.simulated:
            # Nothing may be sent to a real vehicle: the commands are for the simulator only.
            out.update(
                commands=[],
                simulated_commands=list(d.commands),
                real_vehicle_command=False,
                notice_en=d.notice_en,
                notice_ar=d.notice_ar,
            )
        else:
            out.update(commands=list(d.commands), real_vehicle_command=True)
    else:
        out.update(reason=d.code, reason_en=d.reason_en, reason_ar=d.reason_ar)
    return out


@router.patch("/operations/{operation_id}", status_code=204)
async def report_operation(
    operation_id: uuid.UUID, body: OperationResultIn, user: CurrentUser, svc: SvcDep, ctx: CtxDep
) -> Response:
    co = t.control_operations.c
    async with svc.db.user(user.id) as conn:
        row = (
            (
                await conn.execute(
                    select(t.control_operations).where(co.id == operation_id, co.user_id == user.id).with_for_update()
                )
            )
            .mappings()
            .first()
        )
        if row is None:
            raise not_found("operation")
        if row["status"] == "rejected_policy":
            raise APIError(403, "policy_rejected", "this operation was rejected by policy and cannot run")
        if row["status"] in ("succeeded", "failed"):
            raise conflict("operation result already reported", {"status": row["status"]})
        result = dict(row["result"] or {})
        result["device_result"] = body.result or {}
        await conn.execute(
            update(t.control_operations)
            .where(co.id == operation_id)
            .values(
                status=body.status,
                request_frames=body.request_frames,
                response_frames=body.response_frames,
                result=result,
                finished_at=datetime.now(UTC),
            )
        )
        await audit(
            conn,
            ctx,
            "control.result",
            actor=user.id,
            entity_type="control_operation",
            entity_id=operation_id,
            outcome="success" if body.status == "succeeded" else "failure",
            metadata={
                "status": body.status,
                "data_mode": row["data_mode"],
                "request_frames": body.request_frames[:20],
            },
        )
    return Response(status_code=204)
