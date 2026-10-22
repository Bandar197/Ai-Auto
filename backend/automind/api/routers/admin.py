"""Platform administration. Staff only; admins/super-admins must use MFA.

Aggregates run on the system connection (owner, bypasses RLS) *after* the
staff check, because they span all tenants. Numbers are never invented:
ratios without data are ``null``.
"""

from __future__ import annotations

import csv
import io
import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any, Literal

from fastapi import APIRouter, Query, Response
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select, text, update

from automind.api.audit import audit
from automind.api.deps import AdminUser, CtxDep, Page, StaffUser, SvcDep, page
from automind.api.serializers import num, plain, plan_out
from automind.core.errors import forbidden, not_found, validation
from automind.core.security import revoke_all_user_sessions
from automind.db import tables as t

router = APIRouter(prefix="/admin", tags=["admin"])


def _bounds() -> dict[str, datetime]:
    now = datetime.now(UTC)
    day = now.replace(hour=0, minute=0, second=0, microsecond=0)
    return {
        "now": now,
        "day_start": day,
        "month_start": day.replace(day=1),
        "d30": now - timedelta(days=30),
        "h24": now - timedelta(hours=24),
    }


OVERVIEW_SQL = text("""
select
  (select count(*) from automind.users where deleted_at is null) as users_total,
  (select count(*) from automind.users u where u.deleted_at is null and (u.last_login_at >= :d30
      or exists (select 1 from automind.auth_sessions a where a.user_id = u.id and a.created_at >= :d30)))
      as users_active_30d,
  (select count(*) from automind.vehicles where deleted_at is null) as vehicles_total,
  (select count(*) from automind.obd_devices) as devices_total,
  (select count(*) from automind.diagnostic_sessions where started_at >= :day_start) as sessions_today,
  (select count(*) from automind.diagnostic_sessions where started_at >= :month_start) as sessions_month,
  (select count(*) from automind.diagnostic_sessions where started_at >= :month_start and data_mode = 'live')
      as mode_live,
  (select count(*) from automind.diagnostic_sessions where started_at >= :month_start and data_mode = 'demo')
      as mode_demo,
  (select count(*) from automind.diagnostic_sessions
      where started_at >= :month_start and data_mode = 'replay') as mode_replay,
  (select count(*) from automind.vehicle_connections where started_at >= :d30) as conn_total,
  (select count(*) from automind.vehicle_connections where started_at >= :d30
      and adapter_status = 'connected' and ecu_status = 'connected') as conn_ok,
  (select count(*) from automind.ai_diagnoses where user_feedback is not null) as fb_total,
  (select count(*) from automind.ai_diagnoses where user_feedback is not null and confirmed_cause is not null)
      as fb_confirmed,
  (select coalesce(sum(amount), 0) from automind.payments where status = 'succeeded' and currency = 'SAR'
      and coalesce(paid_at, created_at) >= :month_start) as revenue_month_sar,
  (select count(*) from automind.subscriptions where cancelled_at >= :month_start) as cancelled_month,
  (select count(*) from automind.workshops) as workshops_total,
  (select count(*) from automind.suppliers) as suppliers_total,
  (select count(*) from automind.parts_orders where created_at >= :month_start) as orders_month,
  (select count(*) from automind.system_errors where occurred_at >= :h24) as errors_24h,
  (select count(*) from automind.ai_diagnoses
      where created_at >= :month_start and model is not null) as ai_requests,
  (select coalesce(sum(input_tokens), 0) from automind.ai_diagnoses
      where created_at >= :month_start) as ai_in,
  (select coalesce(sum(output_tokens), 0) from automind.ai_diagnoses
      where created_at >= :month_start) as ai_out,
  (select coalesce(sum(cost_usd), 0) from automind.ai_diagnoses
      where created_at >= :month_start) as ai_cost
""")


def _ratio(ok: int, total: int) -> float | None:
    return round(ok / total, 4) if total else None


