"""Registration, login, refresh rotation + reuse detection, logout, lockout, password policy, MFA."""

from __future__ import annotations

import jwt
import pyotp
import pytest

from tests.api.test_health_errors import assert_envelope
from tests.conftest import DEFAULT_PASSWORD, auth, register, unique_email


async def _audit_actions(db, user_id) -> list[str]:
    rows = await db.fetch("select action, outcome from automind.audit_logs where actor_user_id = $1 order by id", user_id)
    return [f"{r['action']}:{r['outcome']}" for r in rows]


async def test_register_returns_user_tokens_and_consents(client, db, settings):
    email = unique_email()
    data = await register(client, email=email.upper(), full_name="Ali", locale="en")
    user = data["user"]
    assert user["email"] == email.upper()
    assert user["platform_role"] == "user" and user["mfa_enabled"] is False and user["locale"] == "en"
    tokens = data["tokens"]
    assert tokens["token_type"] == "bearer" and tokens["expires_in"] == settings.access_token_ttl_s
    claims = jwt.decode(tokens["access_token"], settings.jwt_secret.get_secret_value(), algorithms=["HS256"])
    assert claims["sub"] == user["id"] and claims["typ"] == "access" and claims["mfa"] is False
    assert {"sub", "role", "mfa", "iat", "exp", "jti", "typ"} <= set(claims)
    # password stored as Argon2id, consents recorded, audit written
    row = await db.fetchrow("select password_hash from automind.users where id = $1", user["id"])
    assert row["password_hash"].startswith("$argon2id$")
    purposes = {
        r["purpose"]
        for r in await db.fetch("select purpose from automind.user_consents where user_id = $1 and granted", user["id"])
    }
    assert purposes == {"terms", "privacy_policy"}
    assert "auth.register:success" in await _audit_actions(db, user["id"])
    # refresh token stored only as a hash
    rt = tokens["refresh_token"]
    stored = await db.fetchval("select count(*) from automind.auth_sessions where refresh_token_hash = $1", rt.encode())
    assert stored == 0
    # duplicate (case-insensitive) e-mail
    r = await client.post(
        "/auth/register",
        json={"email": email.lower(), "password": DEFAULT_PASSWORD, "accept_terms_version": "1", "accept_privacy_version": "1"},
    )
    assert_envelope(r, 409, "conflict")


@pytest.mark.parametrize(
    "password,reason",
    [
        ("short1!", "at least 10"),
        ("password123", "too common"),
        ("aaaaaaaaaaaa", "too common"),
    ],
)
async def test_password_policy(client, password, reason):
    r = await client.post(
        "/auth/register",
        json={"email": unique_email(), "password": password, "accept_terms_version": "1", "accept_privacy_version": "1"},
    )
    err = assert_envelope(r, 422, "validation_error")
    assert reason in err["message"]


async def test_password_must_not_equal_email(client):
    email = unique_email()
    r = await client.post(
        "/auth/register",
        json={"email": email, "password": email.upper(), "accept_terms_version": "1", "accept_privacy_version": "1"},
    )
    assert_envelope(r, 422, "validation_error")


async def test_register_requires_consent_versions(client):
    r = await client.post("/auth/register", json={"email": unique_email(), "password": DEFAULT_PASSWORD})
    assert_envelope(r, 422, "validation_error")


async def test_login_and_me(client, db):
    reg = await register(client)
    r = await client.post("/auth/login", json={"email": reg["email"].upper(), "password": DEFAULT_PASSWORD})
    assert r.status_code == 200, r.text
    tokens = r.json()["tokens"]
    me = await client.get("/me", headers=auth(tokens))
    assert me.status_code == 200 and me.json()["id"] == reg["user"]["id"]
    assert await db.fetchval("select last_login_at is not null from automind.users where id = $1", reg["user"]["id"])
    bad = await client.post("/auth/login", json={"email": reg["email"], "password": "wrong-password-123"})
    assert_envelope(bad, 401, "unauthorized")
    unknown = await client.post("/auth/login", json={"email": unique_email(), "password": "whatever-12345"})
    assert_envelope(unknown, 401, "unauthorized")
    actions = await _audit_actions(db, reg["user"]["id"])
    assert "auth.login:success" in actions and "auth.login:failure" in actions


