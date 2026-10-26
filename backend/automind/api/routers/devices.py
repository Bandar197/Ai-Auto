"""OBD adapters and connection-attempt logging."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Response
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import delete, func, select, update

from automind.api.access import ensure_device, get_vehicle
from automind.api.deps import CurrentUser, Page, SvcDep, page
from automind.api.serializers import device_out
from automind.core.errors import not_found, validation
from automind.db import tables as t

router = APIRouter(tags=["devices"])

Transport = Literal["wifi_tcp", "ble", "usb_serial"]


class DeviceIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    transport: Transport
    adapter_type: Literal["elm327", "stn11xx", "stn21xx", "j2534", "other"] = "elm327"
    host: str | None = Field(None, max_length=255)
    port: int | None = Field(None, ge=1, le=65535)
    ble_device_id: str | None = Field(None, max_length=100)
    ble_service_uuid: str | None = Field(None, max_length=64)
    ble_notify_uuid: str | None = Field(None, max_length=64)
    ble_write_uuid: str | None = Field(None, max_length=64)
    firmware_version: str | None = Field(None, max_length=100)

    @model_validator(mode="after")
    def _tcp(self) -> DeviceIn:
        if self.transport == "wifi_tcp" and (not self.host or not self.port):
            raise ValueError("wifi_tcp devices need host and port")
        return self


class DevicePatch(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=80)
    host: str | None = Field(None, max_length=255)
    port: int | None = Field(None, ge=1, le=65535)
    ble_device_id: str | None = Field(None, max_length=100)
    ble_service_uuid: str | None = Field(None, max_length=64)
    ble_notify_uuid: str | None = Field(None, max_length=64)
    ble_write_uuid: str | None = Field(None, max_length=64)
    firmware_version: str | None = Field(None, max_length=100)


class ConnectionIn(BaseModel):
    device_id: uuid.UUID | None = None
    vehicle_id: uuid.UUID | None = None
    data_mode: Literal["live", "demo", "replay"]
    transport: Literal["wifi_tcp", "ble", "usb_serial", "bt_classic", "in_process"] | None = None
    adapter_status: Literal["connected", "unreachable", "timeout", "rejected", "error"]
    ecu_status: Literal["connected", "no_response", "bus_error", "not_attempted", "error"]
    protocol_code: str | None = Field(None, max_length=10)
    protocol_name: str | None = Field(None, max_length=100)
    adapter_firmware: str | None = Field(None, max_length=100)
    attempts: int = Field(1, ge=1, le=1000)
    latency_ms: int | None = Field(None, ge=0, le=3_600_000)
    error_code: str | None = Field(None, max_length=100)
    error_message: str | None = Field(None, max_length=1000)
    app_platform: str | None = Field(None, max_length=30)
    app_version: str | None = Field(None, max_length=30)
    started_at: datetime
    ended_at: datetime | None = None

    @model_validator(mode="after")
    def _times(self) -> ConnectionIn:
        if self.started_at.tzinfo is None:
            self.started_at = self.started_at.replace(tzinfo=UTC)
        if self.ended_at is not None:
            if self.ended_at.tzinfo is None:
                self.ended_at = self.ended_at.replace(tzinfo=UTC)
            if self.ended_at < self.started_at:
                raise ValueError("ended_at must be after started_at")
        return self


def _mine(user_id: uuid.UUID):
    d = t.obd_devices.c
    return (d.owner_user_id == user_id) | (d.organization_id.isnot(None) & func.automind.is_org_member(d.organization_id))


@router.get("/devices")
async def list_devices(user: CurrentUser, svc: SvcDep, p: Page) -> dict:
    cond = _mine(user.id)
    async with svc.db.user(user.id) as conn:
        total = (await conn.execute(select(func.count()).select_from(t.obd_devices).where(cond))).scalar_one()
        rows = (
            (
                await conn.execute(
                    select(t.obd_devices).where(cond).order_by(t.obd_devices.c.created_at.desc()).limit(p.limit).offset(p.offset)
                )
            )
            .mappings()
            .all()
        )
    return page([device_out(r) for r in rows], total, p)


@router.post("/devices", status_code=201)
async def create_device(body: DeviceIn, user: CurrentUser, svc: SvcDep) -> dict:
    async with svc.db.user(user.id) as conn:
        row = (
            (
                await conn.execute(
                    t.obd_devices.insert().values(owner_user_id=user.id, **body.model_dump()).returning(t.obd_devices)
                )
            )
            .mappings()
            .one()
        )
    return device_out(row)


@router.patch("/devices/{device_id}")
async def patch_device(device_id: uuid.UUID, body: DevicePatch, user: CurrentUser, svc: SvcDep) -> dict:
    values = body.model_dump(exclude_unset=True)
    async with svc.db.user(user.id) as conn:
        await ensure_device(conn, device_id)
        if values:
            res = await conn.execute(
                update(t.obd_devices).where(t.obd_devices.c.id == device_id).values(**values).returning(t.obd_devices)
            )
        else:
            res = await conn.execute(select(t.obd_devices).where(t.obd_devices.c.id == device_id))
        row = res.mappings().first()
    if row is None:
        raise not_found("device")
    return device_out(row)


@router.delete("/devices/{device_id}", status_code=204)
async def delete_device(device_id: uuid.UUID, user: CurrentUser, svc: SvcDep) -> Response:
    async with svc.db.user(user.id) as conn:
        await ensure_device(conn, device_id)
        res = await conn.execute(delete(t.obd_devices).where(t.obd_devices.c.id == device_id).returning(t.obd_devices.c.id))
        if res.first() is None:
            raise not_found("device")
    return Response(status_code=204)


@router.post("/connections", status_code=201)
async def log_connection(body: ConnectionIn, user: CurrentUser, svc: SvcDep) -> dict:
    now = datetime.now(UTC)
    if body.started_at > now + timedelta(days=1) or body.started_at < now - timedelta(days=365):
        raise validation("started_at is outside the accepted window", {"field": "started_at"})
    async with svc.db.user(user.id) as conn:
        if body.vehicle_id:
            await get_vehicle(conn, body.vehicle_id)
        await ensure_device(conn, body.device_id)
        cid = (
            await conn.execute(
                t.vehicle_connections.insert().values(user_id=user.id, **body.model_dump()).returning(t.vehicle_connections.c.id)
            )
        ).scalar_one()
        if body.device_id and body.adapter_status == "connected":
            await conn.execute(
                update(t.obd_devices)
                .where(t.obd_devices.c.id == body.device_id)
                .values(last_seen_at=body.ended_at or body.started_at)
            )
    return {"id": str(cid)}