@router.get("/stats/overview")
async def overview(staff: StaffUser, svc: SvcDep) -> dict:
    b = _bounds()
    async with svc.db.system() as conn:
        r = (await conn.execute(OVERVIEW_SQL, b)).mappings().one()
        subs = (
            await conn.execute(
                text("""
            select p.key, count(s.id) as n
            from automind.subscription_plans p
            left join automind.subscriptions s
              on s.plan_id = p.id and s.status in ('trialing', 'active', 'past_due')
            group by p.key order by p.key""")
            )
        ).all()
    return {
        "users_total": r["users_total"],
        "users_active_30d": r["users_active_30d"],
        "vehicles_total": r["vehicles_total"],
        "devices_total": r["devices_total"],
        "sessions_today": r["sessions_today"],
        "sessions_month": r["sessions_month"],
        "sessions_by_mode": {"live": r["mode_live"], "demo": r["mode_demo"], "replay": r["mode_replay"]},
        "connection_success_rate_30d": _ratio(r["conn_ok"], r["conn_total"]),
        "diagnosis_confirmed_rate": _ratio(r["fb_confirmed"], r["fb_total"]),
        "active_subscriptions_by_plan": {k: int(n) for k, n in subs},
        "revenue_month_sar": float(r["revenue_month_sar"]),
        "cancelled_subscriptions_month": r["cancelled_month"],
        "workshops_total": r["workshops_total"],
        "suppliers_total": r["suppliers_total"],
        "orders_month": r["orders_month"],
        "errors_24h": r["errors_24h"],
        "ai_usage_month": {
            "requests": r["ai_requests"],
            "input_tokens": int(r["ai_in"]),
            "output_tokens": int(r["ai_out"]),
            "cost_usd": float(r["ai_cost"]),
        },
    }


TIMESERIES_SQL = {
    "sessions": "select (started_at at time zone 'UTC')::date as d, count(*) as v "
    "from automind.diagnostic_sessions where started_at >= :start group by 1",
    "signups": "select (created_at at time zone 'UTC')::date as d, count(*) as v from automind.users "
    "where created_at >= :start group by 1",
    "revenue": "select (coalesce(paid_at, created_at) at time zone 'UTC')::date as d, sum(amount) as v "
    "from automind.payments where status = 'succeeded' and currency = 'SAR' "
    "and coalesce(paid_at, created_at) >= :start group by 1",
    "connections": "select (started_at at time zone 'UTC')::date as d, count(*) as v, "
    "count(*) filter (where adapter_status = 'connected' and ecu_status = 'connected') as ok "
    "from automind.vehicle_connections where started_at >= :start group by 1",
}


@router.get("/stats/timeseries")
async def timeseries(
    staff: StaffUser,
    svc: SvcDep,
    metric: Literal["sessions", "connections", "signups", "revenue"] = "sessions",
    days: int = Query(30, ge=1, le=365),
) -> dict:
    today = datetime.now(UTC).date()
    first = today - timedelta(days=days - 1)
    start = datetime(first.year, first.month, first.day, tzinfo=UTC)
    async with svc.db.system() as conn:
        rows = (await conn.execute(text(TIMESERIES_SQL[metric]), {"start": start})).mappings().all()
    by_day = {r["d"]: r for r in rows}
    points = []
    for i in range(days):
        d: date = first + timedelta(days=i)
        r = by_day.get(d)
        v = num(r["v"]) if r else 0
        point: dict[str, Any] = {"date": d.isoformat(), "value": float(v) if metric == "revenue" else int(v)}
        if metric == "connections":
            ok = int(r["ok"]) if r else 0
            point.update(success=ok, failure=int(v) - ok)
        points.append(point)
    return {"metric": metric, "points": points}


