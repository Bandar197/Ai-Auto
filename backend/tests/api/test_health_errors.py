"""Health checks, error envelope, request id, security headers."""

from __future__ import annotations


def assert_envelope(r, status: int, code: str) -> dict:
    assert r.status_code == status, r.text
    body = r.json()
    assert set(body) == {"error"}
    assert set(body["error"]) == {"code", "message", "details"}
    assert body["error"]["code"] == code
    assert isinstance(body["error"]["message"], str) and body["error"]["message"]
    assert isinstance(body["error"]["details"], dict)
    return body["error"]


async def test_health(client):
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"
    assert r.json()["version"]


async def test_ready_checks_database(client):
    r = await client.get("/health/ready")
    assert r.status_code == 200, r.text
    assert r.json()["checks"]["database"] == "ok"


async def test_request_id_generated_and_echoed(client):
    r = await client.get("/health")
    assert len(r.headers["x-request-id"]) >= 16
    r = await client.get("/health", headers={"X-Request-ID": "abc-123"})
    assert r.headers["x-request-id"] == "abc-123"
    # invalid ids are replaced, never reflected
    r = await client.get("/health", headers={"X-Request-ID": "<script>"})
    assert r.headers["x-request-id"] != "<script>"


async def test_security_headers(client):
    r = await client.get("/health")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["x-frame-options"] == "DENY"
    assert "default-src 'none'" in r.headers["content-security-policy"]


async def test_unknown_route_is_enveloped(client):
    r = await client.get("/does-not-exist")
    assert_envelope(r, 404, "not_found")
    assert r.headers.get("x-request-id")


async def test_unauthenticated_is_enveloped(client):
    assert_envelope(await client.get("/me"), 401, "unauthorized")
    assert_envelope(await client.get("/me", headers={"Authorization": "Bearer nope"}), 401, "unauthorized")


async def test_validation_error_envelope_does_not_echo_input(client):
    r = await client.post("/auth/register", json={"email": "x@example.com", "password": 123456789012})
    err = assert_envelope(r, 422, "validation_error")
    assert err["details"]["errors"]
    assert "123456789012" not in r.text


async def test_method_not_allowed_enveloped(client):
    r = await client.put("/health")
    assert_envelope(r, 405, "method_not_allowed")
