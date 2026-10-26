"""Plans, the user's subscription and in-app notifications."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Response
from sqlalchemy import func, select, update

from automind.api.deps import CurrentUser, Page, SvcDep, page
from automind.api.plans import current_subscription
from automind.api.serializers import plain, plan_out
from automind.core.errors import not_found
from automind.db import tables as t

router = APIRouter(tags=["commerce"])


@router.get("/plans")
async def list_plans(svc: SvcDep) -> list[dict]:
    """Public: active plans (shown on the paywall before sign-in)."""
    async with svc.db.system() as conn:
        rows = (
            (
                await conn.execute(
                    select(t.subscription_plans)
                    .where(t.subscription_plans.c.active.is_(True))
                    .order_by(t.subscription_plans.c.sort_order)
                )
            )
            .mappings()
            .all()
        )
    return [plan_out(r) for r in rows]


@router.get("/me/subscription")
async def my_subscription(user: CurrentUser, svc: SvcDep) -> dict:
    async with svc.db.user(user.id) as conn:
        sub, plan = await current_subscription(conn, user.id)
    return {
        "subscription": plain(sub) if sub else None,
        "plan": plan_out(plan) if plan else None,
        "is_default": sub is None,
    }


@router.get("/notifications")
async def list_notifications(user: CurrentUser, svc: SvcDep, p: Page, unread_only: bool = False) -> dict:
    cond = t.notifications.c.user_id == user.id
    if unread_only:
        cond = cond & t.notifications.c.read_at.is_(None)
    async with svc.db.user(user.id) as conn:
        total = (await conn.execute(select(func.count()).select_from(t.notifications).where(cond))).scalar_one()
        rows = (
            (
                await conn.execute(
                    select(t.notifications)
                    .where(cond)
                    .order_by(t.notifications.c.created_at.desc())
                    .limit(p.limit)
                    .offset(p.offset)
                )
            )
            .mappings()
            .all()
        )
    return page([plain(r) for r in rows], total, p)


@router.post("/notifications/{notification_id}/read", status_code=204)
async def mark_read(notification_id: uuid.UUID, user: CurrentUser, svc: SvcDep) -> Response:
    async with svc.db.user(user.id) as conn:
        res = await conn.execute(
            update(t.notifications)
            .where(t.notifications.c.id == notification_id, t.notifications.c.user_id == user.id)
            .values(read_at=func.coalesce(t.notifications.c.read_at, datetime.now(UTC)))
            .returning(t.notifications.c.id)
        )
        if res.first() is None:
            raise not_found("notification")
    return Response(status_code=204)