async def test_refresh_rotation_and_reuse_detection(client, db):
    reg = await register(client)
    rt1 = reg["tokens"]["refresh_token"]
    r = await client.post("/auth/refresh", json={"refresh_token": rt1})
    assert r.status_code == 200, r.text
    rt2 = r.json()["tokens"]["refresh_token"]
    assert rt2 != rt1
    assert (await client.get("/me", headers=auth(r.json()["tokens"]))).status_code == 200

    # rt2 → rt3 works
    r = await client.post("/auth/refresh", json={"refresh_token": rt2})
    assert r.status_code == 200
    rt3 = r.json()["tokens"]["refresh_token"]

    # Re-using the rotated rt1 is theft: the whole family is revoked …
    r = await client.post("/auth/refresh", json={"refresh_token": rt1})
    err = assert_envelope(r, 401, "unauthorized")
    assert err["details"]["reason"] == "reuse"
    # … so even the newest token no longer works.
    r = await client.post("/auth/refresh", json={"refresh_token": rt3})
    assert_envelope(r, 401, "unauthorized")
    assert "auth.refresh_reuse_detected:denied" in await _audit_actions(db, reg["user"]["id"])
    alive = await db.fetchval(
        "select count(*) from automind.auth_sessions where user_id = $1 and revoked_at is null", reg["user"]["id"]
    )
    assert alive == 0


async def test_refresh_reuse_does_not_touch_other_families(client):
    reg = await register(client)
    other = await client.post("/auth/login", json={"email": reg["email"], "password": DEFAULT_PASSWORD})
    other_rt = other.json()["tokens"]["refresh_token"]
    rt1 = reg["tokens"]["refresh_token"]
    await client.post("/auth/refresh", json={"refresh_token": rt1})
    await client.post("/auth/refresh", json={"refresh_token": rt1})  # reuse → family 1 revoked
    r = await client.post("/auth/refresh", json={"refresh_token": other_rt})
    assert r.status_code == 200


async def test_logout_revokes_refresh_token(client, db):
    reg = await register(client)
    rt = reg["tokens"]["refresh_token"]
    r = await client.post("/auth/logout", json={"refresh_token": rt})
    assert r.status_code == 204
    r = await client.post("/auth/refresh", json={"refresh_token": rt})
    err = assert_envelope(r, 401, "unauthorized")
    assert err["details"]["reason"] == "revoked"
    assert "auth.logout:success" in await _audit_actions(db, reg["user"]["id"])
    # idempotent for unknown tokens
    assert (await client.post("/auth/logout", json={"refresh_token": "x" * 64})).status_code == 204


async def test_lockout_after_five_failures(client, db):
    reg = await register(client)
    for _ in range(5):
        r = await client.post("/auth/login", json={"email": reg["email"], "password": "bad-password-000"})
        assert r.status_code == 401
    # now even the correct password is refused while locked
    r = await client.post("/auth/login", json={"email": reg["email"], "password": DEFAULT_PASSWORD})
    err = assert_envelope(r, 401, "unauthorized")
    assert err["details"]["reason"] == "account_locked"
    assert 0 < err["details"]["retry_after_s"] <= 15 * 60 + 1
    locked = await db.fetchval(
        "select locked_until > now() + interval '14 minutes' from automind.users where id=$1", reg["user"]["id"]
    )
    assert locked
    # lock expires → login works again and counters reset
    await db.execute("update automind.users set locked_until = now() - interval '1 second' where id = $1", reg["user"]["id"])
    r = await client.post("/auth/login", json={"email": reg["email"], "password": DEFAULT_PASSWORD})
    assert r.status_code == 200
    row = await db.fetchrow("select failed_login_count, locked_until from automind.users where id = $1", reg["user"]["id"])
    assert row["failed_login_count"] == 0 and row["locked_until"] is None


