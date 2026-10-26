"""Async engine + the two transaction scopes used by the API.

* ``system()`` — runs as the connection owner (bypasses RLS). Only for
  registration/login/refresh, workers and admin aggregates.
* ``user(user_id)`` — one transaction that first runs
  ``select set_config('app.user_id', :uid, true)`` and ``set local role
  automind_app`` so every statement is subject to Row Level Security.

Both are async context managers yielding an ``AsyncConnection`` inside a
transaction that commits on success and rolls back on exceptions.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection, AsyncEngine, create_async_engine
from sqlalchemy.pool import NullPool

from automind.core.config import Settings


class Database:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        kwargs: dict = {"pool_pre_ping": True}
        if settings.db_null_pool:
            kwargs["poolclass"] = NullPool
        else:
            kwargs.update(pool_size=settings.db_pool_size, max_overflow=settings.db_max_overflow)
        self.engine: AsyncEngine = create_async_engine(settings.database_url, **kwargs)
        # Validated as a plain identifier in Settings; quoted anyway.
        self._set_role_sql = text(f'set local role "{settings.db_app_role}"')

    @asynccontextmanager
    async def system(self) -> AsyncIterator[AsyncConnection]:
        async with self.engine.begin() as conn:
            yield conn

    @asynccontextmanager
    async def user(self, user_id: uuid.UUID | str) -> AsyncIterator[AsyncConnection]:
        uid = str(uuid.UUID(str(user_id)))  # validates
        async with self.engine.begin() as conn:
            await conn.execute(text("select set_config('app.user_id', :uid, true)"), {"uid": uid})
            await conn.execute(self._set_role_sql)
            yield conn

    async def ensure_partitions(self) -> int:
        async with self.system() as conn:
            return int((await conn.execute(text("select automind.ensure_telemetry_partitions()"))).scalar_one())

    async def ping(self) -> bool:
        async with self.engine.connect() as conn:
            await conn.execute(text("select 1"))
        return True

    async def dispose(self) -> None:
        await self.engine.dispose()
