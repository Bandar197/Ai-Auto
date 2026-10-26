"""Optional LLM narrative on top of the rule-based diagnosis.

The model receives ONLY the structured result (findings, evidence, causes,
tests) and writes a plain-language explanation in Arabic and English. It is
instructed not to add facts, values or causes that are not in the input and it
cannot change rankings, confidence or the health score — those come from the
rule engine. If the API is not configured or fails, the rule result stands.
"""

from __future__ import annotations

import json
import os
import time
from typing import Any

from pydantic import BaseModel, Field

from automind.diagnosis.models import DiagnosisResult, DiagnosticInput, LLMNarrative

PROMPT_VERSION = "narrative-2026-10-1"
DEFAULT_MODEL = "claude-opus-5-5"
# USD per million tokens (input, output) — used only for the usage dashboard.
PRICING = {"claude-opus-5-5": (4.0, 20.0), "claude-sonnet-5-5": (2.0, 10.0), "claude-haiku-5-5": (0.10, 0.50)}

SYSTEM_PROMPT = """You are the explanation layer of AutoMind AI, a vehicle diagnostics platform used in Saudi Arabia.
You receive the structured output of a rule-based diagnosis engine (findings, measured evidence, ranked
probable causes, recommended tests, data-quality notes) and you write a clear explanation for the car owner
and a short technical note for the technician, in Arabic and in English.

Rules — follow all of them:
1. Use only facts present in the input JSON. Never invent sensor values, specifications, part numbers,
   prices, vehicle details or causes that are not listed. If something is unknown, say it is unknown.
2. Do not change the ranking, likelihood, confidence, severity or health score. Report them as given.
3. Keep measured data and inference clearly separate: say "the car reported / we measured" for evidence
   with is_measured=true, and "this suggests / possible" for causes and inferences.
4. Never present a probable cause as confirmed. Tell the reader which test confirms it before any part
   is replaced. Parts listed under parts_candidates always require confirmation first.
5. If data_mode is "demo", state clearly that this is simulated demo data, not a real vehicle. If it is
   "replay", say it is a re-analysis of a previously recorded session.
6. For any finding with severity "critical", start with a clear safety instruction (stop driving).
7. Arabic: natural Modern Standard Arabic as used by Gulf mechanics; keep acronyms such as MAP, MAF, O2,
   EGR and DTC codes in Latin letters. English: plain, no jargon for the owner part.
8. Be concise: owner explanation at most ~150 words per language; technician note at most ~120 words."""


class _Narrative(BaseModel):
    owner_explanation_en: str = Field(description="Plain-language explanation for the car owner (English)")
    owner_explanation_ar: str = Field(description="Plain-language explanation for the car owner (Arabic)")
    technician_note_en: str = Field(description="Concise technical note for the technician (English)")
    technician_note_ar: str = Field(description="Concise technical note for the technician (Arabic)")


def _llm_input(result: DiagnosisResult, inp: DiagnosticInput) -> dict[str, Any]:
    """Compact, deterministic payload (sorted keys) — no raw time series."""
    return {
        "data_mode": result.data_mode,
        "vehicle": inp.vehicle.model_dump(exclude_none=True),
        "health_score": result.health_score,
        "health_band": result.health_band,
        "dtcs": [d.model_dump(exclude_none=True) for d in result.dtcs],
        "findings": [
            {
                "title_en": f.title_en, "title_ar": f.title_ar, "system": f.system, "severity": f.severity,
                "status": f.status, "confidence": f.confidence, "related_dtcs": f.related_dtcs,
                "causes": [{"en": c.title_en, "ar": c.title_ar, "likelihood": c.likelihood, "rank": c.rank}
                           for c in f.causes],
                "evidence": [e.model_dump(exclude_none=True, exclude={"id"}) for e in f.evidence],
                "tests": [{"en": t.title_en, "ar": t.title_ar, "expected_en": t.expected_en} for t in f.tests],
                "parts_candidates": [p.model_dump() for p in f.parts_candidates],
                "missing_data": [m.model_dump(exclude_none=True) for m in f.missing_data],
            }
            for f in result.findings
        ],
        "data_quality": result.data_quality.model_dump(),
    }


def _make_client() -> Any:
    import anthropic

    key = os.environ.get("AUTOMIND_ANTHROPIC_API_KEY") or os.environ.get("ANTHROPIC_API_KEY")
    return anthropic.AsyncAnthropic(api_key=key) if key else anthropic.AsyncAnthropic()


async def add_narrative(
    result: DiagnosisResult, inp: DiagnosticInput, *, client: Any | None = None, model: str | None = None,
) -> DiagnosisResult:
    model = model or os.environ.get("AUTOMIND_LLM_MODEL", DEFAULT_MODEL)
    client = client or _make_client()
    payload = json.dumps(_llm_input(result, inp), ensure_ascii=False, sort_keys=True)
    t0 = time.monotonic()
    response = await client.beta.messages.parse(
        model=model,
        max_tokens=4000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",  # on a safety decline the API re-runs on Anthropic's recommended fallback model
        output_config={"effort": "low"},  # rephrasing structured facts; no deep reasoning needed
        system=[{"type": "text", "text": SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}],
        messages=[{"role": "user", "content": f"Diagnosis result JSON:\n{payload}"}],
        output_format=_Narrative,
    )
    if response.stop_reason == "refusal":
        raise RuntimeError("LLM declined the request")
    parsed: _Narrative | None = response.parsed_output
    if parsed is None:
        raise RuntimeError(f"LLM returned no structured output (stop_reason={response.stop_reason})")
    usage = response.usage
    in_tok = int(getattr(usage, "input_tokens", 0) or 0) + int(getattr(usage, "cache_read_input_tokens", 0) or 0)
    out_tok = int(getattr(usage, "output_tokens", 0) or 0)
    served = getattr(response, "model", model) or model
    result.llm = LLMNarrative(
        model=served, prompt_version=PROMPT_VERSION,
        narrative_en=f"{parsed.owner_explanation_en}\n\nTechnician: {parsed.technician_note_en}",
        narrative_ar=f"{parsed.owner_explanation_ar}\n\nللفني: {parsed.technician_note_ar}",
        input_tokens=in_tok, output_tokens=out_tok, latency_ms=int((time.monotonic() - t0) * 1000),
    )
    return result


def estimate_cost_usd(model: str, input_tokens: int, output_tokens: int) -> float:
    pin, pout = PRICING.get(model, PRICING[DEFAULT_MODEL])
    return round(input_tokens / 1e6 * pin + output_tokens / 1e6 * pout, 6)
