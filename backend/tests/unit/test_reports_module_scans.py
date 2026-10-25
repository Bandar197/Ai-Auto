"""Honest module-scan outcomes flow into the diagnosis result and the reports,
and PDF rendering produces a real PDF (or reports it's unavailable)."""

import json
from pathlib import Path

import pytest

from automind.diagnosis.engine import diagnose
from automind.diagnosis.input_builder import from_recording
from automind.diagnosis.models import DiagnosticInput, InputDTC, InputModuleScan
from automind.recording.format import RecDTC, RecModuleScan, Recording, RecSource
from automind.reports import (
    ReportMeta,
    ReportRendererUnavailable,
    render_report_html,
    render_report_json,
    render_report_pdf,
)

SCHEMA_DIR = Path(__file__).resolve().parents[3] / "shared" / "schemas"


def _result_with_modules():
    inp = DiagnosticInput(
        data_mode="live",
        module_scans=[
            InputModuleScan(key="srs", name_en="Airbag (SRS)", name_ar="الإيرباق", category="airbag",
                            address="7D0", outcome="no_response"),
            InputModuleScan(key="abs", name_en="ABS", name_ar="نظام ABS", category="abs",
                            address="7D1", outcome="read_no_codes"),
            InputModuleScan(key="bcm", name_en="Body control", name_ar="وحدة الهيكل", category="body",
                            address="7D2", outcome="refused"),
            InputModuleScan(key="eng2", name_en="Engine", name_ar="المحرك", category="engine",
                            address="7E0", outcome="read_codes",
                            codes=[InputDTC(code="P0106"), InputDTC(code="B1ABC")]),
        ],
    )
    return diagnose(inp)


def test_engine_passes_module_outcomes_through_honestly():
    by = {m.key: m for m in _result_with_modules().module_scans}
    assert by["srs"].outcome == "no_response" and by["srs"].read_ok is False
    assert by["abs"].outcome == "read_no_codes" and by["abs"].read_ok is True
    assert by["bcm"].outcome == "refused" and by["bcm"].read_ok is False
    eng = by["eng2"]
    assert eng.outcome == "read_codes" and eng.read_ok is True
    codes = {c.code: c for c in eng.codes}
    assert codes["P0106"].known is True and codes["P0106"].description_ar  # enriched from KB
    assert codes["B1ABC"].known is False and codes["B1ABC"].description_en is None  # nothing invented


def test_non_read_modules_never_carry_codes():
    # A module that did not answer cannot honestly report codes.
    inp = DiagnosticInput(data_mode="live", module_scans=[
        InputModuleScan(key="srs", name_en="SRS", name_ar="SRS", category="airbag",
                        outcome="no_response", codes=[InputDTC(code="B0051")]),
    ])
    assert diagnose(inp).module_scans[0].codes == []


def test_json_report_carries_module_scans():
    doc = render_report_json(_result_with_modules(), ReportMeta(data_mode="live"))
    ms = doc["diagnosis"]["module_scans"]
    assert {m["key"]: m["read_ok"] for m in ms} == {"srs": False, "abs": True, "bcm": False, "eng2": True}


@pytest.mark.parametrize("lang", ["ar", "en"])
def test_html_report_is_honest_about_modules(lang):
    html = render_report_html(_result_with_modules(), ReportMeta(data_mode="live"), lang)
    assert "P0106" in html  # engine read_codes shows the code
    if lang == "en":
        assert "could not verify" in html            # airbag no_response, never "no faults"
        assert "specialist" in html                  # airbag → specialist message
        assert "no stored codes" in html.lower()     # abs read_no_codes (the only honest "no faults")
        assert "refused the read" in html            # body refused
    else:
        assert "تعذّر التحقق" in html
        assert "متخصص" in html


def test_recording_carries_module_scans_through_to_the_report():
    rec = Recording(
        data_mode="live",
        source=RecSource(kind="elm327_wifi"),
        module_scans=[
            RecModuleScan(key="srs", name_en="Airbag (SRS)", name_ar="الإيرباق",
                          category="airbag", address="7D0", outcome="no_response"),
            RecModuleScan(key="eng2", name_en="Engine", name_ar="المحرك", category="engine",
                          address="7E0", outcome="read_codes", codes=[RecDTC(code="P0106", status="stored")]),
        ],
    )
    # Round-trips through JSON (as uploaded) and keeps the outcomes.
    rec = Recording.from_obj(rec.to_json())
    r = diagnose(from_recording(rec))
    by = {m.key: m for m in r.module_scans}
    assert by["srs"].outcome == "no_response" and by["srs"].read_ok is False
    assert by["eng2"].outcome == "read_codes" and any(c.code == "P0106" for c in by["eng2"].codes)
    html = render_report_html(r, ReportMeta(data_mode="live"), "ar")
    assert "تعذّر التحقق" in html and "P0106" in html


def test_recording_schema_accepts_module_scans():
    jsonschema = pytest.importorskip("jsonschema")
    schema = json.loads((SCHEMA_DIR / "recording.v1.schema.json").read_text(encoding="utf-8"))
    rec = Recording(
        data_mode="live", source=RecSource(kind="elm327_wifi"),
        module_scans=[RecModuleScan(key="abs", name_en="ABS", name_ar="ABS", category="abs",
                                    address="7D1", outcome="read_no_codes")],
    )
    jsonschema.validate(json.loads(rec.to_json()), schema)


def test_session_summary_carries_module_scans_into_the_live_input():
    from automind.api.pipeline import session_module_scans

    session = {"summary": {"module_scans": [
        {"key": "srs", "name_en": "SRS", "name_ar": "SRS", "category": "airbag",
         "address": "7D0", "outcome": "no_response", "codes": []},
        {"key": "broken", "outcome": "nonsense"},  # malformed → skipped, never crashes the diagnosis
    ]}}
    out = session_module_scans(session)
    assert len(out) == 1 and out[0].key == "srs" and out[0].outcome == "no_response"
    assert session_module_scans({"summary": None}) == []


def test_pdf_report_renders_a_real_pdf_or_reports_unavailable():
    r = _result_with_modules()
    try:
        pdf = render_report_pdf(r, ReportMeta(data_mode="live"), "ar")
    except ReportRendererUnavailable:
        pytest.skip("WeasyPrint (optional [pdf] extra) not installed in this environment")
    assert pdf[:5] == b"%PDF-" and len(pdf) > 1000
