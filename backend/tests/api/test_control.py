"""AutoMind Control: pure policy unit tests + API behaviour (storage, audit, simulated mode)."""

from __future__ import annotations

import uuid

import pytest

from automind.control.policy import (
    AllowlistEntry,
    Conditions,
    ControlRequest,
    DeviceCtx,
    Procedure,
    VehicleCtx,
    evaluate,
)
from tests.api.test_health_errors import assert_envelope
from tests.conftest import register

CLEAR = Procedure(
    key="clear_dtcs",
    risk_level="medium",
    safety_category="emissions",
    enabled_by_default=True,
    is_prohibited=False,
    required_engine_state="ignition_on",
    obd_service="04",
)
ODO = Procedure(
    key="odometer_adjustment", risk_level="prohibited", safety_category="odometer", enabled_by_default=False, is_prohibited=True
)
OIL = Procedure(
    key="reset_oil_service_indicator",
    risk_level="low",
    safety_category="body",
    enabled_by_default=False,
    is_prohibited=False,
    level=2,
)
THROTTLE = Procedure(
    key="throttle_body_relearn",
    risk_level="medium",
    safety_category="powertrain",
    enabled_by_default=False,
    is_prohibited=False,
    required_engine_state="running",
)

OFF = Conditions(engine_running=False, vehicle_speed_kmh=0)


def req(mode="live", confirmed=True, consent="I understand", cond=OFF, ecu=None):
    return ControlRequest(data_mode=mode, confirmed=confirmed, consent_text=consent, conditions=cond, ecu_address=ecu)


# ----------------------------------------------------------------------------- pure policy
@pytest.mark.nodb
@pytest.mark.parametrize("mode", ["live", "demo", "replay"])
def test_prohibited_always_rejected(mode):
    d = evaluate(
        ODO,
        req(mode),
        allowlist=[AllowlistEntry(active=True, requires_certified_device=False)],
        device=DeviceCtx(is_certified=True),
    )
    assert not d.approved and d.code == "prohibited" and d.reason_en and d.reason_ar


@pytest.mark.nodb
def test_clear_dtcs_conditions():
    assert evaluate(CLEAR, req()).approved
    assert evaluate(CLEAR, req()).commands == ("04",)
    d = evaluate(CLEAR, req(cond=Conditions(engine_running=True, vehicle_speed_kmh=0)))
    assert not d.approved and d.code == "engine_running" and d.reason_ar
    d = evaluate(CLEAR, req(cond=Conditions(engine_running=False, vehicle_speed_kmh=5)))
    assert not d.approved and d.code == "vehicle_moving"
    d = evaluate(CLEAR, req(cond=Conditions(engine_running=False, vehicle_speed_kmh=None)))
    assert not d.approved
    assert evaluate(CLEAR, req(confirmed=False)).code == "not_confirmed"
    assert evaluate(CLEAR, req(consent="   ")).code == "consent_missing"
    # conditions apply in demo too (faithful simulation)
    assert evaluate(CLEAR, req("demo", cond=Conditions(engine_running=True, vehicle_speed_kmh=0))).code == "engine_running"


@pytest.mark.nodb
@pytest.mark.parametrize("mode", ["demo", "replay"])
def test_simulated_modes_flagged(mode):
    d = evaluate(CLEAR, req(mode))
    assert d.approved and d.simulated and "No command is sent to a real vehicle" in d.notice_en and d.notice_ar
    # not-enabled procedures can be demonstrated without an allow-list, still simulated
    d = evaluate(OIL, req(mode))
    assert d.approved and d.simulated


@pytest.mark.nodb
def test_allowlist_matching_and_certification():
    v = VehicleCtx(make="Toyota", model="Camry", model_year=2019)
    cert = DeviceCtx(adapter_type="stn21xx", is_certified=True)
    plain = DeviceCtx(adapter_type="elm327", is_certified=False)
    assert evaluate(OIL, req(), vehicle=v, device=cert).code == "not_allowlisted"
    entry = AllowlistEntry(
        active=True,
        make="toyota",
        model="Camry",
        year_from=2018,
        year_to=2022,
        adapter_type="stn21xx",
        requires_certified_device=True,
    )
    assert evaluate(OIL, req(), vehicle=v, device=cert, allowlist=[entry]).approved
    # inactive entry, wrong year, wrong make, wrong adapter → no match
    for e, vv, dev in [
        (AllowlistEntry(active=False, make="Toyota"), v, cert),
        (entry, VehicleCtx(make="Toyota", model="Camry", model_year=2017), cert),
        (entry, VehicleCtx(make="Nissan", model="Camry", model_year=2019), cert),
        (entry, v, DeviceCtx(adapter_type="elm327", is_certified=True)),
    ]:
        assert evaluate(OIL, req(), vehicle=vv, device=dev, allowlist=[e]).code == "not_allowlisted"
    # certified device required
    e2 = AllowlistEntry(active=True, make="Toyota", requires_certified_device=True)
    assert evaluate(OIL, req(), vehicle=v, device=plain, allowlist=[e2]).code == "device_not_certified"
    assert evaluate(OIL, req(), vehicle=v, device=None, allowlist=[e2]).code == "device_not_certified"
    e3 = AllowlistEntry(active=True, make="Toyota", requires_certified_device=False)
    assert evaluate(OIL, req(), vehicle=v, device=plain, allowlist=[e3]).approved
    # ECU constraint
    e4 = AllowlistEntry(active=True, ecu_address="7E0", requires_certified_device=False)
    assert evaluate(OIL, req(ecu="7E8"), allowlist=[e4]).code == "not_allowlisted"
    assert evaluate(OIL, req(ecu="7e0"), allowlist=[e4]).approved


