"""Small JSON response cache with a TTL (Redis when configured, in-process fallback).

Used for responses that are expensive to produce (LLM calls cost money). The
Redis variant degrades to the in-process cache on Redis errors, like the rate
limiter: availability over strictness.
"""

from __future__ import annotations

import json
import logging
import time
from collections import OrderedDict
from typing import Any

log = logging.getLogger("automind.cache")


class InMemoryTTLCache:
    """LRU + TTL, single process (dev/tests/fallback)."""

    def __init__(self, max_entries: int = 5000) -> None:
        self._data: OrderedDict[str, tuple[float, Any]] = OrderedDict()
        self._max = max_entries

    async def get(self, key: str) -> Any | None:
        item = self._data.get(key)
        if item is None:
            return None
        expires, value = item
        if expires <= time.monotonic():
            self._data.pop(key, None)
            return None
        self._data.move_to_end(key)
        return json.loads(value)

    async def set(self, key: str, value: Any, ttl_s: int) -> None:
        # Stored serialised so callers can never mutate a cached object in place.
        self._data[key] = (time.monotonic() + ttl_s, json.dumps(value, ensure_ascii=False))
        self._data.move_to_end(key)
        while len(self._data) > self._max:
            self._data.popitem(last=False)

    async def clear(self) -> None:
        self._data.clear()

    async def close(self) -> None:
        return None


class RedisTTLCache:
    def __init__(self, url: str, prefix: str = "automind:cache:") -> None:
        from redis import asyncio as aioredis

        self._redis = aioredis.from_url(url, socket_timeout=0.5, socket_connect_timeout=0.5)
        self._prefix = prefix
        self._fallback = InMemoryTTLCache()

    async def get(self, key: str) -> Any | None:
        try:
            raw = await self._redis.get(self._prefix + key)
        except Exception:  # noqa: BLE001 - availability over strictness
            log.warning("redis cache unavailable; using in-memory fallback", exc_info=True)
            return await self._fallback.get(key)
        return json.loads(raw) if raw else None

    async def set(self, key: str, value: Any, ttl_s: int) -> None:
        try:
            await self._redis.set(self._prefix + key, json.dumps(value, ensure_ascii=False), ex=ttl_s)
        except Exception:  # noqa: BLE001
            log.warning("redis cache unavailable; using in-memory fallback", exc_info=True)
            await self._fallback.set(key, value, ttl_s)

    async def close(self) -> None:
        await self._redis.aclose()


def build_cache(redis_url: str | None, prefix: str = "automind:cache:") -> InMemoryTTLCache | RedisTTLCache:
    return RedisTTLCache(redis_url, prefix) if redis_url else InMemoryTTLCache()
