"""Shared FastAPI dependencies: services, principal, pagination, request context."""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Annotated, Any

from fastapi import Depends, Query, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select

from automind.core.config import Settings
from automind.core.crypto import Cipher
from automind.core.errors import APIError, unauthorized
from automind.core.logging import request_id_var
from automind.core.security import Passwords, TokenError, Tokens
from automind.db import tables as t
from automind.db.session import Database

STAFF_ROLES = ("support", "admin", "super_admin")
ADMIN_ROLES = ("admin", "super_admin")


@dataclass
class Services:
    settings: Settings
    db: Database
    passwords: Passwords
    tokens: Tokens
    cipher: Cipher
    blind_key: bytes


def get_services(request: Request) -> Services:
    return request.app.state.services


def get_db(request: Request) -> Database:
    return request.app.state.services.db


@dataclass(frozen=True)
class RequestContext:
    ip: str | None
    user_agent: str | None
    request_id: str | None


def client_ip(request: Request) -> str | None:
    settings: Settings = request.app.state.services.settings
    if settings.trust_proxy_headers:
        # Each trusted proxy appends the address it received the connection from, so only the
        # right-most ``trusted_proxy_count`` entries are trustworthy; anything to their left was sent
        # by the client and must never be used (it would let anyone dodge per-IP rate limits).
        hops = [h.strip() for v in request.headers.getlist("x-forwarded-for") for h in v.split(",") if h.strip()]
        if hops:
            return hops[-min(settings.trusted_proxy_count, len(hops))]
    return request.client.host if request.client else None


def _valid_inet(ip: str | None) -> str | None:
    import ipaddress

    if not ip:
        return None
    try:
        return str(ipaddress.ip_address(ip))
    except ValueError:
        return None


def get_ctx(request: Request) -> RequestContext:
    return RequestContext(
        ip=_valid_inet(client_ip(request)),
        user_agent=(request.headers.get("user-agent") or "")[:400] or None,
        request_id=request_id_var.get(),
    )


@dataclass(frozen=True)
class Principal:
    id: uuid.UUID
    email: str
    role: str
    status: str
    mfa_enabled: bool
    token_mfa: bool

    @property
    def is_staff(self) -> bool:
        return self.role in STAFF_ROLES


_bearer = HTTPBearer(auto_error=False)


async def get_principal(
    request: Request,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)],
) -> Principal:
    if creds is None or creds.scheme.lower() != "bearer" or not creds.credentials:
        raise unauthorized()
    svc: Services = request.app.state.services
    try:
        claims = svc.tokens.decode_access(creds.credentials)
    except TokenError as exc:
        raise unauthorized("invalid or expired access token") from exc
    async with svc.db.system() as conn:
        row = (
            await conn.execute(
                select(
                    t.users.c.id,
                    t.users.c.email,
                    t.users.c.platform_role,
                    t.users.c.status,
                    t.users.c.mfa_enabled,
                ).where(t.users.c.id == claims.sub, t.users.c.deleted_at.is_(None))
            )
        ).first()
    if row is None or row.status != "active":
        raise unauthorized("account is not active")
    p = Principal(
        id=row.id,
        email=row.email,
        role=row.platform_role,
        status=row.status,
        mfa_enabled=row.mfa_enabled,
        token_mfa=claims.mfa,
    )
    request.state.principal = p
    return p


CurrentUser = Annotated[Principal, Depends(get_principal)]


async def require_staff(p: CurrentUser) -> Principal:
    if p.role not in STAFF_ROLES:
        raise APIError(403, "forbidden", "platform staff only")
    # Every staff role (support included: it can read users and audit logs) must sign in with MFA.
    if not (p.mfa_enabled and p.token_mfa):
        raise APIError(403, "mfa_required", "platform staff must sign in with MFA", {"mfa_enabled": p.mfa_enabled})
    return p


async def require_admin(p: Annotated[Principal, Depends(require_staff)]) -> Principal:
    if p.role not in ADMIN_ROLES:
        raise APIError(403, "forbidden", "administrators only")
    return p


StaffUser = Annotated[Principal, Depends(require_staff)]
AdminUser = Annotated[Principal, Depends(require_admin)]


@dataclass(frozen=True)
class PageParams:
    limit: int
    offset: int


def page_params(
    limit: Annotated[int, Query(ge=1, le=100)] = 20, offset: Annotated[int, Query(ge=0, le=10_000_000)] = 0
) -> PageParams:
    return PageParams(limit, offset)


Page = Annotated[PageParams, Depends(page_params)]


def page(items: list[Any], total: int, p: PageParams) -> dict[str, Any]:
    return {"items": items, "total": int(total), "limit": p.limit, "offset": p.offset}


SvcDep = Annotated[Services, Depends(get_services)]
CtxDep = Annotated[RequestContext, Depends(get_ctx)]