async def _top_dtcs(conn, days: int, limit: int) -> list[dict]:
    rows = (
        await conn.execute(
            text("""
        select d.code, count(*) as n, max(d.description_en) as en, max(d.description_ar) as ar
        from automind.diagnostic_trouble_codes d
        join automind.diagnostic_sessions s on s.id = d.session_id
        where d.detected_at >= :start and s.data_mode = 'live'
        group by d.code order by n desc, d.code limit :lim"""),
            {"start": datetime.now(UTC) - timedelta(days=days), "lim": limit},
        )
    ).all()
    kb = None
    try:
        from automind.diagnosis.kb import get_kb

        kb = get_kb()
    except ImportError:
        pass
    out = []
    for code, n, en, ar in rows:
        d = kb.lookup(code) if kb else None
        out.append(
            {
                "code": code,
                "count": int(n),
                "description_en": (d or {}).get("en") or en,
                "description_ar": (d or {}).get("ar") or ar,
            }
        )
    return out


@router.get("/stats/top-dtcs")
async def top_dtcs(
    staff: StaffUser, svc: SvcDep, days: int = Query(30, ge=1, le=365), limit: int = Query(10, ge=1, le=100)
) -> list[dict]:
    """Most frequent codes in *live* sessions (simulated demo/replay data is excluded)."""
    async with svc.db.system() as conn:
        return await _top_dtcs(conn, days, limit)


def _admin_user_query():
    u = t.users.c
    vehicles = (
        select(func.count())
        .select_from(t.vehicles)
        .where(t.vehicles.c.owner_user_id == u.id, t.vehicles.c.deleted_at.is_(None))
        .scalar_subquery()
    )
    sessions = (
        select(func.count()).select_from(t.diagnostic_sessions).where(t.diagnostic_sessions.c.user_id == u.id).scalar_subquery()
    )
    return select(
        u.id,
        u.email,
        u.full_name,
        u.platform_role,
        u.status,
        u.mfa_enabled,
        u.created_at,
        u.last_login_at,
        vehicles.label("vehicles"),
        sessions.label("sessions"),
    )


def _admin_user_out(r) -> dict:
    return {
        "id": str(r["id"]),
        "email": r["email"],
        "full_name": r["full_name"],
        "platform_role": r["platform_role"],
        "status": r["status"],
        "mfa_enabled": r["mfa_enabled"],
        "created_at": r["created_at"],
        "last_login_at": r["last_login_at"],
        "vehicles": int(r["vehicles"]),
        "sessions": int(r["sessions"]),
    }


def _like(q: str) -> str:
    return "%" + q.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


@router.get("/users")
async def list_users(staff: StaffUser, svc: SvcDep, p: Page, q: str = Query("", max_length=200)) -> dict:
    u = t.users.c
    cond = u.deleted_at.is_(None)
    if q.strip():
        pat = _like(q.strip())
        cond = cond & or_(u.email.ilike(pat, escape="\\"), u.full_name.ilike(pat, escape="\\"))
    async with svc.db.system() as conn:
        total = (await conn.execute(select(func.count()).select_from(t.users).where(cond))).scalar_one()
        rows = (
            (await conn.execute(_admin_user_query().where(cond).order_by(u.created_at.desc()).limit(p.limit).offset(p.offset)))
            .mappings()
            .all()
        )
    return page([_admin_user_out(r) for r in rows], total, p)


class AdminUserPatch(BaseModel):
    status: Literal["active", "suspended", "pending_deletion", "deleted"] | None = None
    platform_role: Literal["user", "support", "admin", "super_admin"] | None = None


