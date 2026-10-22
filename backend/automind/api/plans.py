"""Subscription plan resolution and limit enforcement."""

from __future__ import annotations

import uuid
from collections.abc import Mapping
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncConnection

from automind.core.errors import APIError
from automind.db import tables as t

ACTIVE_SUB_STATUSES = ("trialing", "active", "past_due")
DEFAULT_PLAN_KEY = "basic"


async def current_subscription(
    conn: AsyncConnection, user_id: uuid.UUID
) -> tuple[Mapping[str, Any] | None, Mapping[str, Any] | None]:
    """Return (subscription_row | None, plan_row | None) — plan falls back to Basic."""
    sub = (
        (
            await conn.execute(
                select(t.subscriptions)
                .where(t.subscriptions.c.user_id == user_id, t.subscriptions.c.status.in_(ACTIVE_SUB_STATUSES))
                .order_by(t.subscriptions.c.created_at.desc())
                .limit(1)
            )
        )
        .mappings()
        .first()
    )
    plan = None
    if sub is not None:
        plan = (
            (await conn.execute(select(t.subscription_plans).where(t.subscription_plans.c.id == sub["plan_id"])))
            .mappings()
            .first()
        )
    if plan is None:
        plan = (
            (await conn.execute(select(t.subscription_plans).where(t.subscription_plans.c.key == DEFAULT_PLAN_KEY)))
            .mappings()
            .first()
        )
    return sub, plan


async def enforce_limit(conn: AsyncConnection, user_id: uuid.UUID, limit_key: str, current: int) -> None:
    _, plan = await current_subscription(conn, user_id)
    limits = (plan or {}).get("limits") or {}
    limit = limits.get(limit_key)
    if isinstance(limit, (int, float)) and current >= limit:
        raise APIError(
            403,
            "plan_limit",
            f"your plan allows {int(limit)} {limit_key}",
            {"limit": limit_key, "max": int(limit), "plan": (plan or {}).get("key")},
        )
