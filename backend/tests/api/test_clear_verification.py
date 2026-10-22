"""Clear-and-verify through the API + the airbag clear policy."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from automind.control.policy import Conditions, ControlRequest, Procedure, evaluate
from tests.api.test_health_errors import assert_envelope
from tests.conftest import register

BODY = {"consent_text": "I understand.", "confirmed": True, "conditions": {"engine_running": False, "vehicle_speed_kmh": 0}}
READY = {"mil_on": False, "dtc_count": 0, "ignition": "spark",
         "monitors": {"components": {"available": True, "complete": True}, "catalyst": {"available": True, "complete": True}}}


async def _clear_flow(client, h, after_dtcs: list[dict], warmups: float | None):
    v = (await client.post("/vehicles", headers=h, json={"make": "Toyota", "model": "Camry", "model_year": 2018})).json()
    s1 = (await client.post("/sessions", headers=h, json={"data_mode": "live", "vehicle_id": v["id"]})).json()
    await client.post(f"/sessions/{s1['id']}/dtcs", headers=h,
                      json={"dtcs": [{"code": "P0102", "status": "stored", "source_service": "03"}]})
    op = (await client.post("/control/operations", headers=h,
                            json={**BODY, "procedure_key": "clear_dtcs", "data_mode": "live", "session_id": s1["id"]})).json()
    assert op["status"] == "approved", op
    r = await client.patch(f"/control/operations/{op['id']}", headers=h,
                           json={"status": "succeeded", "request_frames": ["04"], "response_frames": ["44"]})
    assert r.status_code == 204
    s2 = (await client.post("/sessions", headers=h, json={"data_mode": "live", "vehicle_id": v["id"]})).json()
    if after_dtcs:
        await client.post(f"/sessions/{s2['id']}/dtcs", headers=h, json={"dtcs": after_dtcs})
    if warmups is not None:
        now = datetime.now(UTC)
        samples = [{"ts": (now + timedelta(seconds=i)).isoformat(), "pid": "0130", "signal": "warmups_since_clear",
                    "value": warmups} for i in range(3)]
        samples += [{"ts": (now + timedelta(seconds=i)).isoformat(), "pid": "010C", "signal": "engine_rpm", "value": 760}
                    for i in range(3)]
        assert (await client.post(f"/sessions/{s2['id']}/telemetry", headers=h, json={"samples": samples})).status_code == 200
    r = await client.post(f"/sessions/{s2['id']}/complete", headers=h, json={"readiness": READY})
    assert r.status_code == 200, r.text
    return v["id"]


async def test_code_came_back_is_a_real_problem(client):
    u = await register(client)
    vid = await _clear_flow(client, u["headers"], [{"code": "P0102", "status": "stored", "source_service": "03"}], None)
    r = await client.get(f"/vehicles/{vid}/clear-verification", headers=u["headers"])
    assert r.status_code == 200, r.text
    v = r.json()
    assert v["overall"] == "problem_confirmed" and v["checks_after_clear"] == 1
    assert v["codes"][0]["code"] == "P0102" and v["codes"][0]["is_real_problem"] is True


async def test_code_stayed_away_after_self_test(client):
    u = await register(client)
    vid = await _clear_flow(client, u["headers"], [], warmups=1)
    v = (await client.get(f"/vehicles/{vid}/clear-verification", headers=u["headers"])).json()
    assert v["overall"] == "likely_resolved"
    assert v["codes"][0]["verdict"] == "not_returned_verified" and "قديم" in v["codes"][0]["title_ar"]


async def test_other_user_cannot_see_verification(client):
    u = await register(client)
    vid = await _clear_flow(client, u["headers"], [], warmups=None)
    other = await register(client)
    assert_envelope(await client.get(f"/vehicles/{vid}/clear-verification", headers=other["headers"]), 404, "not_found")


async def test_no_clear_yet_is_404(client):
    u = await register(client)
    v = (await client.post("/vehicles", headers=u["headers"], json={"make": "Ford"})).json()
    assert_envelope(await client.get(f"/vehicles/{v['id']}/clear-verification", headers=u["headers"]), 404, "not_found")


async def test_stateless_endpoint(client):
    u = await register(client)
    t0 = datetime(2026, 10, 1, tzinfo=UTC).isoformat()
    t1 = datetime(2026, 10, 1, 0, 2, tzinfo=UTC).isoformat()
    body = {"record": {"cleared_at": t0, "before": {"taken_at": t0, "dtcs": [{"code": "B0001", "status": "stored"}]}},
            "checks": [{"taken_at": t1, "dtcs": [{"code": "B0001", "status": "stored"}]}]}
    r = await client.post("/diagnosis/clear-verification", headers=u["headers"], json=body)
    assert r.status_code == 200 and r.json()["codes"][0]["verdict"] == "returned_immediately"
    assert (await client.post("/diagnosis/clear-verification", json=body)).status_code == 401


SRS = Procedure(key="clear_srs_dtcs", risk_level="medium", safety_category="airbag", enabled_by_default=False,
                is_prohibited=False, required_engine_state="ignition_on", level=2)


def _req(mode="live", **cond) -> ControlRequest:
    base = {"engine_running": False, "vehicle_speed_kmh": 0, "active_faults": 0, "repair_confirmed": True}
    return ControlRequest(data_mode=mode, confirmed=True, consent_text="ok", conditions=Conditions(**{**base, **cond}))


def test_srs_clear_refused_while_fault_active():
    d = evaluate(SRS, _req(active_faults=1))
    assert not d.approved and d.code == "active_fault" and "عطل نشط" in d.reason_ar
    assert evaluate(SRS, _req(active_faults=None)).code == "active_fault"  # unknown = not allowed


def test_srs_clear_needs_repair_confirmation_and_engine_off():
    assert evaluate(SRS, _req(repair_confirmed=False)).code == "repair_not_confirmed"
    assert evaluate(SRS, _req(engine_running=True)).code == "engine_running"


def test_srs_clear_live_needs_validated_vehicle_and_demo_is_simulated():
    assert evaluate(SRS, _req()).code == "not_allowlisted"  # no validated pack/adapter for this car
    d = evaluate(SRS, _req(mode="demo"))
    assert d.approved and d.simulated


async def test_srs_procedure_seeded_and_locked(client):
    u = await register(client)
    procs = {p["key"]: p for p in (await client.get("/control/procedures", headers=u["headers"])).json()}
    p = procs["clear_srs_dtcs"]
    assert p["safety_category"] == "airbag" and p["available"] is False and p["reason_ar"]
    assert procs["airbag_crash_data_reset"]["available"] is False