@router.patch("/users/{user_id}")
async def patch_user(user_id: uuid.UUID, body: AdminUserPatch, admin: AdminUser, svc: SvcDep, ctx: CtxDep) -> dict:
    values = body.model_dump(exclude_none=True)
    if not values:
        raise validation("nothing to change")
    if user_id == admin.id:
        raise forbidden("you cannot change your own role or status")
    async with svc.db.system() as conn:
        before = (
            (
                await conn.execute(
                    select(t.users.c.platform_role, t.users.c.status).where(
                        t.users.c.id == user_id, t.users.c.deleted_at.is_(None)
                    )
                )
            )
            .mappings()
            .first()
        )
        if before is None:
            raise not_found("user")
        role_change = "platform_role" in values and values["platform_role"] != before["platform_role"]
        if (role_change or before["platform_role"] == "super_admin") and admin.role != "super_admin":
            await audit(
                conn,
                ctx,
                "admin.user_update",
                actor=admin.id,
                entity_type="user",
                entity_id=user_id,
                outcome="denied",
                metadata={"requested": values},
            )
            denied = True
        else:
            denied = False
            if values.get("status") == "deleted":
                values["deleted_at"] = datetime.now(UTC)
            await conn.execute(update(t.users).where(t.users.c.id == user_id).values(**values))
            if values.get("status") in ("suspended", "pending_deletion", "deleted") or role_change:
                await revoke_all_user_sessions(conn, user_id)
            await audit(
                conn,
                ctx,
                "admin.user_update",
                actor=admin.id,
                entity_type="user",
                entity_id=user_id,
                before=dict(before),
                after={k: v for k, v in body.model_dump(exclude_none=True).items()},
            )
            row = (await conn.execute(_admin_user_query().where(t.users.c.id == user_id))).mappings().one()
    if denied:
        raise forbidden("only a super_admin can change roles or modify a super_admin")
    return _admin_user_out(row)


@router.get("/errors")
async def list_errors(staff: StaffUser, svc: SvcDep, p: Page, component: str | None = Query(None, max_length=50)) -> dict:
    cond = t.system_errors.c.component == component if component else None
    async with svc.db.system() as conn:
        cq = select(func.count()).select_from(t.system_errors)
        q = select(t.system_errors).order_by(t.system_errors.c.occurred_at.desc(), t.system_errors.c.id.desc())
        if cond is not None:
            cq, q = cq.where(cond), q.where(cond)
        total = (await conn.execute(cq)).scalar_one()
        rows = (await conn.execute(q.limit(p.limit).offset(p.offset))).mappings().all()
    return page([plain(r) for r in rows], total, p)


@router.get("/audit-logs")
async def list_audit_logs(
    staff: StaffUser,
    svc: SvcDep,
    p: Page,
    action: str | None = Query(None, max_length=80),
    actor_user_id: uuid.UUID | None = None,
) -> dict:
    a = t.audit_logs.c
    conds = []
    if action:
        conds.append(a.action == action)
    if actor_user_id:
        conds.append(a.actor_user_id == actor_user_id)
    async with svc.db.system() as conn:
        cq = select(func.count()).select_from(t.audit_logs).where(*conds)
        total = (await conn.execute(cq)).scalar_one()
        rows = (
            (
                await conn.execute(
                    select(t.audit_logs).where(*conds).order_by(a.occurred_at.desc(), a.id.desc()).limit(p.limit).offset(p.offset)
                )
            )
            .mappings()
            .all()
        )
    return page(
        [{**plain(r), "ip_address": str(r["ip_address"]) if r["ip_address"] else None} for r in rows],
        total,
        p,
    )


@router.get("/plans")
async def admin_plans(staff: StaffUser, svc: SvcDep) -> list[dict]:
    async with svc.db.system() as conn:
        rows = (await conn.execute(select(t.subscription_plans).order_by(t.subscription_plans.c.sort_order))).mappings().all()
    return [plan_out(r) for r in rows]


class PlanPatch(BaseModel):
    name_en: str | None = Field(None, min_length=1, max_length=80)
    name_ar: str | None = Field(None, min_length=1, max_length=80)
    price_monthly: float | None = Field(None, ge=0, le=1_000_000)
    price_yearly: float | None = Field(None, ge=0, le=10_000_000)
    features: dict[str, Any] | None = None
    limits: dict[str, Any] | None = None
    active: bool | None = None
    sort_order: int | None = Field(None, ge=0, le=1000)