async def test_rehash_on_login_when_params_change(client, db, database_url):
    from automind.api.main import create_app
    from tests.conftest import make_settings

    reg = await register(client)
    old = await db.fetchval("select password_hash from automind.users where id=$1", reg["user"]["id"])
    import httpx

    stronger = create_app(make_settings(database_url, argon2_time_cost=2))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=stronger), base_url="http://t/api/v1") as c2:
        r = await c2.post("/auth/login", json={"email": reg["email"], "password": DEFAULT_PASSWORD})
        assert r.status_code == 200
    new = await db.fetchval("select password_hash from automind.users where id=$1", reg["user"]["id"])
    assert new != old and ",t=2," in new


async def test_suspended_user_cannot_login_or_use_token(client, db):
    reg = await register(client)
    await db.execute("update automind.users set status = 'suspended' where id = $1", reg["user"]["id"])
    r = await client.post("/auth/login", json={"email": reg["email"], "password": DEFAULT_PASSWORD})
    assert_envelope(r, 403, "forbidden")
    assert_envelope(await client.get("/me", headers=reg["headers"]), 401, "unauthorized")


async def test_mfa_setup_enable_and_login(client, db, settings):
    reg = await register(client)
    h = reg["headers"]
    r = await client.post("/auth/mfa/setup", headers=h)
    assert r.status_code == 200
    secret = r.json()["secret"]
    assert r.json()["otpauth_uri"].startswith("otpauth://totp/")
    # secret is stored encrypted, never in clear text
    blob = await db.fetchval("select mfa_secret_ciphertext from automind.users where id = $1", reg["user"]["id"])
    assert blob and secret.encode() not in bytes(blob) and bytes(blob)[:1] == b"\x01"
    assert_envelope(await client.post("/auth/mfa/enable", headers=h, json={"code": "000000"}), 422, "validation_error")
    r = await client.post("/auth/mfa/enable", headers=h, json={"code": pyotp.TOTP(secret).now()})
    assert r.status_code == 204
    # login now requires the code
    r = await client.post("/auth/login", json={"email": reg["email"], "password": DEFAULT_PASSWORD})
    assert_envelope(r, 403, "mfa_required")
    r = await client.post("/auth/login", json={"email": reg["email"], "password": DEFAULT_PASSWORD, "totp_code": "123456"})
    assert_envelope(r, 401, "unauthorized")
    r = await client.post(
        "/auth/login", json={"email": reg["email"], "password": DEFAULT_PASSWORD, "totp_code": pyotp.TOTP(secret).now()}
    )
    assert r.status_code == 200
    claims = jwt.decode(r.json()["tokens"]["access_token"], settings.jwt_secret.get_secret_value(), algorithms=["HS256"])
    assert claims["mfa"] is True
    # refresh keeps the MFA level of the session
    r2 = await client.post("/auth/refresh", json={"refresh_token": r.json()["tokens"]["refresh_token"]})
    claims2 = jwt.decode(r2.json()["tokens"]["access_token"], settings.jwt_secret.get_secret_value(), algorithms=["HS256"])
    assert claims2["mfa"] is True
    actions = await _audit_actions(db, reg["user"]["id"])
    assert "auth.mfa_setup:success" in actions and "auth.mfa_enable:success" in actions
    assert "auth.mfa_enable:failure" in actions


async def test_expired_or_forged_access_token_rejected(client, settings):
    reg = await register(client)
    claims = jwt.decode(reg["tokens"]["access_token"], settings.jwt_secret.get_secret_value(), algorithms=["HS256"])
    forged = jwt.encode({**claims, "role": "super_admin"}, "not-the-secret-but-long-enough-for-hs256-0123", algorithm="HS256")
    assert_envelope(await client.get("/me", headers=auth(forged)), 401, "unauthorized")
    expired = jwt.encode({**claims, "exp": claims["iat"] - 10}, settings.jwt_secret.get_secret_value(), algorithm="HS256")
    assert_envelope(await client.get("/me", headers=auth(expired)), 401, "unauthorized")
    none_alg = jwt.encode(claims, key=None, algorithm="none")
    assert_envelope(await client.get("/me", headers=auth(none_alg)), 401, "unauthorized")
