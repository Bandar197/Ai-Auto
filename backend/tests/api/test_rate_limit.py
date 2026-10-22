"""Rate limiting: auth endpoints per IP, everything else per user → 429 rate_limited."""

from __future__ import annotations

import httpx
import pytest

from automind.core.ratelimit import InMemoryRateLimiter
from tests.api.test_health_errors import assert_envelope
from tests.conftest import make_settings, register


@pytest.fixture
async def limited_client(database_url):
    from automind.api.main import create_app

    app = create_app(make_settings(database_url, rate_limit_auth_per_min=3, rate_limit_user_per_min=5))
    transport = httpx.ASGITransport(app=app, client=("10.0.0.1", 1234))
    async with httpx.AsyncClient(transport=transport, base_url="http://t/api/v1") as c:
        yield c


async def test_auth_endpoints_limited_per_ip(limited_client):
    body = {"email": "nobody@example.com", "password": "wrong-password-1"}
    for _ in range(3):
        assert (await limited_client.post("/auth/login", json=body)).status_code == 401
    r = await limited_client.post("/auth/login", json=body)
    err = assert_envelope(r, 429, "rate_limited")
    assert int(r.headers["retry-after"]) >= 1 and err["details"]["retry_after_s"] >= 1
    assert r.headers.get("x-request-id")
    # health is never limited
    assert (await limited_client.get("/health")).status_code == 200


async def test_other_endpoints_limited_per_user(client, limited_client):
    a = await register(client)  # registered through the unlimited app
    b = await register(client)
    for _ in range(5):
        assert (await limited_client.get("/me", headers=a["headers"])).status_code == 200
    assert_envelope(await limited_client.get("/me", headers=a["headers"]), 429, "rate_limited")
    # a different user from the same IP has his own budget
    assert (await limited_client.get("/me", headers=b["headers"])).status_code == 200


@pytest.mark.nodb
async def test_in_memory_sliding_window():
    rl = InMemoryRateLimiter()
    assert all([(await rl.hit("k", 2, 60)).allowed for _ in range(2)])
    d = await rl.hit("k", 2, 60)
    assert not d.allowed and d.retry_after_s >= 1
    assert (await rl.hit("other", 2, 60)).allowed
    # window passes → allowed again
    rl._hits["k"] = type(rl._hits["k"])([0.0, 0.0])
    assert (await rl.hit("k", 2, 60)).allowed
