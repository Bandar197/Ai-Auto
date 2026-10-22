"""Registration, login, token refresh/logout and MFA enrolment."""

from __future__ import annotations

import re
from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select, update

from automind.api.audit import audit
from automind.api.deps import CtxDep, CurrentUser, SvcDep
from automind.api.serializers import user_out
from automind.core.errors import APIError, conflict, unauthorized, validation
from automind.core.security import (
    PasswordPolicyError,
    RefreshError,
    check_password_policy,
    create_auth_session,
    decrypt_mfa_secret,
    encrypt_mfa_secret,
    hash_refresh_token,
    new_totp_secret,
    register_failed_login,
    revoke_family,
    rotate_refresh_token,
    totp_uri,
    verify_totp,
)
from automind.db import tables as t

router = APIRouter(prefix="/auth", tags=["auth"])

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _email(v: str) -> str:
    v = (v or "").strip()
    if len(v) > 254 or not EMAIL_RE.match(v):
        raise ValueError("invalid e-mail address")
    return v


class RegisterIn(BaseModel):
    email: str
    password: str = Field(max_length=256)
    full_name: str | None = Field(None, max_length=200)
    locale: Literal["ar", "en"] = "ar"
    accept_terms_version: str = Field(min_length=1, max_length=50)
    accept_privacy_version: str = Field(min_length=1, max_length=50)

    _v_email = field_validator("email")(lambda cls, v: _email(v))


class LoginIn(BaseModel):
    email: str = Field(max_length=254)
    password: str = Field(max_length=256)
    totp_code: str | None = Field(None, max_length=10)


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=10, max_length=200)


class CodeIn(BaseModel):
    code: str = Field(min_length=6, max_length=10)


USER_COLS = (
    t.users.c.id,
    t.users.c.email,
    t.users.c.full_name,
    t.users.c.phone,
    t.users.c.locale,
    t.users.c.platform_role,
    t.users.c.mfa_enabled,
    t.users.c.created_at,
)


@router.post("/register", status_code=201)
async def register(body: RegisterIn, svc: SvcDep, ctx: CtxDep) -> dict:
    try:
        check_password_policy(body.password, body.email)
    except PasswordPolicyError as exc:
        raise validation(str(exc), {"field": "password"}) from exc
    pw_hash = await svc.passwords.hash(body.password)
    async with svc.db.system() as conn:
        exists = (
            await conn.execute(
                select(t.users.c.id).where(func.lower(t.users.c.email) == body.email.lower(), t.users.c.deleted_at.is_(None))
            )
        ).first()
        if exists:
            raise conflict("an account with this e-mail already exists", {"field": "email"})
        user = (
            (
                await conn.execute(
                    t.users.insert()
                    .values(
                        email=body.email,
                        password_hash=pw_hash,
                        full_name=body.full_name,
                        locale=body.locale,
                    )
                    .returning(*USER_COLS)
                )
            )
            .mappings()
            .one()
        )
        await conn.execute(
            t.user_consents.insert(),
            [
                {
                    "user_id": user["id"],
                    "purpose": "terms",
                    "document_version": body.accept_terms_version,
                    "granted": True,
                    "ip_address": ctx.ip,
                },
                {
                    "user_id": user["id"],
                    "purpose": "privacy_policy",
                    "document_version": body.accept_privacy_version,
                    "granted": True,
                    "ip_address": ctx.ip,
                },
            ],
        )
        tokens = await create_auth_session(
            conn,
            svc.tokens,
            user_id=user["id"],
            role=user["platform_role"],
            mfa=False,
            user_agent=ctx.user_agent,
            ip=ctx.ip,
        )
        await audit(conn, ctx, "auth.register", actor=user["id"], entity_type="user", entity_id=user["id"])
    return {"user": user_out(user), "tokens": tokens.as_dict()}


