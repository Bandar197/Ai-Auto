"""The signed-in user's profile, consents and PDPL rights (export / deletion)."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Response
from pydantic import BaseModel, Field
from sqlalchemy import select, update

from automind.api.audit import audit
from automind.api.deps import CtxDep, CurrentUser, SvcDep
from automind.api.serializers import decrypt_vin, plain, user_out
from automind.core.errors import not_found
from automind.core.security import revoke_all_user_sessions
from automind.db import tables as t

router = APIRouter(tags=["me"])

USER_COLS = (
    t.users.c.id,
    t.users.c.email,
    t.users.c.full_name,
    t.users.c.phone,
    t.users.c.locale,
    t.users.c.platform_role,
    t.users.c.mfa_enabled,
    t.users.c.created_at,
)


class MePatch(BaseModel):
    full_name: str | None = Field(None, max_length=200)
    phone: str | None = Field(None, max_length=30, pattern=r"^\+?[0-9 ()-]{6,30}$")
    locale: Literal["ar", "en"] | None = None


class ConsentIn(BaseModel):
    purpose: Literal[
        "terms",
        "privacy_policy",
        "diagnostic_processing",
        "ai_processing",
        "training_use",
        "marketing",
        "share_with_workshop",
    ]
    document_version: str = Field(min_length=1, max_length=50)
    granted: bool


@router.get("/me")
async def get_me(user: CurrentUser, svc: SvcDep) -> dict:
    async with svc.db.user(user.id) as conn:
        row = (await conn.execute(select(*USER_COLS).where(t.users.c.id == user.id))).mappings().first()
    if row is None:
        raise not_found("user")
    return user_out(row)


@router.patch("/me")
async def patch_me(body: MePatch, user: CurrentUser, svc: SvcDep) -> dict:
    values = body.model_dump(exclude_unset=True)
    async with svc.db.user(user.id) as conn:
        if values:
            await conn.execute(update(t.users).where(t.users.c.id == user.id).values(**values))
        row = (await conn.execute(select(*USER_COLS).where(t.users.c.id == user.id))).mappings().one()
    return user_out(row)


@router.post("/me/consents", status_code=201)
async def add_consent(body: ConsentIn, user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> dict:
    async with svc.db.user(user.id) as conn:
        row = (
            (
                await conn.execute(
                    t.user_consents.insert()
                    .values(
                        user_id=user.id,
                        purpose=body.purpose,
                        document_version=body.document_version,
                        granted=body.granted,
                        ip_address=ctx.ip,
                    )
                    .returning(t.user_consents)
                )
            )
            .mappings()
            .one()
        )
    return plain(row, exclude=("ip_address",))


async def _rows(conn, stmt) -> list[dict]:
    return [plain(r) for r in (await conn.execute(stmt)).mappings().all()]


@router.get("/me/export")
async def export_me(user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> dict:
    """PDPL right of access: every row that belongs to the user (VINs decrypted)."""
    uid = user.id
    out: dict = {"format": "automind.export.v1", "generated_at": datetime.now(UTC).isoformat()}
    async with svc.db.user(uid) as conn:
        me = (await conn.execute(select(t.users).where(t.users.c.id == uid))).mappings().one()
        out["user"] = plain(me, exclude=("password_hash", "mfa_secret_ciphertext"))
        out["consents"] = await _rows(conn, select(t.user_consents).where(t.user_consents.c.user_id == uid))
        out["data_requests"] = await _rows(conn, select(t.data_requests).where(t.data_requests.c.user_id == uid))
        vehicles = []
        for v in (await conn.execute(select(t.vehicles).where(t.vehicles.c.owner_user_id == uid))).mappings():
            d = plain(v)
            d["vin"] = decrypt_vin(svc.cipher, v)
            vehicles.append(d)
        out["vehicles"] = vehicles
        vids = [v["id"] for v in vehicles]
        out["maintenance_records"] = (
            await _rows(conn, select(t.maintenance_records).where(t.maintenance_records.c.vehicle_id.in_(vids))) if vids else []
        )
        out["devices"] = await _rows(conn, select(t.obd_devices).where(t.obd_devices.c.owner_user_id == uid))
        out["connections"] = await _rows(conn, select(t.vehicle_connections).where(t.vehicle_connections.c.user_id == uid))
        sessions = await _rows(conn, select(t.diagnostic_sessions).where(t.diagnostic_sessions.c.user_id == uid))
        out["sessions"] = sessions
        sids = [s["id"] for s in sessions]
        for key, table in (
            ("dtcs", t.diagnostic_trouble_codes),
            ("telemetry", t.telemetry_readings),
            ("telemetry_aggregates", t.telemetry_aggregates),
            ("findings", t.diagnostic_findings),
            ("ai_diagnoses", t.ai_diagnoses),
            ("evidence", t.diagnosis_evidence),
        ):
            out[key] = await _rows(conn, select(table).where(table.c.session_id.in_(sids))) if sids else []
        out["recordings"] = await _rows(conn, select(t.telemetry_recordings).where(t.telemetry_recordings.c.user_id == uid))
        out["control_operations"] = await _rows(conn, select(t.control_operations).where(t.control_operations.c.user_id == uid))
        out["report_shares"] = await _rows(conn, select(t.report_shares).where(t.report_shares.c.owner_user_id == uid))
        out["subscriptions"] = await _rows(conn, select(t.subscriptions).where(t.subscriptions.c.user_id == uid))
        out["payments"] = await _rows(conn, select(t.payments).where(t.payments.c.user_id == uid))
        out["notifications"] = await _rows(conn, select(t.notifications).where(t.notifications.c.user_id == uid))
        out["parts_orders"] = await _rows(conn, select(t.parts_orders).where(t.parts_orders.c.user_id == uid))
    async with svc.db.system() as conn:
        # System-only tables, still strictly filtered to this user.
        out["auth_sessions"] = await _rows(
            conn,
            select(
                t.auth_sessions.c.id,
                t.auth_sessions.c.created_at,
                t.auth_sessions.c.expires_at,
                t.auth_sessions.c.rotated_at,
                t.auth_sessions.c.revoked_at,
                t.auth_sessions.c.user_agent,
                t.auth_sessions.c.ip_address,
            ).where(t.auth_sessions.c.user_id == uid),
        )
        out["audit_logs"] = await _rows(conn, select(t.audit_logs).where(t.audit_logs.c.actor_user_id == uid))
        await conn.execute(
            t.data_requests.insert().values(user_id=uid, kind="export", status="completed", completed_at=datetime.now(UTC))
        )
        await audit(conn, ctx, "privacy.export", actor=uid, entity_type="user", entity_id=uid)
    return out


@router.delete("/me", status_code=202)
async def delete_me(user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> Response:
    async with svc.db.system() as conn:
        await conn.execute(update(t.users).where(t.users.c.id == user.id).values(status="pending_deletion"))
        await conn.execute(t.data_requests.insert().values(user_id=user.id, kind="delete", status="pending"))
        await revoke_all_user_sessions(conn, user.id)
        await audit(conn, ctx, "privacy.delete_requested", actor=user.id, entity_type="user", entity_id=user.id)
    return Response(status_code=202)
