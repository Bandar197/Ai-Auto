"""Sessions: ingestion, recording upload, replay, diagnosis persistence, telemetry series, reports."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest

from tests.api.factories import VALID_VIN, make_recording
from tests.api.test_health_errors import assert_envelope
from tests.conftest import register


def _need(module: str):
    return pytest.importorskip(module, reason=f"{module} (lead's module) not available yet")


async def _vehicle(client, h, **kw):
    r = await client.post("/vehicles", headers=h, json={"make": "Toyota", "model": "Camry", "model_year": 2018, **kw})
    assert r.status_code == 201, r.text
    return r.json()


async def test_session_create_validation(client):
    u = await register(client)
    h = u["headers"]
    assert_envelope(await client.post("/sessions", headers=h, json={"data_mode": "demo"}), 422, "validation_error")
    assert_envelope(await client.post("/sessions", headers=h, json={"data_mode": "replay"}), 422, "validation_error")
    assert_envelope(
        await client.post("/sessions", headers=h, json={"data_mode": "live", "vehicle_id": str(uuid.uuid4())}), 404, "not_found"
    )
    r = await client.post("/sessions", headers=h, json={"data_mode": "demo", "demo_scenario_key": "healthy"})
    assert r.status_code == 201 and r.json()["data_mode"] == "demo" and r.json()["status"] == "in_progress"


async def test_dtcs_telemetry_measurements_and_complete(client, db):
    _need("automind.diagnosis.engine")
    u = await register(client)
    h = u["headers"]
    v = await _vehicle(client, h)
    s = (
        await client.post(
            "/sessions", headers=h, json={"data_mode": "live", "vehicle_id": v["id"], "protocol_name": "ISO 15765-4"}
        )
    ).json()
    sid = s["id"]
    r = await client.post(
        f"/sessions/{sid}/dtcs",
        headers=h,
        json={
            "dtcs": [
                {
                    "code": "P0106",
                    "status": "stored",
                    "source_service": "03",
                    "ecu_address": "7E8",
                    "freeze_frame": {"values": {"engine_rpm": 800, "map_kpa": 60}},
                },
                {"code": "P0106", "status": "stored", "source_service": "03", "ecu_address": "7E8"},  # duplicate
            ]
        },
    )
    assert r.status_code == 204, r.text
    assert (await client.get(f"/sessions/{sid}", headers=h)).json()["dtc_count"] == 1

    start = datetime.now(UTC) - timedelta(minutes=5)
    samples = []
    for i in range(60):
        ts = (start + timedelta(seconds=i)).isoformat()
        samples += [
            {"ts": ts, "pid": "010C", "signal": "engine_rpm", "value": 780 + i % 5, "unit": "rpm"},
            {"ts": ts, "pid": "010B", "signal": "map_kpa", "value": 62.0, "unit": "kPa"},
            {"ts": ts, "pid": "0105", "signal": "coolant_temp_c", "value": 90.0, "unit": "°C"},
        ]
    r = await client.post(f"/sessions/{sid}/telemetry", headers=h, json={"samples": samples})
    assert r.status_code == 200 and r.json() == {"accepted": 180}

    # implausible timestamps are rejected
    future = (datetime.now(UTC) + timedelta(days=2)).isoformat()
    r = await client.post(
        f"/sessions/{sid}/telemetry",
        headers=h,
        json={"samples": [{"ts": future, "pid": "010C", "signal": "engine_rpm", "value": 1}]},
    )
    assert_envelope(r, 422, "validation_error")
    old = (datetime.now(UTC) - timedelta(days=400)).isoformat()
    r = await client.post(
        f"/sessions/{sid}/telemetry",
        headers=h,
        json={"samples": [{"ts": old, "pid": "010C", "signal": "engine_rpm", "value": 1}]},
    )
    assert_envelope(r, 422, "validation_error")
    too_many = [{"ts": start.isoformat(), "pid": "010C", "signal": "engine_rpm", "value": 1}] * 5001
    assert_envelope(
        await client.post(f"/sessions/{sid}/telemetry", headers=h, json={"samples": too_many}), 422, "validation_error"
    )

    r = await client.post(
        f"/sessions/{sid}/measurements",
        headers=h,
        json={"measurements": [{"key": "ac_low_side_pressure", "value": 30, "unit": "psi", "note": "gauge"}]},
    )
    assert r.status_code == 204

    assert_envelope(await client.get(f"/sessions/{sid}/diagnosis", headers=h), 404, "not_found")
    r = await client.post(f"/sessions/{sid}/complete", headers=h, json={"mil_on": True, "odometer_km": 100000, "language": "en"})
    assert r.status_code == 200, r.text
    result = r.json()
    assert result["data_mode"] == "live"
    assert 0 <= result["health_score"] <= 100
    assert any(d["code"] == "P0106" for d in result["dtcs"])

    sess = (await client.get(f"/sessions/{sid}", headers=h)).json()
    assert sess["status"] == "completed" and sess["completed_at"] and sess["mil_on"] is True
    assert sess["health_score"] == result["health_score"]
    assert sess["engine_version"] == result["engine_version"] and sess["kb_version"] == result["kb_version"]

    # GET diagnosis round-trips exactly
    assert (await client.get(f"/sessions/{sid}/diagnosis", headers=h)).json() == result

    # persisted rows
    sid_u = uuid.UUID(sid)
    n_findings = await db.fetchval("select count(*) from automind.diagnostic_findings where session_id=$1", sid_u)
    assert n_findings == len(result["findings"])
    n_ev = await db.fetchval("select count(*) from automind.diagnosis_evidence where session_id=$1", sid_u)
    assert n_ev == sum(len(f["evidence"]) for f in result["findings"])
    measured = await db.fetch("select is_measured from automind.diagnosis_evidence where session_id=$1", sid_u)
    expected_measured = [e["is_measured"] for f in result["findings"] for e in f["evidence"]]
    assert sorted(r["is_measured"] for r in measured) == sorted(expected_measured)
    ai = await db.fetchrow("select * from automind.ai_diagnoses where session_id=$1", sid_u)
    assert ai["engine"] == "rules" and ai["language"] == "en" and ai["input_sha256"]
    assert ai["summary_owner"] == result["summary"]["en"]
    aggs = {r["signal"]: r for r in await db.fetch("select * from automind.telemetry_aggregates where session_id=$1", sid_u)}
    assert aggs["engine_rpm"]["sample_count"] == 60 and aggs["map_kpa"]["avg_value"] == pytest.approx(62.0)
    summary = await db.fetchval("select summary from automind.diagnostic_sessions where id=$1", sid_u)
    assert "measurements" in summary and "latest_diagnosis" in summary

    # re-diagnose keeps history
    r = await client.post(f"/sessions/{sid}/diagnose", headers=h, json={"language": "ar"})
    assert r.status_code == 200
    assert await db.fetchval("select count(*) from automind.ai_diagnoses where session_id=$1", sid_u) == 2

    # telemetry series
    r = await client.get(f"/sessions/{sid}/telemetry?signals=engine_rpm,map_kpa", headers=h)
    body = r.json()
    assert set(body["series"]) == {"engine_rpm", "map_kpa"} and len(body["series"]["engine_rpm"]) == 60
    assert body["units"]["map_kpa"] == "kPa" and {"t", "v"} == set(body["series"]["map_kpa"][0])

    # closed sessions don't accept more raw data
    r = await client.post(
        f"/sessions/{sid}/dtcs", headers=h, json={"dtcs": [{"code": "P0300", "status": "pending", "source_service": "07"}]}
    )
    assert_envelope(r, 409, "conflict")


async def test_recording_upload_mismatch_and_replay(client, db):
    _need("automind.diagnosis.engine")
    _need("automind.diagnosis.input_builder")
    u = await register(client)
    h = u["headers"]
    live = (await client.post("/sessions", headers=h, json={"data_mode": "live"})).json()
    # a demo recording can never be attached to a live session
    r = await client.post(f"/sessions/{live['id']}/recording", headers=h, json=make_recording("demo"))
    err = assert_envelope(r, 422, "validation_error")
    assert err["details"]["field"] == "data_mode"
    # invalid recordings are rejected
    bad = make_recording("live")
    bad["dtcs"] = [{"code": "XYZ", "status": "stored"}]
    assert_envelope(await client.post(f"/sessions/{live['id']}/recording", headers=h, json=bad), 422, "validation_error")

    rec = make_recording("live", dtcs=["P0106"], vin=VALID_VIN)
    r = await client.post(f"/sessions/{live['id']}/recording", headers=h, json=rec)
    assert r.status_code == 201, r.text
    meta = r.json()
    assert meta["data_mode"] == "live" and meta["sample_count"] == len(rec["samples"])
    assert set(meta["signals"]) == {"engine_rpm", "map_kpa", "coolant_temp_c", "vehicle_speed_kmh"}
    # derived rows
    lid = uuid.UUID(live["id"])
    assert await db.fetchval("select count(*) from automind.diagnostic_trouble_codes where session_id=$1", lid) == 1
    n_tel = await db.fetchval("select count(*) from automind.telemetry_readings where session_id=$1", lid)
    assert n_tel == len(rec["samples"])
    pids = {r["pid"] for r in await db.fetch("select distinct pid from automind.telemetry_readings where session_id=$1", lid)}
    assert pids == {"010C", "010B", "0105", "010D"}
    # VIN never stored in clear text inside the recording
    stored = (await client.get(f"/recordings/{meta['id']}", headers=h)).json()
    assert stored["vehicle"]["vin"] == "2C3CDZ*******1234"
    assert stored["data_mode"] == "live"

    # replay → new replay session linked to the recording, diagnosis persisted
    r = await client.post(f"/recordings/{meta['id']}/replay", headers=h, json={"language": "en"})
    assert r.status_code == 201, r.text
    out = r.json()
    rs = out["session"]
    assert rs["data_mode"] == "replay" and rs["source_recording_id"] == meta["id"] and rs["status"] == "completed"
    assert out["diagnosis"]["data_mode"] == "replay"
    assert (await client.get(f"/sessions/{rs['id']}/diagnosis", headers=h)).json() == out["diagnosis"]
    rid = uuid.UUID(rs["id"])
    assert await db.fetchval("select count(*) from automind.ai_diagnoses where session_id=$1", rid) == 1
    assert await db.fetchval("select count(*) from automind.telemetry_readings where session_id=$1", rid) > 0
    # the original recording keeps its data_mode
    assert await db.fetchval("select data_mode from automind.telemetry_recordings where id=$1", uuid.UUID(meta["id"])) == "live"
    # list recordings
    assert (await client.get("/recordings", headers=h)).json()["total"] == 1


async def test_recording_too_large_returns_413(client, settings, database_url):
    import httpx

    from automind.api.main import create_app
    from tests.conftest import make_settings

    small = create_app(make_settings(database_url, max_inline_recording_bytes=2048))
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=small), base_url="http://t/api/v1") as c:
        u = await register(c)
        r = await c.post("/recordings", headers=u["headers"], json=make_recording("live", seconds=20))
        assert_envelope(r, 413, "payload_too_large")


async def test_stateless_analyze(client, db):
    _need("automind.diagnosis.engine")
    u = await register(client)
    r = await client.post(
        "/diagnosis/analyze", headers=u["headers"], json={"recording": make_recording("live", dtcs=["P0106"]), "language": "en"}
    )
    assert r.status_code == 200, r.text
    assert r.json()["data_mode"] == "live"
    assert await db.fetchval("select count(*) from automind.diagnostic_sessions") == 0
    assert_envelope(await client.post("/diagnosis/analyze", json={"recording": make_recording()}), 401, "unauthorized")


async def test_report_json_and_html(client):
    _need("automind.reports")
    _need("automind.diagnosis.engine")
    u = await register(client)
    h = u["headers"]
    v = await _vehicle(client, h, vin=VALID_VIN)
    s = (await client.post("/sessions", headers=h, json={"data_mode": "live", "vehicle_id": v["id"]})).json()
    await client.post(f"/sessions/{s['id']}/recording", headers=h, json=make_recording("live", dtcs=["P0106"]))
    assert_envelope(await client.get(f"/sessions/{s['id']}/report", headers=h), 404, "not_found")
    await client.post(f"/sessions/{s['id']}/complete", headers=h, json={})
    r = await client.get(f"/sessions/{s['id']}/report?format=json&lang=en", headers=h)
    assert r.status_code == 200, r.text
    rep = r.json()
    assert rep["data_mode"] == "live" and rep["meta"]["data_mode"] == "live"
    assert rep["meta"]["vehicle"]["vin_masked"] == "2C3CDZ*******1234"
    assert any(d["code"] == "P0106" for d in rep["diagnosis"]["dtcs"])
    r = await client.get(f"/sessions/{s['id']}/report?format=html&lang=ar", headers=h)
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    assert "P0106" in r.text
    assert VALID_VIN not in r.text


async def test_demo_scenarios_and_run(client, db):
    _need("automind.simulator.runner")
    _need("automind.diagnosis.engine")
    u = await register(client)
    h = u["headers"]
    scenarios = (await client.get("/demo/scenarios", headers=h)).json()
    keys = {s["key"] for s in scenarios}
    assert "p0106_map_sensor" in keys
    assert {"key", "name_en", "name_ar", "description_en", "description_ar", "dtcs"} == set(scenarios[0])
    assert_envelope(await client.post("/demo/run", headers=h, json={"scenario_key": "nope_nope"}), 404, "not_found")
    assert_envelope(
        await client.post("/demo/run", headers=h, json={"scenario_key": "healthy", "duration_s": 5}), 422, "validation_error"
    )
    r = await client.post("/demo/run", headers=h, json={"scenario_key": "p0106_map_sensor", "duration_s": 30, "language": "en"})
    assert r.status_code == 201, r.text
    out = r.json()
    assert out["session"]["data_mode"] == "demo" and out["session"]["demo_scenario_key"] == "p0106_map_sensor"
    assert out["diagnosis"]["data_mode"] == "demo"
    assert any(d["code"] == "P0106" for d in out["diagnosis"]["dtcs"])
    sid = uuid.UUID(out["session"]["id"])
    assert await db.fetchval("select data_mode from automind.telemetry_recordings where session_id=$1", sid) == "demo"
    assert await db.fetchval("select count(*) from automind.telemetry_readings where session_id=$1", sid) > 0
