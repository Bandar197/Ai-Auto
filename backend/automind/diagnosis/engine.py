"""Diagnosis engine: rules first, optional LLM narrative on top.

The same `DiagnosticInput` → same `DiagnosisResult` (minus timestamps) in
live, demo and replay modes; only `data_mode` labels differ.
"""

from __future__ import annotations

import hashlib
import json
import logging

from automind.diagnosis.features import Context
from automind.diagnosis.kb import get_kb
from automind.diagnosis.models import (
    Bilingual,
    DataQuality,
    DiagnosisResult,
    DiagnosticInput,
    DTCResult,
    Finding,
    SystemStatus,
)
from automind.diagnosis.rules.powertrain import SPECIALISED_RULES, GenericDtcRule

log = logging.getLogger("automind.diagnosis")

ENGINE_VERSION = "1.0.0"
SEVERITY_PENALTY = {"info": 0, "low": 10, "medium": 20, "high": 32, "critical": 60}
SEVERITY_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}

# signals that indicate each system was actually observed
SYSTEM_SIGNALS = {
    "engine": ["engine_rpm", "engine_load"],
    "fuel": ["stft_b1", "ltft_b1"],
    "air_intake": ["map_kpa", "maf_gs", "throttle_pos"],
    "ignition": ["engine_rpm", "timing_advance"],
    "cooling": ["coolant_temp"],
    "charging": ["module_voltage"],
    "emissions": ["o2_b1s1_voltage"],
    "transmission": [],
    "ac": [],
}
SYSTEM_NAMES = {
    "engine": ("Engine", "المحرك"), "fuel": ("Fuel system", "نظام الوقود"), "air_intake": ("Air intake", "نظام السحب"),
    "ignition": ("Ignition", "الإشعال"), "cooling": ("Cooling", "التبريد"), "charging": ("Battery & charging", "البطارية والشحن"),
    "emissions": ("Emissions", "الانبعاثات"), "transmission": ("Transmission", "ناقل الحركة"), "ac": ("Air conditioning", "التكييف"),
    "electrical": ("Electrical", "الكهرباء"), "network": ("Vehicle network", "شبكة السيارة"), "other": ("Other", "أخرى"),
}

DISCLAIMERS = [
    Bilingual(
        en="This is a decision-support analysis based on the data the vehicle reported. It is not a confirmed diagnosis: "
           "perform the recommended tests before replacing parts.",
        ar="هذا تحليل مساند لاتخاذ القرار مبني على البيانات التي أبلغت عنها السيارة، وليس تشخيصا مؤكدا: "
           "نفّذ الاختبارات المقترحة قبل استبدال أي قطعة.",
    ),
    Bilingual(
        en="Reference ranges are generic values for typical gasoline engines, not the manufacturer's specifications for this vehicle.",
        ar="النطاقات المرجعية قيم عامة للمحركات البنزين المعتادة وليست مواصفات الشركة المصنعة لهذه السيارة.",
    ),
]


def _input_hash(inp: DiagnosticInput) -> str:
    payload = inp.model_dump(mode="json", exclude={"data_mode"})
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def _dtc_results(inp: DiagnosticInput) -> list[DTCResult]:
    kb = get_kb()
    out = []
    seen = set()
    for d in inp.dtcs:
        if (d.code, d.status) in seen:
            continue
        seen.add((d.code, d.status))
        k = kb.lookup(d.code)
        st = kb.structure(d.code)
        out.append(DTCResult(
            code=d.code, status=d.status, ecu=d.ecu,
            description_en=k["en"] if k else None, description_ar=k["ar"] if k else None,
            system=(k or {}).get("system", st["system"]),
            severity=(k or {}).get("severity", "medium"), known=bool(k),
        ))
    return out


def run_rules(inp: DiagnosticInput) -> tuple[list[Finding], Context]:
    ctx = Context(inp)
    findings: list[Finding] = []
    covered: set[str] = set()
    n = 0
    for rule in SPECIALISED_RULES:
        try:
            f = rule.run(ctx, f"f{n + 1}")
        except Exception:  # a broken rule must never hide the others
            log.exception("rule %s failed", rule.id)
            continue
        if f:
            n += 1
            findings.append(f)
            covered |= set(f.related_dtcs)
    generic = GenericDtcRule()
    # stored/permanent codes first, then pending ones not already covered
    for d in sorted({d.code for d in inp.dtcs}):
        if d in covered:
            continue
        n += 1
        findings.append(generic.run_for(ctx, f"f{n}", d))
        covered.add(d)
    findings.sort(key=lambda f: (SEVERITY_ORDER[f.severity], -f.confidence))
    return findings, ctx


