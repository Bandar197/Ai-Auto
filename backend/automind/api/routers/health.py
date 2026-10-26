from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from automind.api.deps import SvcDep

router = APIRouter(tags=["health"])


@router.get("/health")
async def health(svc: SvcDep) -> dict:
    return {"status": "ok", "version": svc.settings.version}


@router.get("/health/ready")
async def ready(request: Request, svc: SvcDep) -> JSONResponse:
    checks: dict[str, str] = {}
    try:
        await svc.db.ping()
        checks["database"] = "ok"
    except Exception:  # noqa: BLE001
        checks["database"] = "error"
    if svc.settings.redis_url:
        try:
            limiter = request.app.state.rate_limiter
            await limiter._redis.ping()  # noqa: SLF001
            checks["redis"] = "ok"
        except Exception:  # noqa: BLE001
            checks["redis"] = "error"
    ok = all(v == "ok" for v in checks.values())
    body = {"status": "ok" if ok else "degraded", "version": svc.settings.version, "checks": checks}
    if not ok:
        return JSONResponse(
            {"error": {"code": "not_ready", "message": "dependency check failed", "details": body}},
            status_code=503,
        )
    return JSONResponse(body)
