"""FastAPI application factory (``uvicorn automind.api.main:app``)."""

from __future__ import annotations

import logging
import re
import time
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.responses import Response

from automind.api.deps import Services, client_ip
from automind.core.cache import build_cache
from automind.core.config import Settings, get_settings
from automind.core.crypto import Cipher
from automind.core.errors import error_response, install_error_handlers, unexpected_error_response
from automind.core.logging import configure_logging, request_id_var
from automind.core.ratelimit import build_rate_limiter
from automind.core.security import Passwords, TokenError, Tokens
from automind.db.session import Database

log = logging.getLogger("automind.api")

_REQUEST_ID_RE = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")

SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Cache-Control": "no-store",
}


def build_services(settings: Settings) -> Services:
    return Services(
        settings=settings,
        db=Database(settings),
        passwords=Passwords(settings),
        tokens=Tokens(settings),
        cipher=Cipher(settings.data_key_bytes),
        blind_key=settings.blind_key_bytes,
    )


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    if settings.environment != "test":
        configure_logging(settings.log_level, settings.log_json)
    services = build_services(settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        if settings.db_ensure_partitions_on_startup:
            try:
                created = await services.db.ensure_partitions()
                log.info("telemetry partitions ensured", extra={"created": created})
            except Exception:  # noqa: BLE001 - the API can still serve; /health/ready reports DB state
                log.exception("could not ensure telemetry partitions")
        yield
        await app.state.rate_limiter.close()
        await app.state.explain_cache.close()
        await services.db.dispose()

    docs = settings.environment != "prod"
    app = FastAPI(
        title="AutoMind AI API",
        version=settings.version,
        lifespan=lifespan,
        docs_url=f"{settings.api_prefix}/docs" if docs else None,
        redoc_url=None,
        openapi_url=f"{settings.api_prefix}/openapi.json" if docs else None,
    )
    app.state.services = services
    app.state.db = services.db
    app.state.rate_limiter = build_rate_limiter(settings.redis_url)
    app.state.explain_cache = build_cache(settings.redis_url, prefix="automind:explain:")

    install_error_handlers(app)

    prefix = settings.api_prefix
    auth_prefix = f"{prefix}/auth/"
    exempt = (f"{prefix}/health", f"{prefix}/docs", f"{prefix}/openapi.json")

    @app.middleware("http")
    async def request_context(request: Request, call_next) -> Response:
        rid = request.headers.get("x-request-id")
        if not rid or not _REQUEST_ID_RE.match(rid):
            rid = uuid.uuid4().hex
        token = request_id_var.set(rid)
        start = time.perf_counter()
        status = 500
        try:
            response = await _rate_limit(request)
            if response is None:
                try:
                    response = await call_next(request)
                except Exception as exc:  # noqa: BLE001 - keep the envelope + request id on 500s
                    response = await unexpected_error_response(request, exc)
            status = response.status_code
            response.headers["X-Request-ID"] = rid
            for k, v in SECURITY_HEADERS.items():
                response.headers.setdefault(k, v)
            if settings.environment == "prod":
                response.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
            return response
        finally:
            principal = getattr(request.state, "principal", None)
            log.info(
                "request",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status": status,
                    "duration_ms": round((time.perf_counter() - start) * 1000, 1),
                    "user_id": str(principal.id) if principal else None,
                },
            )
            request_id_var.reset(token)

    async def _rate_limit(request: Request) -> Response | None:
        if not settings.rate_limit_enabled or request.method == "OPTIONS":
            return None
        path = request.url.path
        if not path.startswith(prefix) or path.startswith(exempt):
            return None
        limiter = request.app.state.rate_limiter
        if path.startswith(auth_prefix):
            key, limit = f"ip:{client_ip(request)}:auth", settings.rate_limit_auth_per_min
        else:
            key, limit = f"ip:{client_ip(request)}", settings.rate_limit_user_per_min
            authz = request.headers.get("authorization", "")
            if authz.lower().startswith("bearer "):
                try:
                    key = f"user:{services.tokens.decode_access(authz[7:].strip()).sub}"
                except TokenError:
                    pass
        decision = await limiter.hit(key, limit, 60)
        if decision.allowed:
            return None
        return error_response(
            429,
            "rate_limited",
            "too many requests, slow down",
            {"retry_after_s": decision.retry_after_s},
            headers={"Retry-After": str(decision.retry_after_s)},
        )

    # CORS is added last so it wraps everything (including 429 responses).
    if settings.cors_origin_list:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origin_list,
            allow_credentials=False,
            allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
            expose_headers=["X-Request-ID", "Retry-After", "Content-Disposition"],
            max_age=600,
        )

    from automind.api.routers import (
        admin,
        analysis,
        auth,
        clear_verify,
        commerce,
        control,
        devices,
        diag,
        health,
        kb,
        me,
        recordings,
        sessions,
        vehicles,
    )

    for module in (
        health,
        auth,
        me,
        vehicles,
        devices,
        sessions,
        recordings,
        analysis,
        kb,
        control,
        clear_verify,
        commerce,
        diag,
        admin,
    ):
        app.include_router(module.router, prefix=prefix)
    return app


def _lazy_app() -> FastAPI:
    return create_app()


app = _lazy_app()