def _health(findings: list[Finding], inp: DiagnosticInput) -> tuple[int, str]:
    score = 100.0
    for f in findings:
        weight = max(f.confidence, 0.35)
        score -= SEVERITY_PENALTY[f.severity] * weight
    pending_only = {d.code for d in inp.dtcs if d.status == "pending"} - {d.code for d in inp.dtcs if d.status == "stored"}
    score -= 2 * len(pending_only)
    # Caps so the band always reflects the worst problem, whatever the arithmetic says.
    if any(d.status in ("stored", "permanent") for d in inp.dtcs):
        score = min(score, 84)  # a confirmed code is never "good"
    if any(f.severity == "high" for f in findings):
        score = min(score, 65)
    if any(f.severity == "critical" for f in findings):
        score = min(score, 35)
    score = int(round(max(0, min(100, score))))
    band = "good" if score >= 85 else "fair" if score >= 70 else "attention" if score >= 45 else "critical"
    return score, band


def _system_status(findings: list[Finding], ctx: Context) -> list[SystemStatus]:
    out = []
    for sys, sigs in SYSTEM_SIGNALS.items():
        fs = [f for f in findings if f.system == sys]
        en_name, ar_name = SYSTEM_NAMES[sys]
        if fs:
            worst = min(fs, key=lambda f: SEVERITY_ORDER[f.severity])
            status = "fault" if SEVERITY_ORDER[worst.severity] <= 2 and worst.confidence >= 0.45 else "warning"
            out.append(SystemStatus(system=sys, status=status,  # type: ignore[arg-type]
                                    note_en=f"{en_name}: {worst.title_en}", note_ar=f"{ar_name}: {worst.title_ar}"))
        elif sigs and any(ctx.has(s, 5) for s in sigs):
            out.append(SystemStatus(system=sys, status="ok",  # type: ignore[arg-type]
                                    note_en=f"{en_name}: no issue detected in the available data",
                                    note_ar=f"{ar_name}: لم تُكتشف مشكلة في البيانات المتاحة"))
        else:
            out.append(SystemStatus(system=sys, status="unknown",  # type: ignore[arg-type]
                                    note_en=f"{en_name}: not enough data from this vehicle to assess",
                                    note_ar=f"{ar_name}: لا توجد بيانات كافية من هذه السيارة للتقييم"))
    for f in findings:
        if f.system not in SYSTEM_SIGNALS and f.system not in {s.system for s in out}:
            en_name, ar_name = SYSTEM_NAMES.get(f.system, (f.system, f.system))
            out.append(SystemStatus(system=f.system, status="warning",
                                    note_en=f"{en_name}: {f.title_en}", note_ar=f"{ar_name}: {f.title_ar}"))
    return out


def _data_quality(ctx: Context, inp: DiagnosticInput) -> DataQuality:
    signals = sorted(k for k, v in inp.series.items() if v)
    n = sum(len(v) for v in inp.series.values())
    dur = inp.duration_ms / 1000 if inp.duration_ms else 0.0
    warnings = []
    if not inp.series:
        warnings.append(Bilingual(en="No live data was captured — only trouble codes could be analysed.",
                                  ar="لم تُسجل بيانات حية، لذلك تم تحليل أكواد الأعطال فقط."))
    elif dur and dur < 30:
        warnings.append(Bilingual(en=f"Short capture ({dur:.0f} s). 60–120 s including idle and 2500 rpm gives better results.",
                                  ar=f"مدة التسجيل قصيرة ({dur:.0f} ثانية). التسجيل 60–120 ثانية مع خمول و2500 دورة يعطي نتائج أفضل."))
    conds = ctx.conditions_seen()
    if inp.series and "warm_idle" not in conds:
        warnings.append(Bilingual(en="No warm-idle period recorded; several checks need one.",
                                  ar="لم تُسجل فترة خمول والمحرك دافئ، وبعض الفحوص تحتاجها."))
    if inp.data_mode == "demo":
        warnings.append(Bilingual(en="DEMO data from the AutoMind simulator — not a real vehicle.",
                                  ar="بيانات تجريبية من محاكي أوتومايند — ليست سيارة حقيقية."))
    return DataQuality(signals=signals, sample_count=n, duration_s=round(dur, 1), conditions_seen=conds, warnings=warnings)


