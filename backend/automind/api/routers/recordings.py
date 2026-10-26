"""Recordings (v1) and server-side replay."""

from __future__ import annotations

import uuid
from typing import Any, Literal

from fastapi import APIRouter, Body
from pydantic import BaseModel
from sqlalchemy import func, select

from automind.api import pipeline
from automind.api.access import get_recording
from automind.api.deps import CurrentUser, Page, SvcDep, page
from automind.api.serializers import recording_meta_out, session_out
from automind.core.errors import not_found
from automind.db import tables as t

router = APIRouter(prefix="/recordings", tags=["recordings"])


class ReplayIn(BaseModel):
    language: Literal["ar", "en"] = "ar"
    use_llm: bool = False


@router.post("", status_code=201)
async def upload_recording(user: CurrentUser, svc: SvcDep, payload: dict[str, Any] = Body(...)) -> dict:  # noqa: B008
    rec = pipeline.parse_recording(payload)
    async with svc.db.user(user.id) as conn:
        row = await pipeline.store_recording(conn, svc, user.id, rec)
    return recording_meta_out(row)


@router.get("")
async def list_recordings(user: CurrentUser, svc: SvcDep, p: Page) -> dict:
    cond = t.telemetry_recordings.c.user_id == user.id
    async with svc.db.user(user.id) as conn:
        total = (await conn.execute(select(func.count()).select_from(t.telemetry_recordings).where(cond))).scalar_one()
        rows = (
            (
                await conn.execute(
                    select(t.telemetry_recordings)
                    .where(cond)
                    .order_by(t.telemetry_recordings.c.created_at.desc())
                    .limit(p.limit)
                    .offset(p.offset)
                )
            )
            .mappings()
            .all()
        )
    return page([recording_meta_out(r) for r in rows], total, p)


@router.get("/{recording_id}")
async def get_recording_ep(recording_id: uuid.UUID, user: CurrentUser, svc: SvcDep) -> dict:
    async with svc.db.user(user.id) as conn:
        row = await get_recording(conn, recording_id)
    if row["inline_payload"] is None:
        raise not_found("recording payload")
    return row["inline_payload"]


@router.post("/{recording_id}/replay", status_code=201)
async def replay(recording_id: uuid.UUID, user: CurrentUser, svc: SvcDep, body: ReplayIn | None = None) -> dict:
    body = body or ReplayIn()
    async with svc.db.user(user.id) as conn:
        rec_row = await get_recording(conn, recording_id)
        if rec_row["inline_payload"] is None:
            raise not_found("recording payload")
        rec = pipeline.parse_recording(rec_row["inline_payload"])
        vehicle_id = rec_row["vehicle_id"]
        if vehicle_id is not None and not (await conn.execute(select(func.automind.can_write_vehicle(vehicle_id)))).scalar():
            vehicle_id = None  # e.g. a recording shared through an org; replay without the vehicle link
        session = await pipeline.insert_session(
            conn,
            user_id=user.id,
            vehicle_id=vehicle_id,
            data_mode="replay",
            source_recording_id=recording_id,
            protocol_name=rec.source.protocol_name,
        )
        await pipeline.ingest_recording_into_session(conn, session, rec)
        inp = pipeline.input_from_recording(rec, "replay")
        diagnosis = await pipeline.diagnose_session(
            conn, svc, session, language=body.language, use_llm=body.use_llm, complete=True, inp=inp
        )
        session = (
            (await conn.execute(select(t.diagnostic_sessions).where(t.diagnostic_sessions.c.id == session["id"])))
            .mappings()
            .one()
        )
    return {"session": session_out(session), "diagnosis": diagnosis}
