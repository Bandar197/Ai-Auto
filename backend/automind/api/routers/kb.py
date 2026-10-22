"""DTC knowledge base and the shared PID table. Unknown codes → 404 (never invented)."""

from __future__ import annotations

import re
from typing import Any

from fastapi import APIRouter, Query

from automind.api.deps import CurrentUser, Page, page
from automind.core.errors import not_found, validation

router = APIRouter(prefix="/kb", tags=["kb"])

CODE_RE = re.compile(r"^[PCBU][0-9A-F]{4}$")


def _kb_entry(kb, d: dict[str, Any]) -> dict[str, Any]:
    code = d["code"]
    structure = kb.structure(code) if hasattr(kb, "structure") else {}
    return {
        "code": code,
        "system": d.get("system") or structure.get("system"),
        "subsystem": d.get("subsystem"),
        "description_en": d.get("en"),
        "description_ar": d.get("ar"),
        "severity": d.get("severity"),
        "is_generic": d.get("is_generic", structure.get("is_generic")),
        "common_causes": d.get("common_causes") or [],
        "source": getattr(kb, "source", None) or f"AutoMind KB {kb.version}",
        "kb_version": kb.version,
    }


@router.get("/dtc/{code}")
async def dtc_lookup(code: str, user: CurrentUser) -> dict:
    from automind.diagnosis.kb import get_kb

    code = code.strip().upper()
    if not CODE_RE.match(code):
        raise validation("invalid DTC code format", {"field": "code"})
    kb = get_kb()
    d = kb.lookup(code)
    if d is None:
        raise not_found("DTC definition")
    return _kb_entry(kb, d)


@router.get("/dtc")
async def dtc_search(user: CurrentUser, p: Page, q: str = Query("", max_length=100)) -> dict:
    from automind.diagnosis.kb import get_kb

    kb = get_kb()
    hits = kb.search(q, limit=p.offset + p.limit + 1000) if q.strip() else []
    items = [_kb_entry(kb, d) for d in hits[p.offset : p.offset + p.limit]]
    return page(items, len(hits), p)


@router.get("/pids")
async def pid_table(user: CurrentUser) -> dict:
    from automind.obd.pids import load_pid_table

    return load_pid_table()
