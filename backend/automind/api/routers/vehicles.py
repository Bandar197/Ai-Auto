"""Vehicles (VIN encrypted + blind index) and maintenance records."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Literal

from fastapi import APIRouter, Response
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select, update

from automind.api.access import get_vehicle, require_vehicle_write
from automind.api.audit import audit
from automind.api.deps import CtxDep, CurrentUser, Page, SvcDep, page
from automind.api.plans import enforce_limit
from automind.api.serializers import plain, vehicle_out, vin_aad
from automind.core.crypto import normalize_vin, vin_blind_index
from automind.core.errors import conflict, forbidden, validation
from automind.db import tables as t

router = APIRouter(tags=["vehicles"])

FuelType = Literal["gasoline", "diesel", "hybrid", "electric", "flex", "lpg", "cng", "other"]
Transmission = Literal["automatic", "manual", "cvt", "dct", "other"]


class VehicleIn(BaseModel):
    vin: str | None = Field(None, max_length=32)
    make: str | None = Field(None, max_length=60)
    model: str | None = Field(None, max_length=60)
    model_year: int | None = Field(None, ge=1980, le=2100)
    engine: str | None = Field(None, max_length=60)
    fuel_type: FuelType | None = None
    transmission: Transmission | None = None
    nickname: str | None = Field(None, max_length=60)
    plate: str | None = Field(None, max_length=20)
    odometer_km: int | None = Field(None, ge=0, le=5_000_000)


class MaintenanceIn(BaseModel):
    service_date: date
    odometer_km: int | None = Field(None, ge=0, le=5_000_000)
    category: Literal[
        "oil_change",
        "filters",
        "brakes",
        "tires",
        "battery",
        "cooling",
        "ac",
        "transmission",
        "engine_repair",
        "electrical",
        "inspection",
        "other",
    ]
    description: str = Field(min_length=1, max_length=2000)
    cost_amount: float | None = Field(None, ge=0, le=10_000_000)
    currency: str = Field("SAR", pattern=r"^[A-Z]{3}$")
    parts: list[dict] = Field(default_factory=list, max_length=100)
    session_id: uuid.UUID | None = None


def _vin_values(svc, vehicle_id: uuid.UUID, raw_vin: str | None) -> dict:
    if raw_vin is None:
        return {}
    if raw_vin == "":
        return {"vin_ciphertext": None, "vin_blind_index": None, "vin_wmi": None, "vin_model_year_code": None}
    try:
        vin = normalize_vin(raw_vin)
    except ValueError as exc:
        raise validation(str(exc), {"field": "vin"}) from exc
    return {
        "vin_ciphertext": svc.cipher.encrypt(vin, aad=vin_aad(vehicle_id)),
        "vin_blind_index": vin_blind_index(svc.blind_key, vin),
        "vin_wmi": vin[:3],
        "vin_model_year_code": vin[9],
    }


def _mine(user_id: uuid.UUID):
    v = t.vehicles.c
    return or_(
        v.owner_user_id == user_id,
        (v.organization_id.isnot(None)) & func.automind.is_org_member(v.organization_id),
    )


@router.get("/vehicles")
async def list_vehicles(user: CurrentUser, svc: SvcDep, p: Page) -> dict:
    cond = (t.vehicles.c.deleted_at.is_(None)) & _mine(user.id)
    async with svc.db.user(user.id) as conn:
        total = (await conn.execute(select(func.count()).select_from(t.vehicles).where(cond))).scalar_one()
        rows = (
            (
                await conn.execute(
                    select(t.vehicles).where(cond).order_by(t.vehicles.c.created_at.desc()).limit(p.limit).offset(p.offset)
                )
            )
            .mappings()
            .all()
        )
    return page([vehicle_out(r, svc.cipher) for r in rows], total, p)


@router.post("/vehicles", status_code=201)
async def create_vehicle(body: VehicleIn, user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> dict:
    vid = uuid.uuid4()
    values = body.model_dump(exclude={"vin", "plate"}, exclude_none=True)
    values.update(_vin_values(svc, vid, body.vin or None))
    if body.plate:
        values["plate_ciphertext"] = svc.cipher.encrypt(body.plate.strip().upper(), aad=b"plate:" + str(vid).encode())
    async with svc.db.user(user.id) as conn:
        count = (
            await conn.execute(
                select(func.count())
                .select_from(t.vehicles)
                .where(t.vehicles.c.owner_user_id == user.id, t.vehicles.c.deleted_at.is_(None))
            )
        ).scalar_one()
        await enforce_limit(conn, user.id, "vehicles", count)
        if values.get("vin_blind_index"):
            dup = (
                await conn.execute(
                    select(t.vehicles.c.id).where(
                        t.vehicles.c.owner_user_id == user.id,
                        t.vehicles.c.deleted_at.is_(None),
                        t.vehicles.c.vin_blind_index == values["vin_blind_index"],
                    )
                )
            ).first()
            if dup:
                raise conflict("a vehicle with this VIN already exists", {"vehicle_id": str(dup.id)})
        row = (
            (await conn.execute(t.vehicles.insert().values(id=vid, owner_user_id=user.id, **values).returning(t.vehicles)))
            .mappings()
            .one()
        )
        await audit(
            conn,
            ctx,
            "vehicle.create",
            actor=user.id,
            entity_type="vehicle",
            entity_id=vid,
            metadata={"has_vin": bool(values.get("vin_ciphertext"))},
        )
    return vehicle_out(row, svc.cipher)


@router.get("/vehicles/{vehicle_id}")
async def get_vehicle_ep(vehicle_id: uuid.UUID, user: CurrentUser, svc: SvcDep, ctx: CtxDep, reveal_vin: bool = False) -> dict:
    async with svc.db.user(user.id) as conn:
        row = await get_vehicle(conn, vehicle_id)
        if reveal_vin:
            if row["owner_user_id"] != user.id:
                await audit(
                    conn,
                    ctx,
                    "vehicle.reveal_vin",
                    actor=user.id,
                    entity_type="vehicle",
                    entity_id=vehicle_id,
                    outcome="denied",
                )
            else:
                await audit(
                    conn,
                    ctx,
                    "vehicle.reveal_vin",
                    actor=user.id,
                    entity_type="vehicle",
                    entity_id=vehicle_id,
                )
    if reveal_vin and row["owner_user_id"] != user.id:
        raise forbidden("only the owner can reveal the VIN")
    return vehicle_out(row, svc.cipher, reveal=reveal_vin)


@router.patch("/vehicles/{vehicle_id}")
async def patch_vehicle(vehicle_id: uuid.UUID, body: VehicleIn, user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> dict:
    fields = body.model_dump(exclude_unset=True)
    values = {k: v for k, v in fields.items() if k not in ("vin", "plate")}
    if "vin" in fields:
        values.update(_vin_values(svc, vehicle_id, fields["vin"] or ""))
    if "plate" in fields:
        values["plate_ciphertext"] = (
            svc.cipher.encrypt(fields["plate"].strip().upper(), aad=b"plate:" + str(vehicle_id).encode())
            if fields["plate"]
            else None
        )
    async with svc.db.user(user.id) as conn:
        await require_vehicle_write(conn, vehicle_id)
        if values.get("vin_blind_index"):
            dup = (
                await conn.execute(
                    select(t.vehicles.c.id).where(
                        t.vehicles.c.owner_user_id == user.id,
                        t.vehicles.c.deleted_at.is_(None),
                        t.vehicles.c.id != vehicle_id,
                        t.vehicles.c.vin_blind_index == values["vin_blind_index"],
                    )
                )
            ).first()
            if dup:
                raise conflict("a vehicle with this VIN already exists", {"vehicle_id": str(dup.id)})
        if values:
            await conn.execute(update(t.vehicles).where(t.vehicles.c.id == vehicle_id).values(**values))
            await audit(
                conn,
                ctx,
                "vehicle.update",
                actor=user.id,
                entity_type="vehicle",
                entity_id=vehicle_id,
                metadata={"fields": sorted(fields)},
            )
        row = await get_vehicle(conn, vehicle_id)
    return vehicle_out(row, svc.cipher)


@router.delete("/vehicles/{vehicle_id}", status_code=204)
async def delete_vehicle(vehicle_id: uuid.UUID, user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> Response:
    async with svc.db.user(user.id) as conn:
        await require_vehicle_write(conn, vehicle_id)
        await conn.execute(update(t.vehicles).where(t.vehicles.c.id == vehicle_id).values(deleted_at=datetime.now(UTC)))
        await audit(conn, ctx, "vehicle.delete", actor=user.id, entity_type="vehicle", entity_id=vehicle_id)
    return Response(status_code=204)


@router.get("/vehicles/{vehicle_id}/maintenance")
async def list_maintenance(vehicle_id: uuid.UUID, user: CurrentUser, svc: SvcDep, p: Page) -> dict:
    cond = t.maintenance_records.c.vehicle_id == vehicle_id
    async with svc.db.user(user.id) as conn:
        await get_vehicle(conn, vehicle_id)
        total = (await conn.execute(select(func.count()).select_from(t.maintenance_records).where(cond))).scalar_one()
        rows = (
            (
                await conn.execute(
                    select(t.maintenance_records)
                    .where(cond)
                    .order_by(t.maintenance_records.c.service_date.desc())
                    .limit(p.limit)
                    .offset(p.offset)
                )
            )
            .mappings()
            .all()
        )
    return page([plain(r) for r in rows], total, p)


@router.post("/vehicles/{vehicle_id}/maintenance", status_code=201)
async def add_maintenance(vehicle_id: uuid.UUID, body: MaintenanceIn, user: CurrentUser, svc: SvcDep) -> dict:
    async with svc.db.user(user.id) as conn:
        await require_vehicle_write(conn, vehicle_id)
        if body.session_id is not None:
            from automind.api.access import get_session

            await get_session(conn, body.session_id)
        row = (
            (
                await conn.execute(
                    t.maintenance_records.insert()
                    .values(vehicle_id=vehicle_id, created_by=user.id, source="owner", **body.model_dump())
                    .returning(t.maintenance_records)
                )
            )
            .mappings()
            .one()
        )
    return plain(row)
