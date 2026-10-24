"""Controller / profile diagnostic catalogue.

Two layers of trust:

* ``diag_controller_catalog`` — reference data: UNVERIFIED static identifiers
  (module-group names per manufacturer, seeded from
  ``shared/diag/controller_identifiers.json``). Not CAN addresses, not proof an
  ECU is readable. Readable by any signed-in user.
* ``diag_ecu_profiles`` — candidate ECU access profiles (protocol + CAN headers).
  Unverified by default; never field-trusted until a platform admin APPROVES it
  with evidence. Submit/approve is platform-admin only and, by
  separation-of-duties, the submitter may not approve their own profile.

DTC explanations are NOT duplicated here — use ``/kb/dtc/{code}`` and
``/kb/explain``.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from functools import lru_cache
from typing import Any, Literal

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field
from sqlalchemy import and_, func, or_, select

from automind.api.audit import audit
from automind.api.deps import AdminUser, CtxDep, CurrentUser, Page, SvcDep, page
from automind.core.errors import forbidden, not_found, validation
from automind.db import tables as t

router = APIRouter(prefix="/diag", tags=["diag"])

APPROVED_STATUSES = ("verified_vehicle_trace", "licensed_oem", "standard_specification")
REVIEW_STATUSES = ("verified_vehicle_trace", "licensed_oem", "standard_specification", "demo_only", "rejected")


@lru_cache(maxsize=1)
def _protocol_meta() -> dict[str, int | None]:
    """Known protocol names → their CAN id-bit width (from shared/obd/protocols.json)."""
    from automind.obd.elm327 import protocol_table

    out: dict[str, int | None] = {}
    for p in protocol_table().values():
        name = p.get("name")
        if name and name != "Automatic":
            out[name] = p.get("id_bits")
    return out


def _like(q: str) -> str:
    return "%" + q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


def _hex(value: str, field: str) -> str:
    cleaned = value.strip()
    if cleaned[:2].lower() == "0x":
        cleaned = cleaned[2:]
    if not cleaned or any(c not in "0123456789abcdefABCDEF" for c in cleaned):
        raise validation(f"{field} must be hexadecimal", {"field": field})
    return cleaned.upper()


# Expected hex nibble count per CAN id width (11-bit → 3 nibbles, 29-bit → 8 nibbles).
_HEADER_NIBBLES = {11: 3, 29: 8}


class ProfileIn(BaseModel):
    make: str = Field(min_length=1, max_length=40)
    model: str | None = Field(None, max_length=60)
    market: str | None = Field(None, max_length=40)
    variant: str | None = Field(None, max_length=60)
    year_from: int | None = Field(None, ge=1980, le=2100)
    year_to: int | None = Field(None, ge=1980, le=2100)
    controller_id: str | None = Field(None, max_length=120)
    protocol: str | None = Field(None, max_length=60)
    tx_header: str | None = Field(None, max_length=16)
    rx_header: str | None = Field(None, max_length=16)
    read_request: str | None = Field(None, max_length=32)
    id_bits: Literal[11, 29] | None = None
    category: str | None = Field(None, max_length=40)
    model_year_range: str | None = Field(None, max_length=40)
    source_type: str | None = Field(None, max_length=40)
    source_reference: str | None = Field(None, max_length=200)
    notes: str | None = Field(None, max_length=1000)


class ApproveIn(BaseModel):
    # An approval (or a documented rejection) always carries evidence.
    verification_status: Literal[
        "verified_vehicle_trace", "licensed_oem", "standard_specification", "demo_only", "rejected"
    ]
    source_type: str = Field(min_length=1, max_length=40)
    source_reference: str = Field(min_length=1, max_length=200)


def _controller_out(r: Any) -> dict:
    return {
        "id": r["id"],
        "make": r["make"],
        "category": r["category"],
        "label": r["label"],
        "verification_status": r["verification_status"],
        "source_type": r["source_type"],
        "source_reference": r["source_reference"],
        "created_at": r["created_at"],
    }


def _profile_out(r: Any) -> dict:
    def s(v: Any) -> str | None:
        return str(v) if v is not None else None

    return {
        "id": str(r["id"]),
        "make": r["make"],
        "model": r["model"],
        "market": r["market"],
        "variant": r["variant"],
        "year_from": r["year_from"],
        "year_to": r["year_to"],
        "controller_id": r["controller_id"],
        "protocol": r["protocol"],
        "tx_header": r["tx_header"],
        "rx_header": r["rx_header"],
        "read_request": r["read_request"],
        "id_bits": r["id_bits"],
        "category": r["category"],
        "verification_status": r["verification_status"],
        "source_type": r["source_type"],
        "source_reference": r["source_reference"],
        "model_year_range": r["model_year_range"],
        "notes": r["notes"],
        "submitted_by": s(r["submitted_by"]),
        "reviewed_by": s(r["reviewed_by"]),
        "reviewed_at": r["reviewed_at"],
        "version": r["version"],
        "created_at": r["created_at"],
        "updated_at": r["updated_at"],
    }


# ----------------------------------------------------------------------------- catalogue
@router.get("/catalog/manufacturers")
async def manufacturers(user: CurrentUser, svc: SvcDep) -> list[dict]:
    """Makes present in the controller catalogue with their identifier counts."""
    c = t.diag_controller_catalog.c
    async with svc.db.user(user.id) as conn:
        rows = (
            await conn.execute(select(c.make, func.count().label("count")).group_by(c.make).order_by(c.make))
        ).all()
    return [{"make": make, "count": int(n)} for make, n in rows]


@router.get("/catalog/controllers")
async def controllers(
    user: CurrentUser,
    svc: SvcDep,
    p: Page,
    make: str | None = Query(None, max_length=40),
    q: str = Query("", max_length=100),
) -> dict:
    """Paginated catalogue entries (all ``verification_status = 'unverified'``)."""
    c = t.diag_controller_catalog.c
    conds = []
    if make:
        conds.append(c.make == make)
    if q.strip():
        pat = _like(q.strip())
        conds.append(or_(c.id.ilike(pat, escape="\\"), c.label.ilike(pat, escape="\\"), c.category.ilike(pat, escape="\\")))
    async with svc.db.user(user.id) as conn:
        total = (await conn.execute(select(func.count()).select_from(t.diag_controller_catalog).where(*conds))).scalar_one()
        rows = (
            (
                await conn.execute(
                    select(t.diag_controller_catalog).where(*conds).order_by(c.id).limit(p.limit).offset(p.offset)
                )
            )
            .mappings()
            .all()
        )
    return page([_controller_out(r) for r in rows], total, p)


@router.get("/catalog/profiles")
async def profiles(
    user: CurrentUser,
    svc: SvcDep,
    make: str | None = Query(None, max_length=40),
    model: str | None = Query(None, max_length=60),
    year: int | None = Query(None, ge=1980, le=2100),
) -> list[dict]:
    """Approved ECU profiles matching the filters.

    RLS restricts non-admins to the approved set, so unverified submissions are
    never returned here. Admins see their approved rows too (pending review lives
    under ``/diag/admin/profiles/pending-review``).
    """
    pc = t.diag_ecu_profiles.c
    conds = [pc.verification_status.in_(APPROVED_STATUSES)]
    if make:
        conds.append(func.lower(pc.make) == make.lower())
    if model:
        conds.append(func.lower(pc.model) == model.lower())
    if year is not None:
        conds.append(and_(or_(pc.year_from.is_(None), pc.year_from <= year), or_(pc.year_to.is_(None), pc.year_to >= year)))
    async with svc.db.user(user.id) as conn:
        rows = (
            (
                await conn.execute(
                    select(t.diag_ecu_profiles)
                    .where(*conds)
                    .order_by(pc.make, pc.model, pc.year_from.nulls_first(), pc.id)
                )
            )
            .mappings()
            .all()
        )
    return [_profile_out(r) for r in rows]


# ----------------------------------------------------------------------------- admin
@router.get("/admin/profiles/pending-review")
async def pending_review(admin: AdminUser, svc: SvcDep) -> list[dict]:
    """Profiles awaiting a verification decision (``verification_status = 'unverified'``)."""
    pc = t.diag_ecu_profiles.c
    async with svc.db.user(admin.id) as conn:
        rows = (
            (
                await conn.execute(
                    select(t.diag_ecu_profiles)
                    .where(pc.verification_status == "unverified")
                    .order_by(pc.created_at.desc(), pc.id)
                )
            )
            .mappings()
            .all()
        )
    return [_profile_out(r) for r in rows]


def _validate_profile(body: ProfileIn) -> None:
    if body.year_from is not None and body.year_to is not None and body.year_from > body.year_to:
        raise validation("year_from must be <= year_to", {"field": "year_from"})
    if body.protocol is not None:
        meta = _protocol_meta()
        if body.protocol not in meta:
            raise validation("unknown protocol", {"field": "protocol", "known": sorted(meta)})
        proto_bits = meta[body.protocol]
        if proto_bits is not None and body.id_bits is not None and proto_bits != body.id_bits:
            raise validation("id_bits does not match the protocol", {"field": "id_bits"})
    for field, raw in (("tx_header", body.tx_header), ("rx_header", body.rx_header), ("read_request", body.read_request)):
        if raw is None:
            continue
        cleaned = _hex(raw, field)
        if field != "read_request" and body.id_bits is not None:
            want = _HEADER_NIBBLES[body.id_bits]
            if len(cleaned) != want:
                raise validation(
                    f"{field} must be {want} hex digits for a {body.id_bits}-bit CAN id", {"field": field}
                )


@router.post("/admin/profiles", status_code=201)
async def submit_profile(body: ProfileIn, admin: AdminUser, svc: SvcDep, ctx: CtxDep) -> dict:
    """Submit a candidate profile. It is always stored ``unverified`` and must be
    approved by a *different* admin before it becomes visible to users."""
    _validate_profile(body)
    values = body.model_dump()
    # Normalise hex fields to upper-case, no 0x prefix.
    for f in ("tx_header", "rx_header", "read_request"):
        if values[f] is not None:
            values[f] = _hex(values[f], f)
    values.update(verification_status="unverified", submitted_by=admin.id)
    async with svc.db.user(admin.id) as conn:
        row = (
            (await conn.execute(t.diag_ecu_profiles.insert().values(**values).returning(t.diag_ecu_profiles)))
            .mappings()
            .one()
        )
        await audit(
            conn,
            ctx,
            "diag.profile_submit",
            actor=admin.id,
            entity_type="diag_ecu_profile",
            entity_id=row["id"],
            metadata={"make": row["make"], "model": row["model"]},
        )
    return _profile_out(row)


@router.post("/admin/profiles/{profile_id}/approve")
async def approve_profile(profile_id: uuid.UUID, body: ApproveIn, admin: AdminUser, svc: SvcDep, ctx: CtxDep) -> dict:
    """Record a verification decision.

    Separation of duties: the reviewer must be a *different* admin from the
    submitter (403 otherwise). Writes an ``audit_logs`` entry and bumps ``version``.
    """
    pc = t.diag_ecu_profiles.c
    self_review = False
    async with svc.db.user(admin.id) as conn:
        before = (
            (await conn.execute(select(t.diag_ecu_profiles).where(pc.id == profile_id))).mappings().first()
        )
        if before is None:
            raise not_found("profile")
        if before["submitted_by"] is not None and before["submitted_by"] == admin.id:
            # Audit the denial and commit it, then refuse outside the transaction.
            await audit(
                conn,
                ctx,
                "diag.profile_review",
                actor=admin.id,
                entity_type="diag_ecu_profile",
                entity_id=profile_id,
                outcome="denied",
                metadata={"reason": "self_review"},
            )
            self_review = True
    if self_review:
        raise forbidden("a profile must be reviewed by a different administrator than the submitter")
    async with svc.db.user(admin.id) as conn:
        row = (
            (
                await conn.execute(
                    t.diag_ecu_profiles.update()
                    .where(pc.id == profile_id)
                    .values(
                        verification_status=body.verification_status,
                        source_type=body.source_type,
                        source_reference=body.source_reference,
                        reviewed_by=admin.id,
                        reviewed_at=datetime.now(UTC),
                        version=before["version"] + 1,
                    )
                    .returning(t.diag_ecu_profiles)
                )
            )
            .mappings()
            .one()
        )
        await audit(
            conn,
            ctx,
            "diag.profile_review",
            actor=admin.id,
            entity_type="diag_ecu_profile",
            entity_id=profile_id,
            before={"verification_status": before["verification_status"], "version": before["version"]},
            after={"verification_status": row["verification_status"], "version": row["version"]},
        )
    return _profile_out(row)