@router.patch("/plans/{key}")
async def patch_plan(key: str, body: PlanPatch, admin: AdminUser, svc: SvcDep, ctx: CtxDep) -> dict:
    values = body.model_dump(exclude_unset=True)
    for k in ("name_en", "name_ar", "features", "limits", "active", "sort_order"):
        if k in values and values[k] is None:
            raise validation(f"{k} cannot be null", {"field": k})
    if isinstance(values.get("limits"), dict):
        for lk, lv in values["limits"].items():
            if not isinstance(lv, (int, float)) or isinstance(lv, bool) or lv < 0:
                raise validation("limits must be non-negative numbers", {"field": f"limits.{lk}"})
    async with svc.db.system() as conn:
        before = (await conn.execute(select(t.subscription_plans).where(t.subscription_plans.c.key == key))).mappings().first()
        if before is None:
            raise not_found("plan")
        if values:
            await conn.execute(update(t.subscription_plans).where(t.subscription_plans.c.key == key).values(**values))
        after = (await conn.execute(select(t.subscription_plans).where(t.subscription_plans.c.key == key))).mappings().one()
        await audit(
            conn,
            ctx,
            "admin.plan_update",
            actor=admin.id,
            entity_type="subscription_plan",
            entity_id=key,
            before=plan_out(before),
            after=plan_out(after),
        )
    return plan_out(after)


def _csv_cell(v: Any) -> Any:
    if v is None:
        return ""
    if isinstance(v, datetime):
        return v.isoformat()
    s = str(v)
    # Spreadsheet formula injection guard.
    if s and s[0] in ("=", "+", "-", "@", "\t", "\r"):
        return "'" + s
    return s


EXPORT_LIMIT = 100_000


@router.get("/export/{dataset}.csv", response_model=None)
async def export_csv(dataset: str, admin: AdminUser, svc: SvcDep, ctx: CtxDep) -> Response:
    if dataset not in ("users", "sessions", "connections", "top-dtcs"):
        raise not_found("dataset")
    async with svc.db.system() as conn:
        if dataset == "users":
            u = t.users.c
            header = [
                "id",
                "email",
                "full_name",
                "platform_role",
                "status",
                "mfa_enabled",
                "created_at",
                "last_login_at",
            ]
            res = await conn.execute(
                select(*(getattr(u, h) for h in header)).where(u.deleted_at.is_(None)).order_by(u.created_at).limit(EXPORT_LIMIT)
            )
            rows = [list(r) for r in res.all()]
        elif dataset == "sessions":
            s = t.diagnostic_sessions.c
            header = [
                "id",
                "user_id",
                "vehicle_id",
                "data_mode",
                "status",
                "dtc_count",
                "health_score",
                "mil_on",
                "engine_version",
                "kb_version",
                "started_at",
                "completed_at",
            ]
            res = await conn.execute(select(*(getattr(s, h) for h in header)).order_by(s.started_at).limit(EXPORT_LIMIT))
            rows = [list(r) for r in res.all()]
        elif dataset == "connections":
            c = t.vehicle_connections.c
            header = [
                "id",
                "user_id",
                "device_id",
                "vehicle_id",
                "data_mode",
                "transport",
                "adapter_status",
                "ecu_status",
                "protocol_name",
                "adapter_firmware",
                "attempts",
                "latency_ms",
                "error_code",
                "app_platform",
                "app_version",
                "started_at",
                "ended_at",
            ]
            res = await conn.execute(select(*(getattr(c, h) for h in header)).order_by(c.started_at).limit(EXPORT_LIMIT))
            rows = [list(r) for r in res.all()]
        else:
            header = ["code", "count", "description_en", "description_ar"]
            rows = [[d[h] for h in header] for d in await _top_dtcs(conn, 30, 100)]
        await audit(
            conn,
            ctx,
            "admin.export",
            actor=admin.id,
            entity_type="dataset",
            entity_id=dataset,
            metadata={"rows": len(rows)},
        )
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(header)
    for r in rows:
        w.writerow([_csv_cell(v) for v in r])
    stamp = datetime.now(UTC).strftime("%Y%m%d")
    return Response(
        buf.getvalue().encode("utf-8-sig"),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="automind-{dataset}-{stamp}.csv"'},
    )
