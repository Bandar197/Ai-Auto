"""End-to-end: simulator over real TCP → OBD client → recording → diagnosis → reports.

Covers the platform test plan:
  2. ECU simulator on a local TCP port with fault scenarios (P0106 …)
  3. 60–120 s session recorded to JSON and replayed
  4. same analysis in live/demo/replay modes
  5. HTML + JSON reports
  6. network failure handling (drop, unreachable, ignition off)
"""

import asyncio
import json

import jsonschema
import pytest

from automind.diagnosis.engine import diagnose
from automind.diagnosis.input_builder import from_recording
from automind.obd.client import ObdClient
from automind.obd.transport.tcp import TcpTransport
from automind.recording.format import Recording
from automind.recording.recorder import ReplaySource, capture_session
from automind.reports import ReportMeta, render_report_html, render_report_json
from automind.shared_paths import shared_dir
from automind.simulator.runner import run_demo
from automind.simulator.server import SimulatorConfig, SimulatorServer

EXPECTED = {
    "healthy": None,
    "p0106_map_sensor": ("map_sensor_plausibility", "map_sensor_fault"),
    "p0171_vacuum_leak": ("fuel_trim_balance", "vacuum_leak"),
    "p0128_thermostat": ("coolant_warmup", "thermostat_stuck_open"),
    "charging_low": ("charging_system", "alternator"),
    "p0302_misfire": ("misfire", None),
}


@pytest.fixture(scope="module")
def recordings():
    async def build():
        return {key: await run_demo(key, duration_s=110, time_scale=20) for key in EXPECTED}

    return asyncio.run(build())


async def test_recording_duration_and_schema(recordings):
    schema = json.loads((shared_dir() / "schemas" / "recording.v1.schema.json").read_text())
    for key, rec in recordings.items():
        assert rec.data_mode == "demo" and rec.source.kind == "simulator" and rec.source.demo_scenario == key
        assert 100_000 <= rec.duration_ms <= 125_000, key  # 60–120 s window (simulated time)
        assert len(rec.samples) > 200
        jsonschema.validate(json.loads(rec.to_json()), schema)


@pytest.mark.parametrize("key", list(EXPECTED))
async def test_scenario_diagnosis(recordings, key):
    r = diagnose(from_recording(recordings[key]))
    exp = EXPECTED[key]
    if exp is None:
        assert r.findings == [] and r.health_band == "good"
        return
    rule, cause = exp
    top = next(f for f in r.findings if f.rule_id == rule)
    assert top.status in ("suspected", "likely") and top.confidence <= 0.9  # never "confirmed" without a test
    if cause:
        assert top.causes[0].key == cause
    assert any(e.is_measured and e.assessment == "abnormal" for e in top.evidence), "needs data, not only the code"
    assert all(p.requires_confirmation for p in top.parts_candidates)
    assert r.health_score < 85


async def test_save_load_replay_identical(recordings, tmp_path):
    rec = recordings["p0106_map_sensor"]
    p = rec.save(tmp_path / "s.json")
    back = Recording.load(p)
    assert back.model_dump() == rec.model_dump()
    replayed = [s async for s in ReplaySource(back, speed=0)]
    assert [s.values for s in replayed] == [s.values for s in rec.samples]


async def test_same_result_across_modes(recordings):
    rec = recordings["p0171_vacuum_leak"]
    as_demo = diagnose(from_recording(rec))
    as_replay = diagnose(from_recording(rec, data_mode="replay"))
    as_live = diagnose(from_recording(rec, data_mode="live"))  # same data presented as if live
    strip = lambda r: [(f.rule_id, f.confidence, [c.key for c in f.causes]) for f in r.findings]  # noqa: E731
    assert strip(as_demo) == strip(as_replay) == strip(as_live)
    assert as_demo.input_sha256 == as_replay.input_sha256 == as_live.input_sha256
    assert {as_demo.data_mode, as_replay.data_mode, as_live.data_mode} == {"demo", "replay", "live"}
    assert as_demo.summary.en.startswith("[DEMO]") and as_replay.summary.en.startswith("[REPLAY]")


async def test_reports(recordings):
    rec = recordings["p0106_map_sensor"]
    r = diagnose(from_recording(rec))
    meta = ReportMeta(data_mode="demo", demo_scenario="p0106_map_sensor")
    html_ar = render_report_html(r, meta, "ar")
    html_en = render_report_html(r, meta, "en")
    assert 'dir="rtl"' in html_ar and "بيانات تجريبية" in html_ar and "P0106" in html_ar
    assert 'dir="ltr"' in html_en and "DEMO DATA" in html_en
    j = render_report_json(r, meta)
    assert j["format"] == "automind.report.v1" and j["diagnosis"]["data_mode"] == "demo"
    json.dumps(j)
    with pytest.raises(ValueError):
        render_report_json(r, ReportMeta(data_mode="live"))  # cannot relabel demo data as live


async def test_reconnect_after_connection_drop():
    async with SimulatorServer(SimulatorConfig(scenario="healthy", port=0, drop_after=60)) as srv:
        c = ObdClient(TcpTransport("127.0.0.1", srv.port), timeout=1.0)
        assert (await c.connect(retries=1)).ok
        rec = await capture_session(c, duration_s=3, min_request_period_s=0)
        await c.close()
    types = [e.type for e in rec.events]
    assert "connection_lost" in types and "reconnected" in types
    assert srv.connections >= 2
    assert len(rec.samples) > 10


async def test_unreachable_adapter_reports_adapter_side():
    c = ObdClient(TcpTransport("127.0.0.1", 1, connect_timeout=0.5))
    rep = await c.connect(retries=2, backoff=0)
    assert rep.adapter_status == "unreachable" and rep.ecu_status == "not_attempted" and rep.attempts == 2


async def test_ignition_off_over_tcp():
    async with SimulatorServer(SimulatorConfig(port=0, ignition_on=False)) as srv:
        c = ObdClient(TcpTransport("127.0.0.1", srv.port))
        rep = await c.connect(retries=1)
        await c.close()
    assert rep.adapter_status == "connected" and rep.ecu_status == "no_response"


async def test_slow_adapter_latency():
    async with SimulatorServer(SimulatorConfig(port=0, latency_ms=150)) as srv:
        c = ObdClient(TcpTransport("127.0.0.1", srv.port), timeout=2.0)
        rep = await c.connect(retries=1)
        await c.close()
    assert rep.ok
