"""Stateless analysis and the server-side demo (ECU simulator)."""

from __future__ import annotations

import logging
from typing import Any, Literal

from fastapi import APIRouter
from pydantic import BaseModel, Field
from sqlalchemy import select

from automind.api import pipeline
from automind.api.deps import CurrentUser, SvcDep
from automind.api.serializers import session_out
from automind.core.errors import APIError, not_found
from automind.db import tables as t

router = APIRouter(tags=["analysis"])
log = logging.getLogger("automind.demo")


class AnalyzeIn(BaseModel):
    recording: dict[str, Any]
    language: Literal["ar", "en"] = "ar"
    use_llm: bool = False


class DemoRunIn(BaseModel):
    scenario_key: str = Field(min_length=1, max_length=60, pattern=r"^[a-z0-9_]+$")
    duration_s: float = Field(60, ge=30, le=300)
    language: Literal["ar", "en"] = "ar"


@router.post("/diagnosis/analyze")
async def analyze(body: AnalyzeIn, user: CurrentUser, svc: SvcDep) -> dict:
    rec = pipeline.parse_recording(body.recording)
    inp = pipeline.input_from_recording(rec, None)
    result = await pipeline.run_engine(svc, inp, body.language, body.use_llm)
    return result.model_dump(mode="json")


@router.get("/demo/scenarios")
async def demo_scenarios(user: CurrentUser) -> list[dict]:
    from automind.simulator.scenarios import list_scenarios

    keys = ("key", "name_en", "name_ar", "description_en", "description_ar", "dtcs")
    return [{k: s.get(k) for k in keys} for s in list_scenarios()]


@router.post("/demo/run", status_code=201)
async def demo_run(body: DemoRunIn, user: CurrentUser, svc: SvcDep) -> dict:
    from automind.simulator.runner import run_demo
    from automind.simulator.scenarios import list_scenarios

    if body.scenario_key not in {s["key"] for s in list_scenarios()}:
        raise not_found("scenario")
    try:
        rec = await run_demo(body.scenario_key, duration_s=body.duration_s, time_scale=svc.settings.demo_time_scale)
    except Exception as exc:
        log.exception("demo run failed")
        raise APIError(503, "upstream_unavailable", "the ECU simulator could not complete the demo run") from exc
    if rec.data_mode != "demo":  # defensive: simulator data must never be labelled live
        raise APIError(500, "server_error", "simulator produced a non-demo recording")
    async with svc.db.user(user.id) as conn:
        session = await pipeline.insert_session(
            conn,
            user_id=user.id,
            data_mode="demo",
            demo_scenario_key=body.scenario_key,
            protocol_name=rec.source.protocol_name,
            app_platform="server",
            app_version=svc.settings.version,
        )
        await pipeline.store_recording(conn, svc, user.id, rec, session=session)
        await pipeline.ingest_recording_into_session(conn, session, rec)
        inp = pipeline.input_from_recording(rec, "demo")
        diagnosis = await pipeline.diagnose_session(
            conn, svc, session, language=body.language, use_llm=False, complete=True, inp=inp
        )
        session = (
            (await conn.execute(select(t.diagnostic_sessions).where(t.diagnostic_sessions.c.id == session["id"])))
            .mappings()
            .one()
        )
    return {"session": session_out(session), "diagnosis": diagnosis}