@router.post("/login")
async def login(body: LoginIn, svc: SvcDep, ctx: CtxDep) -> dict:
    email = body.email.strip()
    async with svc.db.system() as conn:
        row = (
            (
                await conn.execute(
                    select(t.users).where(func.lower(t.users.c.email) == email.lower(), t.users.c.deleted_at.is_(None))
                )
            )
            .mappings()
            .first()
        )

    if row is None:
        await svc.passwords.verify(None, body.password)  # equalise timing
        async with svc.db.system() as conn:
            await audit(conn, ctx, "auth.login", outcome="failure", metadata={"reason": "unknown_email"})
        raise unauthorized("invalid e-mail or password")

    now = datetime.now(UTC)
    if row["locked_until"] is not None and row["locked_until"] > now:
        async with svc.db.system() as conn:
            await audit(
                conn,
                ctx,
                "auth.login",
                actor=row["id"],
                entity_type="user",
                entity_id=row["id"],
                outcome="denied",
                metadata={"reason": "locked"},
            )
        retry = int((row["locked_until"] - now).total_seconds()) + 1
        raise APIError(
            401,
            "unauthorized",
            "account temporarily locked after repeated failed sign-ins",
            {"reason": "account_locked", "retry_after_s": retry},
        )

    ok = await svc.passwords.verify(row["password_hash"], body.password)
    if not ok:
        async with svc.db.system() as conn:
            locked = await register_failed_login(conn, svc.settings, row["id"])
            await audit(
                conn,
                ctx,
                "auth.login",
                actor=row["id"],
                entity_type="user",
                entity_id=row["id"],
                outcome="failure",
                metadata={"reason": "bad_password", "locked": locked is not None},
            )
        raise unauthorized("invalid e-mail or password")

    if row["status"] == "suspended":
        async with svc.db.system() as conn:
            await audit(
                conn,
                ctx,
                "auth.login",
                actor=row["id"],
                entity_type="user",
                entity_id=row["id"],
                outcome="denied",
                metadata={"reason": "suspended"},
            )
        raise APIError(403, "forbidden", "account suspended")
    if row["status"] != "active":
        raise unauthorized("account is not active")

    mfa_ok = False
    if row["mfa_enabled"]:
        if not body.totp_code:
            raise APIError(403, "mfa_required", "a TOTP code is required for this account")
        secret = decrypt_mfa_secret(svc.cipher, row["id"], row["mfa_secret_ciphertext"])
        if not verify_totp(secret, body.totp_code):
            async with svc.db.system() as conn:
                await register_failed_login(conn, svc.settings, row["id"])
                await audit(
                    conn,
                    ctx,
                    "auth.login",
                    actor=row["id"],
                    entity_type="user",
                    entity_id=row["id"],
                    outcome="failure",
                    metadata={"reason": "bad_totp"},
                )
            raise unauthorized("invalid MFA code")
        mfa_ok = True

    values: dict = {"failed_login_count": 0, "locked_until": None, "last_login_at": now}
    if svc.passwords.needs_rehash(row["password_hash"]):
        values["password_hash"] = await svc.passwords.hash(body.password)
    async with svc.db.system() as conn:
        await conn.execute(update(t.users).where(t.users.c.id == row["id"]).values(**values))
        tokens = await create_auth_session(
            conn,
            svc.tokens,
            user_id=row["id"],
            role=row["platform_role"],
            mfa=mfa_ok,
            user_agent=ctx.user_agent,
            ip=ctx.ip,
        )
        await audit(
            conn,
            ctx,
            "auth.login",
            actor=row["id"],
            entity_type="user",
            entity_id=row["id"],
            metadata={"mfa": mfa_ok, "rehashed": "password_hash" in values},
        )
    return {"user": user_out(row), "tokens": tokens.as_dict()}


@router.post("/refresh")
async def refresh(body: RefreshIn, svc: SvcDep, ctx: CtxDep) -> dict:
    error: RefreshError | None = None
    async with svc.db.system() as conn:
        try:
            issued, _uid = await rotate_refresh_token(conn, svc.tokens, body.refresh_token, user_agent=ctx.user_agent, ip=ctx.ip)
        except RefreshError as exc:
            error = exc
            if exc.reason == "reuse":
                await audit(
                    conn,
                    ctx,
                    "auth.refresh_reuse_detected",
                    actor=exc.user_id,
                    entity_type="auth_family",
                    entity_id=exc.family_id,
                    outcome="denied",
                )
    # commit happened above (family revocation must persist even on failure)
    if error is not None:
        raise unauthorized("invalid refresh token", {"reason": error.reason})
    return {"tokens": issued.as_dict()}


@router.post("/logout", status_code=204)
async def logout(body: RefreshIn, svc: SvcDep, ctx: CtxDep) -> Response:
    async with svc.db.system() as conn:
        row = (
            await conn.execute(
                select(t.auth_sessions.c.user_id, t.auth_sessions.c.family_id).where(
                    t.auth_sessions.c.refresh_token_hash == hash_refresh_token(body.refresh_token)
                )
            )
        ).first()
        if row is not None:
            await revoke_family(conn, row.family_id)
            await audit(
                conn,
                ctx,
                "auth.logout",
                actor=row.user_id,
                entity_type="auth_family",
                entity_id=row.family_id,
            )
    return Response(status_code=204)


@router.post("/mfa/setup")
async def mfa_setup(user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> dict:
    if user.mfa_enabled:
        raise conflict("MFA is already enabled")
    secret = new_totp_secret()
    async with svc.db.user(user.id) as conn:
        await conn.execute(
            update(t.users)
            .where(t.users.c.id == user.id)
            .values(mfa_secret_ciphertext=encrypt_mfa_secret(svc.cipher, user.id, secret))
        )
        await audit(conn, ctx, "auth.mfa_setup", actor=user.id, entity_type="user", entity_id=user.id)
    return {"secret": secret, "otpauth_uri": totp_uri(secret, user.email)}


@router.post("/mfa/enable", status_code=204)
async def mfa_enable(body: CodeIn, user: CurrentUser, svc: SvcDep, ctx: CtxDep) -> Response:
    async with svc.db.user(user.id) as conn:
        row = (
            await conn.execute(select(t.users.c.mfa_enabled, t.users.c.mfa_secret_ciphertext).where(t.users.c.id == user.id))
        ).first()
        if row is None or row.mfa_secret_ciphertext is None:
            raise conflict("call /auth/mfa/setup first")
        if row.mfa_enabled:
            raise conflict("MFA is already enabled")
        secret = decrypt_mfa_secret(svc.cipher, user.id, row.mfa_secret_ciphertext)
        valid = verify_totp(secret, body.code)
        if valid:
            await conn.execute(update(t.users).where(t.users.c.id == user.id).values(mfa_enabled=True))
        await audit(
            conn,
            ctx,
            "auth.mfa_enable",
            actor=user.id,
            entity_type="user",
            entity_id=user.id,
            outcome="success" if valid else "failure",
        )
    if not valid:
        raise validation("invalid MFA code", {"field": "code"})
    return Response(status_code=204)
