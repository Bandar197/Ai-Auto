"""Lookups that run on a *user* connection, so RLS decides visibility.

Foreign keys are checked by PostgreSQL as the table owner (bypassing RLS),
so every id a client sends (vehicle, device, connection, recording) is first
looked up here: invisible → 404, never "silently linked to someone else's row".
"""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncConnection

from automind.core.errors import forbidden, not_found
from automind.db import tables as t


async def get_vehicle(conn: AsyncConnection, vehicle_id: uuid.UUID) -> Mapping[str, Any]:
    row = (
        (await conn.execute(select(t.vehicles).where(t.vehicles.c.id == vehicle_id, t.vehicles.c.deleted_at.is_(None))))
        .mappings()
        .first()
    )
    if row is None:
        raise not_found("vehicle")
    return row


async def require_vehicle_write(conn: AsyncConnection, vehicle_id: uuid.UUID) -> Mapping[str, Any]:
    row = await get_vehicle(conn, vehicle_id)
    if not (await conn.execute(select(func.automind.can_write_vehicle(vehicle_id)))).scalar():
        raise forbidden("you cannot modify this vehicle")
    return row


async def get_session(
    conn: AsyncConnection, session_id: uuid.UUID, *, write: bool = False, for_update: bool = False
) -> Mapping[str, Any]:
    """Visible → row; invisible → 404; visible but read-only (e.g. via a share) and write → 403."""
    stmt = select(t.diagnostic_sessions).where(t.diagnostic_sessions.c.id == session_id)
    row = (await conn.execute(stmt)).mappings().first()
    if row is None:
        raise not_found("session")
    if (write or for_update) and not (await conn.execute(select(func.automind.can_write_session(session_id)))).scalar():
        raise forbidden("you cannot modify this session")
    if for_update:
        # FOR UPDATE is subject to the UPDATE policy as well, hence after the write check.
        row = (await conn.execute(stmt.with_for_update())).mappings().one()
    return row


async def ensure_device(conn: AsyncConnection, device_id: uuid.UUID | None) -> Mapping[str, Any] | None:
    if device_id is None:
        return None
    row = (await conn.execute(select(t.obd_devices).where(t.obd_devices.c.id == device_id))).mappings().first()
    if row is None:
        raise not_found("device")
    return row


async def ensure_connection(conn: AsyncConnection, connection_id: uuid.UUID | None) -> None:
    if connection_id is None:
        return
    row = (await conn.execute(select(t.vehicle_connections.c.id).where(t.vehicle_connections.c.id == connection_id))).first()
    if row is None:
        raise not_found("connection")


async def get_recording(conn: AsyncConnection, recording_id: uuid.UUID) -> Mapping[str, Any]:
    row = (
        (await conn.execute(select(t.telemetry_recordings).where(t.telemetry_recordings.c.id == recording_id))).mappings().first()
    )
    if row is None:
        raise not_found("recording")
    return row