@pytest.mark.nodb
def test_engine_state_requirement():
    e = AllowlistEntry(active=True, requires_certified_device=False)
    assert evaluate(THROTTLE, req(cond=OFF), allowlist=[e]).code == "engine_not_running"
    assert evaluate(THROTTLE, req(cond=Conditions(engine_running=True, vehicle_speed_kmh=0)), allowlist=[e]).approved


# ----------------------------------------------------------------------------- API
BODY = {
    "consent_text": "I accept that codes and readiness monitors are reset.",
    "confirmed": True,
    "conditions": {"engine_running": False, "vehicle_speed_kmh": 0},
}


async def test_procedures_listing(client):
    u = await register(client)
    procs = {p["key"]: p for p in (await client.get("/control/procedures", headers=u["headers"])).json()}
    assert procs["clear_dtcs"]["available"] is True
    assert procs["odometer_adjustment"]["available"] is False and procs["odometer_adjustment"]["reason_ar"]
    assert procs["abs_bleed"]["available"] is False
    assert isinstance(procs["clear_dtcs"]["preconditions"], list)


async def test_operation_prohibited_rejected_and_stored(client, db):
    u = await register(client)
    r = await client.post(
        "/control/operations", headers=u["headers"], json={**BODY, "procedure_key": "odometer_adjustment", "data_mode": "live"}
    )
    assert r.status_code == 201, r.text
    out = r.json()
    assert out["status"] == "rejected_policy" and out["reason"] == "prohibited" and out["reason_ar"]
    assert "commands" not in out
    row = await db.fetchrow("select status, rejection_reason from automind.control_operations where id=$1", uuid.UUID(out["id"]))
    assert row["status"] == "rejected_policy" and row["rejection_reason"].startswith("prohibited")
    audit = await db.fetchrow(
        "select outcome from automind.audit_logs where action='control.request' and entity_id=$1", out["id"]
    )
    assert audit["outcome"] == "denied"
    # a rejected operation can't report a result
    r = await client.patch(f"/control/operations/{out['id']}", headers=u["headers"], json={"status": "succeeded"})
    assert_envelope(r, 403, "policy_rejected")


async def _live_session_with_codes(client, h) -> dict:
    v = (await client.post("/vehicles", headers=h, json={"make": "Dodge", "model": "Challenger", "model_year": 2019})).json()
    s = (await client.post("/sessions", headers=h, json={"data_mode": "live", "vehicle_id": v["id"]})).json()
    r = await client.post(f"/sessions/{s['id']}/dtcs", headers=h,
                          json={"dtcs": [{"code": "P0106", "status": "stored", "source_service": "03"}]})
    assert r.status_code == 204, r.text
    return {"vehicle_id": v["id"], "session_id": s["id"]}


async def test_clear_requires_saved_scan(client):
    u = await register(client)
    r = await client.post("/control/operations", headers=u["headers"],
                          json={**BODY, "procedure_key": "clear_dtcs", "data_mode": "live"})
    assert_envelope(r, 422, "validation_error")


