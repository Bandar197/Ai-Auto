"""Passwords, tokens, MFA and account lockout.

* Passwords: Argon2id (argon2-cffi), re-hashed on login when parameters change.
* Access tokens: short-lived JWT (``iss, aud, sub, role, mfa, iat, exp, jti, typ=access``);
  the algorithm is pinned to the configured one and ``iss``/``aud`` are verified.
* Refresh tokens: opaque ``secrets.token_urlsafe(48)``; only their SHA-256 is
  stored (``automind.auth_sessions``). Every use rotates the token; presenting
  an already-rotated token revokes the whole family (theft detection).
* TOTP (RFC 6238) via pyotp; the secret is stored AES-GCM encrypted.
* Lockout: ``lockout_threshold`` consecutive failures lock the account for
  ``lockout_minutes``.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import anyio
import jwt
import pyotp
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncConnection

from automind.core.config import Settings
from automind.core.crypto import Cipher
from automind.db import tables as t

MFA_ISSUER = "AutoMind AI"

# A small list of the most common passwords (≥ 10 chars, lower-case) — the
# policy also rejects any password equal to the e-mail or its local part.
COMMON_PASSWORDS = frozenset(
    {
        "1234567890",
        "12345678910",
        "123456789a",
        "0123456789",
        "0987654321",
        "1q2w3e4r5t",
        "1qaz2wsx3edc",
        "qwertyuiop",
        "asdfghjkl;",
        "password12",
        "password123",
        "password1234",
        "passw0rd123",
        "iloveyou12",
        "qwerty1234",
        "qwerty12345",
        "qwerty123456",
        "abcdefghij",
        "abc1234567",
        "11111111111",
        "1111111111",
        "0000000000",
        "aaaaaaaaaa",
        "letmein123",
        "welcome123",
        "admin12345",
        "administrator",
        "football123",
        "princess123",
        "sunshine123",
        "superman123",
        "dragon1234",
        "monkey1234",
        "baseball123",
        "trustno1234",
        "changeme123",
        "automind123",
        "automind2026",
        "saudiarabia",
        "riyadh12345",
        "123123123123",
        "987654321a",
        "zaq12wsxcde",
        "q1w2e3r4t5",
        "p@ssw0rd123",
        "password!1",
        "mypassword1",
        "secret12345",
    }
)


class PasswordPolicyError(ValueError):
    pass


def check_password_policy(password: str, email: str) -> None:
    if len(password) < 10:
        raise PasswordPolicyError("password must be at least 10 characters")
    if len(password) > 256:
        raise PasswordPolicyError("password must be at most 256 characters")
    low = password.lower()
    em = (email or "").strip().lower()
    if low == em or (em and low == em.split("@", 1)[0]):
        raise PasswordPolicyError("password must not be your e-mail address")
    if low in COMMON_PASSWORDS or len(set(low)) <= 2:
        raise PasswordPolicyError("password is too common")


class Passwords:
    def __init__(self, settings: Settings) -> None:
        self._ph = PasswordHasher(
            time_cost=settings.argon2_time_cost,
            memory_cost=settings.argon2_memory_kib,
            parallelism=settings.argon2_parallelism,
        )
        # Used to equalise timing when the account does not exist.
        self._dummy = self._ph.hash(secrets.token_urlsafe(16))

    async def hash(self, password: str) -> str:
        return await anyio.to_thread.run_sync(self._ph.hash, password)

    async def verify(self, hashed: str | None, password: str) -> bool:
        def _v() -> bool:
            try:
                return self._ph.verify(hashed or self._dummy, password) and hashed is not None
            except (VerifyMismatchError, VerificationError, InvalidHashError):
                return False

        return await anyio.to_thread.run_sync(_v)

    def needs_rehash(self, hashed: str) -> bool:
        try:
            return self._ph.check_needs_rehash(hashed)
        except InvalidHashError:
            return True


# ----------------------------------------------------------------------------- JWT
@dataclass(frozen=True)
class AccessClaims:
    sub: uuid.UUID
    role: str
    mfa: bool
    jti: str
    iat: int
    exp: int


class TokenError(Exception):
    pass


class Tokens:
    def __init__(self, settings: Settings) -> None:
        self.s = settings
        if settings.jwt_algorithm.startswith("HS"):
            self._sign_key: Any = settings.jwt_secret.get_secret_value()
            self._verify_key: Any = self._sign_key
        else:
            if not (settings.jwt_private_key and settings.jwt_public_key):
                raise ValueError("RS256/ES256 need AUTOMIND_JWT_PRIVATE_KEY and AUTOMIND_JWT_PUBLIC_KEY")
            self._sign_key = settings.jwt_private_key.get_secret_value()
            self._verify_key = settings.jwt_public_key

    def issue_access(self, user_id: uuid.UUID, role: str, mfa: bool) -> str:
        now = int(datetime.now(UTC).timestamp())
        claims = {
            "iss": self.s.jwt_issuer,
            "aud": self.s.jwt_audience,
            "sub": str(user_id),
            "role": role,
            "mfa": bool(mfa),
            "iat": now,
            "exp": now + self.s.access_token_ttl_s,
            "jti": uuid.uuid4().hex,
            "typ": "access",
        }
        return jwt.encode(claims, self._sign_key, algorithm=self.s.jwt_algorithm)

    def decode_access(self, token: str) -> AccessClaims:
        try:
            c = jwt.decode(
                token,
                self._verify_key,
                algorithms=[self.s.jwt_algorithm],
                issuer=self.s.jwt_issuer,
                audience=self.s.jwt_audience,
                options={"require": ["iss", "aud", "sub", "exp", "iat", "jti", "typ"]},
            )
        except jwt.PyJWTError as exc:
            raise TokenError(str(exc)) from exc
        if c.get("typ") != "access":
            raise TokenError("not an access token")
        try:
            sub = uuid.UUID(str(c["sub"]))
        except ValueError as exc:
            raise TokenError("bad subject") from exc
        return AccessClaims(
            sub=sub,
            role=str(c.get("role", "user")),
            mfa=bool(c.get("mfa", False)),
            jti=str(c["jti"]),
            iat=int(c["iat"]),
            exp=int(c["exp"]),
        )


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_refresh_token(token: str) -> bytes:
    return hashlib.sha256(token.encode("utf-8")).digest()


# ----------------------------------------------------------------------------- TOTP
def new_totp_secret() -> str:
    return pyotp.random_base32()


def totp_uri(secret: str, email: str) -> str:
    return pyotp.TOTP(secret).provisioning_uri(name=email, issuer_name=MFA_ISSUER)


def totp_match_step(secret: str, code: str | None, *, at: datetime | None = None) -> int | None:
    """Time step (unix time // 30) the code belongs to, within one step of clock drift, else None.

    Callers must record the step and refuse it (or any earlier step) next time: that is what
    stops a code from being replayed inside its validity window.
    """
    if not code:
        return None
    code = code.strip().replace(" ", "")
    if not code.isdigit() or len(code) != 6:
        return None
    totp = pyotp.TOTP(secret)
    now = int((at or datetime.now(UTC)).timestamp()) // totp.interval
    for step in (now - 1, now, now + 1):
        if hmac.compare_digest(totp.generate_otp(step), code):
            return step
    return None


def verify_totp(secret: str, code: str | None) -> bool:
    return totp_match_step(secret, code) is not None


async def consume_totp_step(conn: AsyncConnection, user_id: uuid.UUID, step: int) -> bool:
    """Atomically record ``step`` as used; False if it (or a later one) was already used."""
    res = await conn.execute(
        update(t.users)
        .where(
            t.users.c.id == user_id,
            (t.users.c.mfa_last_used_step.is_(None)) | (t.users.c.mfa_last_used_step < step),
        )
        .values(mfa_last_used_step=step)
    )
    return res.rowcount == 1


def encrypt_mfa_secret(cipher: Cipher, user_id: uuid.UUID, secret: str) -> bytes:
    return cipher.encrypt(secret, aad=b"mfa:" + str(user_id).encode())


def decrypt_mfa_secret(cipher: Cipher, user_id: uuid.UUID, blob: bytes) -> str:
    return cipher.decrypt_str(blob, aad=b"mfa:" + str(user_id).encode())


# ----------------------------------------------------------------------------- sessions (DB)
@dataclass
class IssuedTokens:
    access_token: str
    refresh_token: str
    expires_in: int

    def as_dict(self) -> dict[str, Any]:
        return {
            "access_token": self.access_token,
            "refresh_token": self.refresh_token,
            "token_type": "bearer",
            "expires_in": self.expires_in,
        }


async def create_auth_session(
    conn: AsyncConnection,
    tokens: Tokens,
    *,
    user_id: uuid.UUID,
    role: str,
    mfa: bool,
    family_id: uuid.UUID | None = None,
    user_agent: str | None = None,
    ip: str | None = None,
) -> IssuedTokens:
    """Insert a refresh-token row (system connection) and mint both tokens."""
    refresh = new_refresh_token()
    now = datetime.now(UTC)
    await conn.execute(
        t.auth_sessions.insert().values(
            user_id=user_id,
            refresh_token_hash=hash_refresh_token(refresh),
            family_id=family_id or uuid.uuid4(),
            user_agent=(user_agent or "")[:400] or None,
            ip_address=ip,
            mfa_verified=mfa,
            created_at=now,
            expires_at=now + timedelta(seconds=tokens.s.refresh_token_ttl_s),
        )
    )
    return IssuedTokens(tokens.issue_access(user_id, role, mfa), refresh, tokens.s.access_token_ttl_s)


class RefreshError(Exception):
    def __init__(self, reason: str, user_id: uuid.UUID | None = None, family_id: uuid.UUID | None = None):
        super().__init__(reason)
        self.reason = reason
        self.user_id = user_id
        self.family_id = family_id


async def rotate_refresh_token(
    conn: AsyncConnection,
    tokens: Tokens,
    refresh_token: str,
    *,
    user_agent: str | None = None,
    ip: str | None = None,
) -> tuple[IssuedTokens, uuid.UUID]:
    """Rotate a refresh token. Raises RefreshError; reuse revokes the family.

    Must run on a system connection. On ``RefreshError("reuse")`` the caller
    must still COMMIT so that the family revocation persists.
    """
    h = hash_refresh_token(refresh_token)
    row = (await conn.execute(select(t.auth_sessions).where(t.auth_sessions.c.refresh_token_hash == h))).mappings().first()
    if row is None:
        raise RefreshError("unknown")
    now = datetime.now(UTC)
    if row["rotated_at"] is not None:
        await revoke_family(conn, row["family_id"])
        raise RefreshError("reuse", row["user_id"], row["family_id"])
    if row["revoked_at"] is not None:
        raise RefreshError("revoked", row["user_id"], row["family_id"])
    if row["expires_at"] <= now:
        raise RefreshError("expired", row["user_id"], row["family_id"])
    # Atomic claim: a concurrent refresh with the same token loses and is treated as reuse.
    claimed = (
        await conn.execute(
            update(t.auth_sessions)
            .where(
                t.auth_sessions.c.id == row["id"],
                t.auth_sessions.c.rotated_at.is_(None),
                t.auth_sessions.c.revoked_at.is_(None),
            )
            .values(rotated_at=now)
            .returning(t.auth_sessions.c.id)
        )
    ).first()
    if claimed is None:
        await revoke_family(conn, row["family_id"])
        raise RefreshError("reuse", row["user_id"], row["family_id"])
    user = (await conn.execute(select(t.users.c.platform_role, t.users.c.status).where(t.users.c.id == row["user_id"]))).first()
    if user is None or user.status != "active":
        await revoke_family(conn, row["family_id"])
        raise RefreshError("inactive", row["user_id"], row["family_id"])
    issued = await create_auth_session(
        conn,
        tokens,
        user_id=row["user_id"],
        role=user.platform_role,
        mfa=row["mfa_verified"],
        family_id=row["family_id"],
        user_agent=user_agent,
        ip=ip,
    )
    return issued, row["user_id"]


async def revoke_family(conn: AsyncConnection, family_id: uuid.UUID) -> None:
    await conn.execute(
        update(t.auth_sessions)
        .where(t.auth_sessions.c.family_id == family_id, t.auth_sessions.c.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )


async def revoke_all_user_sessions(conn: AsyncConnection, user_id: uuid.UUID) -> None:
    await conn.execute(
        update(t.auth_sessions)
        .where(t.auth_sessions.c.user_id == user_id, t.auth_sessions.c.revoked_at.is_(None))
        .values(revoked_at=datetime.now(UTC))
    )


# ----------------------------------------------------------------------------- lockout (DB)
async def register_failed_login(conn: AsyncConnection, settings: Settings, user_id: uuid.UUID) -> datetime | None:
    """Atomically increment the failure counter; lock the account at the threshold.

    Returns ``locked_until`` when this failure triggered a lock.
    """
    count = (
        await conn.execute(
            update(t.users)
            .where(t.users.c.id == user_id)
            .values(failed_login_count=t.users.c.failed_login_count + 1)
            .returning(t.users.c.failed_login_count)
        )
    ).scalar_one()
    if count < settings.lockout_threshold:
        return None
    locked_until = datetime.now(UTC) + timedelta(minutes=settings.lockout_minutes)
    await conn.execute(update(t.users).where(t.users.c.id == user_id).values(failed_login_count=0, locked_until=locked_until))
    return locked_until
