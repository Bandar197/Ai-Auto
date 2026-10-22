"""Append-only audit trail (``automind.audit_logs``)."""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncConnection

from automind.api.deps import RequestContext
from automind.db import tables as t


async def audit(
    conn: AsyncConnection,
    ctx: RequestContext | None,
    action: str,
    *,
    actor: uuid.UUID | None = None,
    entity_type: str | None = None,
    entity_id: Any = None,
    outcome: str = "success",
    metadata: dict[str, Any] | None = None,
    before: dict[str, Any] | None = None,
    after: dict[str, Any] | None = None,
) -> None:
    """Write one audit row on ``conn`` (system or user connection).

    On a user connection the RLS policy only accepts rows whose actor is the
    current user (or NULL), so callers must pass their own id as ``actor``.
    """
    await conn.execute(
        t.audit_logs.insert().values(
            actor_user_id=actor,
            action=action,
            entity_type=entity_type,
            entity_id=str(entity_id) if entity_id is not None else None,
            outcome=outcome,
            ip_address=ctx.ip if ctx else None,
            user_agent=ctx.user_agent if ctx else None,
            request_id=ctx.request_id if ctx else None,
            before_state=before,
            after_state=after,
            metadata=metadata or {},
        )
    )