async def test_clear_dtcs_live_flow(client, db):
    u = await register(client)
    h = u["headers"]
    base = {**BODY, **(await _live_session_with_codes(client, h))}
    r = await client.post(
        "/control/operations",
        headers=h,
        json={
            **base,
            "procedure_key": "clear_dtcs",
            "data_mode": "live",
            "conditions": {"engine_running": True, "vehicle_speed_kmh": 0},
        },
    )
    assert r.json()["status"] == "rejected_policy" and r.json()["reason"] == "engine_running"
    r = await client.post(
        "/control/operations",
        headers=h,
        json={
            **base,
            "procedure_key": "clear_dtcs",
            "data_mode": "live",
            "conditions": {"engine_running": False, "vehicle_speed_kmh": 12},
        },
    )
    assert r.json()["reason"] == "vehicle_moving"
    r = await client.post(
        "/control/operations", headers=h, json={**base, "procedure_key": "clear_dtcs", "data_mode": "live", "confirmed": False}
    )
    assert r.json()["reason"] == "not_confirmed"
    assert_envelope(
        await client.post(
            "/control/operations",
            headers=h,
            json={**base, "procedure_key": "clear_dtcs", "data_mode": "live", "consent_text": ""},
        ),
        422,
        "validation_error",
    )

    r = await client.post("/control/operations", headers=h, json={**base, "procedure_key": "clear_dtcs", "data_mode": "live"})
    out = r.json()
    assert out["status"] == "approved" and out["commands"] == ["04"] and out["simulated"] is False
    r = await client.patch(
        f"/control/operations/{out['id']}",
        headers=h,
        json={"status": "succeeded", "request_frames": ["04"], "response_frames": ["44"], "result": {"cleared": True}},
    )
    assert r.status_code == 204
    row = await db.fetchrow("select * from automind.control_operations where id=$1", uuid.UUID(out["id"]))
    assert row["status"] == "succeeded" and row["request_frames"] == ["04"] and row["finished_at"]
    assert_envelope(await client.patch(f"/control/operations/{out['id']}", headers=h, json={"status": "failed"}), 409, "conflict")
    actions = [r["action"] for r in await db.fetch("select action from automind.audit_logs where entity_id=$1", out["id"])]
    assert actions == ["control.request", "control.result"]
    # another user can't report on it
    other = await register(client)
    assert_envelope(
        await client.patch(f"/control/operations/{out['id']}", headers=other["headers"], json={"status": "failed"}),
        404,
        "not_found",
    )


async def test_demo_mode_is_simulated(client):
    u = await register(client)
    r = await client.post(
        "/control/operations", headers=u["headers"], json={**BODY, "procedure_key": "clear_dtcs", "data_mode": "demo"}
    )
    out = r.json()
    assert out["status"] == "approved" and out["simulated"] is True
    assert out["commands"] == [] and out["simulated_commands"] == ["04"] and out["real_vehicle_command"] is False
    assert "No command is sent to a real vehicle" in out["notice_en"] and out["notice_ar"]


async def test_session_mode_must_match(client):
    u = await register(client)
    s = (await client.post("/sessions", headers=u["headers"], json={"data_mode": "live"})).json()
    r = await client.post(
        "/control/operations",
        headers=u["headers"],
        json={**BODY, "procedure_key": "clear_dtcs", "data_mode": "demo", "session_id": s["id"]},
    )
    assert_envelope(r, 422, "validation_error")


async def test_allowlisted_procedure_needs_certified_device(client, db):
    u = await register(client)
    h = u["headers"]
    v = (await client.post("/vehicles", headers=h, json={"make": "Toyota", "model": "Camry", "model_year": 2019})).json()
    d = (await client.post("/devices", headers=h, json={"name": "stn", "transport": "ble", "adapter_type": "stn21xx"})).json()
    body = {
        **BODY,
        "procedure_key": "reset_oil_service_indicator",
        "data_mode": "live",
        "vehicle_id": v["id"],
        "device_id": d["id"],
    }
    assert (await client.post("/control/operations", headers=h, json=body)).json()["reason"] == "not_allowlisted"
    admin_id = uuid.UUID(u["user"]["id"])
    await db.execute(
        """insert into automind.procedure_allowlist (procedure_id, make, year_from, year_to,
        adapter_type, requires_certified_device, approved_by, approved_at, active)
        select id, 'Toyota', 2018, 2022, 'stn21xx', true, $1, now(), true
        from automind.service_procedures where key = 'reset_oil_service_indicator'""",
        admin_id,
    )
    assert (await client.post("/control/operations", headers=h, json=body)).json()["reason"] == "device_not_certified"
    # certification is a platform decision (owners can't self-certify: DB trigger) — set as the system role
    await db.execute("update automind.obd_devices set is_certified = true where id = $1", uuid.UUID(d["id"]))
    out = (await client.post("/control/operations", headers=h, json=body)).json()
    assert out["status"] == "approved" and out["simulated"] is False


async def test_owner_cannot_self_certify_device(app, client):
    from sqlalchemy import update
    from sqlalchemy.exc import DBAPIError

    from automind.db import tables as t

    u = await register(client)
    d = (await client.post("/devices", headers=u["headers"], json={"name": "x", "transport": "ble"})).json()
    with pytest.raises(DBAPIError):
        async with app.state.services.db.user(uuid.UUID(u["user"]["id"])) as conn:
            await conn.execute(update(t.obd_devices).where(t.obd_devices.c.id == uuid.UUID(d["id"])).values(is_certified=True))
