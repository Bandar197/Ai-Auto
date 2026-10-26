"""Diagnosis engine invariants that do not need the simulator."""

import pytest

from automind.diagnosis.engine import diagnose, diagnose_async
from automind.diagnosis.kb import get_kb
from automind.diagnosis.models import DiagnosticInput, InputDTC, Sample, UserMeasurement


def _series(values, step_ms=500):
    return [Sample(t_ms=i * step_ms, value=v) for i, v in enumerate(values)]


def test_kb_loaded_and_never_invents():
    kb = get_kb()
    assert len(kb) > 300 and kb.lookup("P0106")["ar"]
    assert kb.lookup("P1ABC") is None
    r = diagnose(DiagnosticInput(data_mode="live", dtcs=[InputDTC(code="P1ABC")]))
    d = r.dtcs[0]
    assert d.known is False and d.description_en is None
    f = r.findings[0]
    assert f.rule_id == "generic_dtc" and "not in the AutoMind knowledge base" in f.title_en
    assert f.causes == []  # nothing invented


def test_code_only_is_at_most_suspected():
    r = diagnose(DiagnosticInput(data_mode="live", dtcs=[InputDTC(code="P0106")]))
    f = r.findings[0]
    assert f.status in ("suspected", "inconclusive") and f.confidence <= 0.45
    assert any(m.description_en for m in f.missing_data)


def test_overheat_is_critical_and_caps_health():
    n = 60
    inp = DiagnosticInput(data_mode="live", series={
        "engine_rpm": _series([780] * n), "vehicle_speed": _series([0] * n), "coolant_temp": _series([115] * n)})
    r = diagnose(inp)
    assert r.findings[0].severity == "critical" and r.health_score <= 35 and r.health_band == "critical"


def test_ac_requests_measurements_then_uses_them():
    r = diagnose(DiagnosticInput(data_mode="live", dtcs=[InputDTC(code="P0532")]))
    ac = next(f for f in r.findings if f.rule_id == "ac_performance")
    assert len(ac.missing_data) >= 3
    r2 = diagnose(DiagnosticInput(data_mode="live", measurements=[
        UserMeasurement(key="ac_low_side_kpa", value=110, unit="kPa"),
        UserMeasurement(key="ac_high_side_kpa", value=800, unit="kPa"),
        UserMeasurement(key="ac_vent_temp_c", value=20, unit="°C"),
        UserMeasurement(key="ambient_temp_c", value=40, unit="°C")]))
    ac2 = next(f for f in r2.findings if f.rule_id == "ac_performance")
    assert ac2.causes[0].key == "low_charge" and not ac2.missing_data


def test_measured_vs_inferred_separation():
    r = diagnose(DiagnosticInput(data_mode="live", dtcs=[InputDTC(code="P0420")]))
    for f in r.findings:
        for e in f.evidence:
            if e.kind in ("kb_reference", "missing_data"):
                assert e.is_measured is False


class _FakeUsage:
    input_tokens, output_tokens, cache_read_input_tokens = 900, 300, 0


class _FakeParsed:
    owner_explanation_en = "owner en"
    owner_explanation_ar = "شرح"
    technician_note_en = "tech en"
    technician_note_ar = "ملاحظة"


class _FakeResp:
    stop_reason = "end_turn"
    parsed_output = _FakeParsed()
    usage = _FakeUsage()
    model = "claude-opus-5-5"


class _FakeClient:
    def __init__(self):
        self.kwargs = None
        outer = self

        class _M:
            async def parse(self, **kw):
                outer.kwargs = kw
                return _FakeResp()

        class _B:
            messages = _M()

        self.beta = _B()


async def test_llm_narrative_with_fake_client():
    fake = _FakeClient()
    inp = DiagnosticInput(data_mode="demo", dtcs=[InputDTC(code="P0106")])
    r = await diagnose_async(inp, use_llm=True, llm_client=fake)
    assert r.llm and r.llm.narrative_ar.startswith("شرح") and r.llm.input_tokens == 900
    assert fake.kwargs["model"] == "claude-opus-5-5" and fake.kwargs["fallbacks"] == "default"
    assert '"data_mode": "demo"' in fake.kwargs["messages"][0]["content"]


async def test_llm_failure_keeps_rule_result():
    class Boom:
        class beta:  # noqa: N801
            class messages:  # noqa: N801
                @staticmethod
                async def parse(**kw):
                    raise RuntimeError("network")

    r = await diagnose_async(DiagnosticInput(data_mode="live", dtcs=[InputDTC(code="P0106")]), use_llm=True,
                             llm_client=Boom())
    assert r.llm is None and r.findings


@pytest.mark.parametrize("lang", ["ar", "en"])
def test_engine_language_independent(lang):
    r = diagnose(DiagnosticInput(data_mode="live", dtcs=[InputDTC(code="P0171")]), language=lang)
    assert r.summary.ar and r.summary.en
