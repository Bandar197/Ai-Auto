"""Sliding-window rate limiting (Redis when configured, in-memory fallback)."""

from __future__ import annotations

import logging
import time
import uuid
from collections import deque
from dataclasses import dataclass

log = logging.getLogger("automind.ratelimit")


@dataclass(frozen=True)
class Decision:
    allowed: bool
    remaining: int
    retry_after_s: int


class InMemoryRateLimiter:
    """Sliding-window log per key. Single-process only (dev/tests/fallback)."""

    def __init__(self, max_keys: int = 100_000) -> None:
        self._hits: dict[str, deque[float]] = {}
        self._max_keys = max_keys

    async def hit(self, key: str, limit: int, window_s: int = 60) -> Decision:
        now = time.monotonic()
        q = self._hits.get(key)
        if q is None:
            if len(self._hits) >= self._max_keys:
                self._evict(now, window_s)
            q = self._hits[key] = deque()
        while q and q[0] <= now - window_s:
            q.popleft()
        if len(q) >= limit:
            retry = max(1, int(q[0] + window_s - now) + 1)
            return Decision(False, 0, retry)
        q.append(now)
        return Decision(True, limit - len(q), 0)

    def _evict(self, now: float, window_s: int) -> None:
        for k in [k for k, q in self._hits.items() if not q or q[-1] <= now - window_s]:
            del self._hits[k]
        if len(self._hits) >= self._max_keys:  # still full: drop oldest half
            for k in list(self._hits)[: self._max_keys // 2]:
                del self._hits[k]

    async def close(self) -> None:
        return None


class RedisRateLimiter:
    """Sliding-window log in a Redis sorted set; falls back to memory on Redis errors."""

    def __init__(self, url: str) -> None:
        from redis import asyncio as aioredis

        self._redis = aioredis.from_url(url, socket_timeout=0.5, socket_connect_timeout=0.5)
        self._fallback = InMemoryRateLimiter()

    async def hit(self, key: str, limit: int, window_s: int = 60) -> Decision:
        now = time.time()
        rkey = f"automind:rl:{key}"
        try:
            pipe = self._redis.pipeline(transaction=True)
            pipe.zremrangebyscore(rkey, 0, now - window_s)
            pipe.zcard(rkey)
            pipe.zrange(rkey, 0, 0, withscores=True)
            _, count, oldest = await pipe.execute()
            if count >= limit:
                first = oldest[0][1] if oldest else now
                return Decision(False, 0, max(1, int(first + window_s - now) + 1))
            pipe = self._redis.pipeline(transaction=True)
            pipe.zadd(rkey, {f"{now}:{uuid.uuid4().hex[:8]}": now})
            pipe.expire(rkey, window_s + 1)
            await pipe.execute()
            return Decision(True, limit - count - 1, 0)
        except Exception:  # noqa: BLE001 - availability over strictness
            log.warning("redis rate limiter unavailable; using in-memory fallback", exc_info=True)
            return await self._fallback.hit(key, limit, window_s)

    async def close(self) -> None:
        await self._redis.aclose()


def build_rate_limiter(redis_url: str | None) -> InMemoryRateLimiter | RedisRateLimiter:
    return RedisRateLimiter(redis_url) if redis_url else InMemoryRateLimiter()