def _summaries(findings: list[Finding], dtcs: list[DTCResult], score: int, band: str,
               inp: DiagnosticInput) -> tuple[Bilingual, Bilingual]:
    mode_en = {"live": "", "demo": "[DEMO] ", "replay": "[REPLAY] "}[inp.data_mode]
    mode_ar = {"live": "", "demo": "[تجريبي] ", "replay": "[إعادة تشغيل] "}[inp.data_mode]
    band_en = {"good": "good", "fair": "fair", "attention": "needs attention", "critical": "critical"}[band]
    band_ar = {"good": "جيدة", "fair": "مقبولة", "attention": "تحتاج انتباها", "critical": "حرجة"}[band]
    if not findings:
        own = Bilingual(
            en=f"{mode_en}Vehicle health {score}/100 ({band_en}). No trouble codes and no abnormal readings in the data captured.",
            ar=f"{mode_ar}صحة السيارة {score}/100 ({band_ar}). لا توجد أكواد أعطال ولا قراءات غير طبيعية في البيانات المسجلة.",
        )
        tech = Bilingual(en=f"{mode_en}No DTCs (03/07/0A). All evaluated parameters within generic ranges.",
                         ar=f"{mode_ar}لا توجد أكواد (03/07/0A). جميع المعاملات المقيمة ضمن النطاقات العامة.")
        return own, tech
    top = findings[0]
    crit = [f for f in findings if f.severity == "critical"]
    lead_en = "Stop driving and have the vehicle checked. " if crit else ""
    lead_ar = "أوقف القيادة وافحص السيارة. " if crit else ""
    own = Bilingual(
        en=f"{mode_en}Vehicle health {score}/100 ({band_en}). {lead_en}{len(findings)} issue(s) found; the most important: "
           f"{top.title_en}. Recommended next step: {top.tests[0].title_en if top.tests else 'professional inspection'}.",
        ar=f"{mode_ar}صحة السيارة {score}/100 ({band_ar}). {lead_ar}تم العثور على {len(findings)} مشكلة؛ الأهم: "
           f"{top.title_ar}. الخطوة التالية المقترحة: {top.tests[0].title_ar if top.tests else 'فحص لدى مختص'}.",
    )
    codes = ", ".join(f"{d.code}({d.status[0].upper()})" for d in dtcs) or "none"
    parts_en, parts_ar = [], []
    for f in findings[:5]:
        c = f.causes[0] if f.causes else None
        parts_en.append(f"[{f.severity}/{f.status} {f.confidence:.2f}] {f.title_en}" + (f" → top cause: {c.title_en} ({c.likelihood:.0%})" if c else ""))
        parts_ar.append(f"[{f.severity}/{f.status} {f.confidence:.2f}] {f.title_ar}" + (f" ← السبب الأرجح: {c.title_ar} ({c.likelihood:.0%})" if c else ""))
    tech = Bilingual(en=f"{mode_en}DTCs: {codes}. " + " | ".join(parts_en),
                     ar=f"{mode_ar}الأكواد: {codes}. " + " | ".join(parts_ar))
    return own, tech


def diagnose(inp: DiagnosticInput, language: str = "ar") -> DiagnosisResult:  # noqa: ARG001 - both languages always returned
    findings, ctx = run_rules(inp)
    dtcs = _dtc_results(inp)
    score, band = _health(findings, inp)
    own, tech = _summaries(findings, dtcs, score, band, inp)
    return DiagnosisResult(
        engine_version=ENGINE_VERSION, kb_version=get_kb().version, data_mode=inp.data_mode,
        health_score=score, health_band=band, summary=own, technician_summary=tech,  # type: ignore[arg-type]
        dtcs=dtcs, findings=findings, system_status=_system_status(findings, ctx),
        data_quality=_data_quality(ctx, inp), disclaimers=DISCLAIMERS, input_sha256=_input_hash(inp),
    )


async def diagnose_async(inp: DiagnosticInput, language: str = "ar", use_llm: bool = False,
                         llm_client: object | None = None) -> DiagnosisResult:
    result = diagnose(inp, language)
    if use_llm:
        from automind.diagnosis.llm import add_narrative

        try:
            result = await add_narrative(result, inp, client=llm_client)
        except Exception:  # LLM is optional; never lose the rule-based result
            log.exception("LLM narrative failed; returning rule-based result")
    return result
