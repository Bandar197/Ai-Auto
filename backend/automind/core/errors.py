"""Error envelope ``{"error": {"code", "message", "details"}}`` and handlers.

Every error leaving the API — application errors, validation errors, unknown
routes, database constraint violations and unexpected exceptions — uses the
same shape so that the mobile app and the dashboard need a single parser.
"""

from __future__ import annotations

import logging
from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import DBAPIError
from starlette.exceptions import HTTPException as StarletteHTTPException

from automind.core.logging import request_id_var

log = logging.getLogger("automind.errors")


class APIError(Exception):
    """An error with an HTTP status and a stable machine-readable code."""

    def __init__(
        self,
        status: int,
        code: str,
        message: str,
        details: dict[str, Any] | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.details = details or {}
        self.headers = headers


def not_found(what: str = "resource") -> APIError:
    return APIError(404, "not_found", f"{what} not found")


def forbidden(message: str = "forbidden", details: dict[str, Any] | None = None) -> APIError:
    return APIError(403, "forbidden", message, details)


def unauthorized(message: str = "authentication required", details: dict[str, Any] | None = None) -> APIError:
    return APIError(401, "unauthorized", message, details, headers={"WWW-Authenticate": "Bearer"})


def conflict(message: str, details: dict[str, Any] | None = None) -> APIError:
    return APIError(409, "conflict", message, details)


def validation(message: str, details: dict[str, Any] | None = None) -> APIError:
    return APIError(422, "validation_error", message, details)


def error_body(code: str, message: str, details: dict[str, Any] | None = None) -> dict[str, Any]:
    return {"error": {"code": code, "message": message, "details": details or {}}}


def error_response(
    status: int,
    code: str,
    message: str,
    details: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    return JSONResponse(error_body(code, message, details), status_code=status, headers=headers)


_STATUS_CODES = {
    400: "bad_request",
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    405: "method_not_allowed",
    406: "not_acceptable",
    409: "conflict",
    413: "payload_too_large",
    415: "unsupported_media_type",
    422: "validation_error",
    429: "rate_limited",
}


def _sqlstate(exc: DBAPIError) -> str | None:
    orig = exc.orig
    for candidate in (orig, getattr(orig, "__cause__", None)):
        if candidate is None:
            continue
        code = getattr(candidate, "sqlstate", None) or getattr(candidate, "pgcode", None)
        if code:
            return str(code)
    return None


def _clean_validation_errors(errors: list[dict[str, Any]]) -> list[dict[str, Any]]:
    # Never echo the rejected input back (it may contain a password or VIN).
    out = []
    for e in errors:
        out.append(
            {
                "loc": [str(p) for p in e.get("loc", ())],
                "msg": str(e.get("msg", "")),
                "type": str(e.get("type", "")),
            }
        )
    return out


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(APIError)
    async def _api_error(_: Request, exc: APIError) -> JSONResponse:
        return error_response(exc.status, exc.code, exc.message, exc.details, exc.headers)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        return error_response(
            422,
            "validation_error",
            "request validation failed",
            {"errors": _clean_validation_errors(list(exc.errors()))},
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = _STATUS_CODES.get(exc.status_code, "error")
        message = exc.detail if isinstance(exc.detail, str) else code
        return error_response(exc.status_code, code, message, headers=getattr(exc, "headers", None))

    @app.exception_handler(DBAPIError)
    async def _db(request: Request, exc: DBAPIError) -> JSONResponse:
        state = _sqlstate(exc) or ""
        if state == "23505":
            return error_response(409, "conflict", "resource already exists")
        if state == "23503":
            return error_response(422, "validation_error", "referenced resource does not exist")
        if state in ("23514", "23502", "22001", "22003", "22007", "22P02", "22023"):
            return error_response(422, "validation_error", "value rejected by a database constraint")
        if state == "42501":
            return error_response(403, "forbidden", "not allowed")
        log.exception("database error", extra={"sqlstate": state})
        await _record_system_error(request, "db_error", str(exc.orig)[:500] if exc.orig else str(exc)[:500])
        return error_response(500, "server_error", "internal server error")

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
        return await unexpected_error_response(request, exc)


async def unexpected_error_response(request: Request, exc: Exception) -> JSONResponse:
    log.error("unhandled error", exc_info=exc)
    await _record_system_error(request, type(exc).__name__, str(exc)[:500])
    return error_response(500, "server_error", "internal server error")


async def _record_system_error(request: Request, code: str, message: str) -> None:
    """Best effort: persist an unexpected error to automind.system_errors."""
    db = getattr(request.app.state, "db", None)
    if db is None:
        return
    try:
        from automind.db import tables as t

        principal = getattr(request.state, "principal", None)
        async with db.system() as conn:
            await conn.execute(
                t.system_errors.insert().values(
                    component="api",
                    error_code=code[:100],
                    message=message,
                    request_id=request_id_var.get(),
                    user_id=getattr(principal, "id", None),
                    context={"path": request.url.path, "method": request.method},
                )
            )
    except Exception:  # noqa: BLE001 - never mask the original error
        log.warning("could not record system error", exc_info=True)
