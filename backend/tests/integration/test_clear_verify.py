"""Clear-and-verify end-to-end through the TCP simulator.

* p0106_map_sensor: the fault is still physically present → after clearing,
  the code is detected again (pending, then stored) → "problem_confirmed".
* old_code_repaired: stored P0102 left from a repaired connector, live data
  normal → after clearing and the self-tests running, it stays away →
  "likely_resolved".
"""

import asyncio
from datetime import UTC, datetime, timedelta

from automind.diagnosis.models import InputDTC
from automind.diagnosis.recurrence import ClearRecord, ScanSnapshot, assess_after_clear, monitor_for
from automind.obd.client import ClearAuthorization, ObdClient
from automind.obd.transport.tcp import TcpTransport
from automind.simulator.server import SimulatorConfig, SimulatorServer

TIME_SCALE = 40.0  # 1 real second = 40 simulated seconds


async def _snapshot(c: ObdClient) -> ScanSnapshot:
    vals = {}
    for pid in ("0C", "30", "31"):
        if c.is_supported(pid):
            vals.update((await c.read_pid(pid)).values)
    return ScanSnapshot(
        taken_at=datetime.now(UTC),
        dtcs=[InputDTC(code=d.code, status=d.status, ecu=d.ecu) for d in await c.read_all_dtcs()],
        readiness=await c.monitor_status(),
        warmups_since_clear=vals.get("warmups_since_clear"),
        distance_since_clear_km=vals.get("distance_since_clear"),
        engine_running=(vals.get("engine_rpm") or 0) > 300,
    )


async def _run(scenario: str, waits_s: list[float]):
    cfg = SimulatorConfig(scenario=scenario, port=0, time_scale=TIME_SCALE, engine_running=False,
                          start_engine_after_clear_s=5)
    async with SimulatorServer(cfg) as srv:
        c = ObdClient(TcpTransport("127.0.0.1", srv.port))
        assert (await c.connect(retries=1)).ok
        before = await _snapshot(c)
        res = await c.clear_dtcs(ClearAuthorization("op-test", True, "I understand"))
        assert res["ok"]
        record = ClearRecord(cleared_at=datetime.now(UTC), before=before, data_mode="demo")
        checks = [await _snapshot(c)]  # immediate re-check, same key cycle
        await c.close()
        for w in waits_s:  # later scans on new connections (vehicle state persists)
            await asyncio.sleep(w)
            c = ObdClient(TcpTransport("127.0.0.1", srv.port))
            assert (await c.connect(retries=1)).ok
            checks.append(await _snapshot(c))
            await c.close()
    return record, checks


async def test_fault_still_present_comes_back():
    record, checks = await _run("p0106_map_sensor", [1.5])  # +60 simulated seconds
    v = assess_after_clear(record, checks)
    assert v.overall == "problem_confirmed"
    p0106 = next(cv for cv in v.codes if cv.code == "P0106")
    assert p0106.verdict in ("returned_confirmed", "returned_pending") and p0106.is_real_problem is True
    assert "حقيقي" in p0106.title_ar or "اكتُشف" in p0106.title_ar


async def test_repaired_old_code_does_not_come_back():
    record, checks = await _run("old_code_repaired", [3.0])  # +120 simulated seconds → monitors complete
    v = assess_after_clear(record, checks)
    p0102 = next(cv for cv in v.codes if cv.code == "P0102")
    assert p0102.verdict == "not_returned_verified" and p0102.is_real_problem is False
    assert v.overall == "likely_resolved"
    assert "غالبا عطل قديم" in p0102.title_ar


async def test_immediate_recheck_alone_is_not_proof():
    record, checks = await _run("old_code_repaired", [])
    v = assess_after_clear(record, checks)
    assert v.overall == "verifying"  # not returned yet, but self-tests have not run


def test_airbag_code_logic_without_vehicle_access():
    t0 = datetime(2026, 10, 1, tzinfo=UTC)
    rec = ClearRecord(cleared_at=t0, before=ScanSnapshot(taken_at=t0, dtcs=[InputDTC(code="B0001", ecu="SRS")]))
    back = [ScanSnapshot(taken_at=t0 + timedelta(minutes=1), dtcs=[InputDTC(code="B0001")])]
    v = assess_after_clear(rec, back)
    assert v.codes[0].verdict == "returned_immediately" and "الوسائد" in v.codes[0].explanation_ar
    gone = [ScanSnapshot(taken_at=t0 + timedelta(hours=h)) for h in (1, 9)]
    v2 = assess_after_clear(rec, gone)
    assert v2.codes[0].verdict == "not_returned_verified" and "فحمة الدركسون" in v2.codes[0].explanation_ar
    v3 = assess_after_clear(rec, gone[:1])
    assert v3.codes[0].verdict == "not_returned_yet"


def test_permanent_code_alone_is_not_a_return():
    t0 = datetime(2026, 10, 1, tzinfo=UTC)
    rec = ClearRecord(cleared_at=t0, before=ScanSnapshot(taken_at=t0, dtcs=[InputDTC(code="P0420", status="stored")]))
    snap = ScanSnapshot(taken_at=t0 + timedelta(days=1), dtcs=[InputDTC(code="P0420", status="permanent")],
                        warmups_since_clear=3, distance_since_clear_km=80)
    v = assess_after_clear(rec, [snap])
    assert v.codes[0].verdict == "still_permanent" and v.codes[0].is_real_problem is None


def test_new_code_after_clear_is_flagged():
    t0 = datetime(2026, 10, 1, tzinfo=UTC)
    rec = ClearRecord(cleared_at=t0, before=ScanSnapshot(taken_at=t0, dtcs=[InputDTC(code="P0171")]))
    snap = ScanSnapshot(taken_at=t0 + timedelta(days=1), dtcs=[InputDTC(code="P0300", status="pending")])
    v = assess_after_clear(rec, [snap])
    assert any(cv.verdict == "new_code" and cv.code == "P0300" for cv in v.codes) and v.overall == "problem_confirmed"


def test_monitor_mapping():
    assert monitor_for("P0302") == "misfire" and monitor_for("P0135") == "o2_sensor_heater"
    assert monitor_for("P0420") == "catalyst" and monitor_for("P0106") == "components"
    assert monitor_for("B0001") is None and monitor_for("U0100") is None


async def test_counters_reset_while_engine_still_off_after_clear():
    """Right after a clear (engine not started yet) warm-ups/distance must read 0, not the old values."""
    cfg = SimulatorConfig(scenario="p0106_map_sensor", port=0, time_scale=1, engine_running=False)
    async with SimulatorServer(cfg) as srv:
        c = ObdClient(TcpTransport("127.0.0.1", srv.port))
        assert (await c.connect(retries=1)).ok
        assert (await c.read_pid("30")).values["warmups_since_clear"] == 12
        await c.clear_dtcs(ClearAuthorization("op", True, "ok"))
        assert (await c.read_pid("30")).values["warmups_since_clear"] == 0
        assert (await c.read_pid("31")).values["distance_since_clear"] == 0
        await c.close()
