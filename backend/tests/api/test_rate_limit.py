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


def _request(settings, xff: list[str], peer: str = "10.0.0.1"):
    from types import SimpleNamespace

    from starlette.requests import Request

    app = SimpleNamespace(state=SimpleNamespace(services=SimpleNamespace(settings=settings)))
    headers = [(b"x-forwarded-for", v.encode()) for v in xff]
    return Request({"type": "http", "headers": headers, "client": (peer, 1234), "app": app})


@pytest.mark.nodb
def test_client_ip_ignores_spoofable_forwarded_for_entries():
    from automind.api.deps import client_ip
    from automind.core.config import Settings

    untrusted = Settings(environment="test")
    assert client_ip(_request(untrusted, ["6.6.6.6"])) == "10.0.0.1"  # header ignored unless trusted

    one = Settings(environment="test", trust_proxy_headers=True)
    # the client sent "6.6.6.6"; our proxy appended the real peer address 203.0.113.7
    assert client_ip(_request(one, ["6.6.6.6, 203.0.113.7"])) == "203.0.113.7"
    assert client_ip(_request(one, ["6.6.6.6", "203.0.113.7"])) == "203.0.113.7"  # repeated headers
    assert client_ip(_request(one, ["203.0.113.7"])) == "203.0.113.7"
    assert client_ip(_request(one, [" , "])) == "10.0.0.1"
    assert client_ip(_request(one, [])) == "10.0.0.1"

    two = Settings(environment="test", trust_proxy_headers=True, trusted_proxy_count=2)
    assert client_ip(_request(two, ["6.6.6.6, 203.0.113.7, 10.1.0.5"])) == "203.0.113.7"
    assert client_ip(_request(two, ["203.0.113.7"])) == "203.0.113.7"  # fewer hops than configured


async def test_rotating_forwarded_for_does_not_bypass_auth_limit(database_url):
    from automind.api.main import create_app

    app = create_app(make_settings(database_url, rate_limit_auth_per_min=3, trust_proxy_headers=True))
    transport = httpx.ASGITransport(app=app, client=("10.0.0.2", 1234))
    body = {"email": "nobody@example.com", "password": "wrong-password-1"}
    async with httpx.AsyncClient(transport=transport, base_url="http://t/api/v1") as c:
        for i in range(3):
            r = await c.post("/auth/login", json=body, headers={"X-Forwarded-For": f"198.51.100.{i}, 203.0.113.9"})
            assert r.status_code == 401
        r = await c.post("/auth/login", json=body, headers={"X-Forwarded-For": "198.51.100.99, 203.0.113.9"})
        assert_envelope(r, 429, "rate_limited")
