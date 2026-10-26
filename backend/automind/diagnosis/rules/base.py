"""Rule framework: evidence → ranked causes → confidence.

Principles enforced here:
  * Observed data (is_measured=True) is kept apart from inferences/references.
  * Confidence is capped at 0.9 — only a confirmation test performed by a
    technician can turn a finding into 'confirmed'.
  * A DTC alone never yields more than 'suspected'.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

from automind.diagnosis.models import (
    Action,
    Cause,
    Evidence,
    Finding,
    MissingData,
    PartCandidate,
    Severity,
    System,
    TestStep,
)

if TYPE_CHECKING:
    from automind.diagnosis.features import Context, Stats

MAX_CONFIDENCE_WITHOUT_TEST = 0.9


class FindingBuilder:
    def __init__(
        self, fid: str, rule: Rule, *, title_en: str, title_ar: str, system: System, severity: Severity,
        related_dtcs: list[str] | None = None,
    ):
        self.fid = fid
        self.rule = rule
        self.title_en, self.title_ar = title_en, title_ar
        self.system = system
        self.severity: Severity = severity
        self.related_dtcs = sorted(set(related_dtcs or []))
        self.evidence: list[Evidence] = []
        self._causes: list[tuple[str, str, str, float, list[str], list[str]]] = []
        self.tests: list[TestStep] = []
        self.actions: list[Action] = []
        self.parts: list[PartCandidate] = []
        self.missing: list[MissingData] = []

    # ---------------------------------------------------------------- evidence
    def ev(
        self, kind: str, *, measured: bool, assessment: str, weight: float = 0.5, signal: str | None = None,
        value: float | None = None, unit: str | None = None, lo: float | None = None, hi: float | None = None,
        context: str | None = None, en: str | None = None, ar: str | None = None, text: str | None = None,
    ) -> str:
        eid = f"{self.fid}-e{len(self.evidence) + 1}"
        self.evidence.append(Evidence(
            id=eid, kind=kind, is_measured=measured, signal=signal,  # type: ignore[arg-type]
            observed_value=None if value is None else round(value, 3), observed_text=text, unit=unit,
            expected_min=lo, expected_max=hi, expected_context=context, assessment=assessment,  # type: ignore[arg-type]
            weight=weight, note_en=en, note_ar=ar,
        ))
        return eid

    def ev_dtc(self, code: str, status: str, desc_en: str | None, desc_ar: str | None) -> str:
        return self.ev(
            "dtc", measured=True, assessment="supports", weight=0.6, text=f"{code} ({status})",
            en=f"ECU reported {code} ({status})" + (f": {desc_en}" if desc_en else ""),
            ar=f"وحدة التحكم سجلت الكود {code} ({_status_ar(status)})" + (f": {desc_ar}" if desc_ar else ""),
        )

    def ev_stat(
        self, signal: str, st: Stats, *, lo: float | None, hi: float | None, unit: str, context: str,
        use: str = "mean", weight: float = 0.6, en: str = "", ar: str = "",
    ) -> tuple[str, bool]:
        val = getattr(st, use)
        abnormal = (lo is not None and val < lo) or (hi is not None and val > hi)
        eid = self.ev(
            "pid_statistic", measured=True, assessment="abnormal" if abnormal else "normal", weight=weight,
            signal=signal, value=val, unit=unit, lo=lo, hi=hi, context=context,
            en=en or f"{signal} {use} = {val:.2f} {unit} over {st.n} samples ({context})",
            ar=ar or f"{signal} ({_use_ar(use)}) = {val:.2f} {unit} من {st.n} قراءة ({context})",
        )
        return eid, abnormal

    def ev_missing(self, signal: str | None, en: str, ar: str) -> str:
        self.missing.append(MissingData(signal=signal, description_en=en, description_ar=ar))
        return self.ev("missing_data", measured=False, assessment="inconclusive", weight=0.2, signal=signal,
                       en=en, ar=ar)

    def ev_kb(self, en: str, ar: str) -> str:
        return self.ev("kb_reference", measured=False, assessment="inconclusive", weight=0.2, en=en, ar=ar)

    # ---------------------------------------------------------------- outputs
    def cause(self, key: str, en: str, ar: str, prior: float, support: list[str] | None = None,
              contradict: list[str] | None = None) -> None:
        self._causes.append((key, en, ar, prior, support or [], contradict or []))

    def test(self, key: str, en: str, ar: str, how_en: str, how_ar: str, exp_en: str | None = None,
             exp_ar: str | None = None, tools: list[str] | None = None) -> None:
        self.tests.append(TestStep(key=key, title_en=en, title_ar=ar, how_en=how_en, how_ar=how_ar,
                                   expected_en=exp_en, expected_ar=exp_ar, tools=tools or []))

    def action(self, en: str, ar: str, after_test: str | None = None) -> None:
        self.actions.append(Action(title_en=en, title_ar=ar, after_test=after_test))

    def part(self, en: str, ar: str, category: str, cond_en: str, cond_ar: str) -> None:
        self.parts.append(PartCandidate(name_en=en, name_ar=ar, category=category, requires_confirmation=True,
                                        condition_en=cond_en, condition_ar=cond_ar))

    # ---------------------------------------------------------------- build
    def _weight(self, eid: str) -> tuple[float, str]:
        for e in self.evidence:
            if e.id == eid:
                return e.weight, e.assessment
        return 0.0, "inconclusive"

    def build(self, base_confidence: float) -> Finding:
        scored: list[tuple[float, Cause]] = []
        for key, en, ar, prior, sup, con in self._causes:
            score = prior
            for eid in sup:
                w, a = self._weight(eid)
                if a in ("abnormal", "supports"):
                    score *= 1 + 1.5 * w
            for eid in con:
                w, a = self._weight(eid)
                if a in ("abnormal", "supports", "contradicts"):
                    score *= max(0.05, 1 - 0.8 * w)
            scored.append((score, Cause(key=key, title_en=en, title_ar=ar, likelihood=0.0,
                                        supporting_evidence=sup, contradicting_evidence=con)))
        total = sum(s for s, _ in scored) or 1.0
        scored.sort(key=lambda x: -x[0])
        causes = []
        for rank, (s, c) in enumerate(scored, 1):
            c.likelihood = round(min(0.95, s / total), 3)
            c.rank = rank
            causes.append(c)

        measured_abn = [e for e in self.evidence if e.is_measured and e.kind != "dtc" and e.assessment == "abnormal"]
        measured_norm = [e for e in self.evidence if e.is_measured and e.kind != "dtc" and e.assessment == "normal"]
        conf = base_confidence + sum(0.12 * e.weight for e in measured_abn) - sum(0.04 * e.weight for e in measured_norm)
        conf -= 0.05 * len(self.missing)
        if not measured_abn:
            conf = min(conf, 0.45)  # code (or nothing) without corroborating data
        conf = round(max(0.05, min(MAX_CONFIDENCE_WITHOUT_TEST, conf)), 3)
        status = "likely" if conf >= 0.6 else "suspected" if conf >= 0.3 else "inconclusive"
        return Finding(
            id=self.fid, rule_id=self.rule.id, rule_version=self.rule.version, system=self.system,
            title_en=self.title_en, title_ar=self.title_ar, severity=self.severity, status=status,  # type: ignore[arg-type]
            confidence=conf, related_dtcs=self.related_dtcs, causes=causes, evidence=self.evidence,
            tests=self.tests, actions=self.actions, parts_candidates=self.parts, missing_data=self.missing,
        )


class Rule(ABC):
    id: str
    version: str = "1.0.0"
    #: DTC codes (exact) or prefixes ending with '*' that trigger this rule
    dtc_triggers: tuple[str, ...] = ()

    def matching_dtcs(self, ctx: Context) -> list[str]:
        out = []
        for code in ctx.dtc_codes():
            for trig in self.dtc_triggers:
                if (trig.endswith("*") and code.startswith(trig[:-1])) or code == trig:
                    out.append(code)
                    break
        return sorted(out)

    @abstractmethod
    def run(self, ctx: Context, fid: str) -> Finding | None: ...


def _status_ar(s: str) -> str:
    return {"stored": "مخزن", "pending": "معلق", "permanent": "دائم"}.get(s, s)


def _use_ar(u: str) -> str:
    return {"mean": "المتوسط", "max": "الأعلى", "min": "الأدنى", "std": "الانحراف المعياري", "p95": "المئين 95",
            "p05": "المئين 5", "p50": "الوسيط"}.get(u, u)
