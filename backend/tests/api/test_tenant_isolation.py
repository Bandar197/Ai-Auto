"""Tenant isolation through PostgreSQL RLS (the API runs user requests as automind_app)."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest

from tests.api.factories import VALID_VIN, add_member, make_org, make_recording
from tests.api.test_health_errors import assert_envelope
from tests.conftest import register


@pytest.fixture
async def world(client):
    """User A with a vehicle, device, completed session (recording + diagnosis); user B with nothing."""
    pytest.importorskip("automind.diagnosis.engine")
    a = await register(client)
    b = await register(client)
    ha = a["headers"]
    v = (await client.post("/vehicles", headers=ha, json={"vin": VALID_VIN, "make": "Toyota"})).json()
    d = (await client.post("/devices", headers=ha, json={"name": "obd", "transport": "ble"})).json()
    s = (
        await client.post("/sessions", headers=ha, json={"data_mode": "live", "vehicle_id": v["id"], "device_id": d["id"]})
    ).json()
    rec = (await client.post(f"/sessions/{s['id']}/recording", headers=ha, json=make_recording("live", dtcs=["P0106"]))).json()
    r = await client.post(f"/sessions/{s['id']}/complete", headers=ha, json={"language": "en"})
    assert r.status_code == 200, r.text
    return {"a": a, "b": b, "vehicle": v, "device": d, "session": s, "recording": rec}


async def test_user_b_cannot_read_or_modify_a_data(client, world):
    hb = world["b"]["headers"]
    vid, sid, rid, did = (world["vehicle"]["id"], world["session"]["id"], world["recording"]["id"], world["device"]["id"])
    for path in (
        f"/vehicles/{vid}",
        f"/vehicles/{vid}?reveal_vin=true",
        f"/vehicles/{vid}/maintenance",
        f"/sessions/{sid}",
        f"/sessions/{sid}/diagnosis",
        f"/sessions/{sid}/telemetry",
        f"/sessions/{sid}/report",
        f"/sessions/{sid}/report?format=html",
        f"/recordings/{rid}",
    ):
        assert_envelope(await client.get(path, headers=hb), 404, "not_found")
    # writes
    assert_envelope(await client.patch(f"/vehicles/{vid}", headers=hb, json={"nickname": "mine"}), 404, "not_found")
    assert_envelope(await client.delete(f"/vehicles/{vid}", headers=hb), 404, "not_found")
    assert_envelope(await client.patch(f"/devices/{did}", headers=hb, json={"name": "x"}), 404, "not_found")
    assert_envelope(await client.delete(f"/devices/{did}", headers=hb), 404, "not_found")
    assert_envelope(await client.post(f"/sessions/{sid}/dtcs", headers=hb, json={"dtcs": []}), 404, "not_found")
    assert_envelope(await client.post(f"/sessions/{sid}/telemetry", headers=hb, json={"samples": []}), 404, "not_found")
    assert_envelope(await client.post(f"/sessions/{sid}/diagnose", headers=hb, json={}), 404, "not_found")
    assert_envelope(await client.post(f"/sessions/{sid}/complete", headers=hb, json={}), 404, "not_found")
    assert_envelope(await client.post(f"/recordings/{rid}/replay", headers=hb, json={}), 404, "not_found")
    # B can't link A's vehicle/device/recording into his own rows
    assert_envelope(await client.post("/sessions", headers=hb, json={"data_mode": "live", "vehicle_id": vid}), 404, "not_found")
    assert_envelope(await client.post("/sessions", headers=hb, json={"data_mode": "live", "device_id": did}), 404, "not_found")
    assert_envelope(
        await client.post("/sessions", headers=hb, json={"data_mode": "replay", "source_recording_id": rid}), 404, "not_found"
    )
    assert_envelope(
        await client.post(
            "/connections",
            headers=hb,
            json={
                "vehicle_id": vid,
                "data_mode": "live",
                "adapter_status": "connected",
                "ecu_status": "connected",
                "started_at": datetime.now(UTC).isoformat(),
            },
        ),
        404,
        "not_found",
    )
    assert_envelope(
        await client.post(
            f"/sessions/{sid}/shares", headers=hb, json={"organization_id": str(uuid.uuid4()), "consent_version": "v1"}
        ),
        404,
        "not_found",
    )


async def test_user_b_lists_are_empty(client, world):
    hb = world["b"]["headers"]
    for path in ("/vehicles", "/devices", "/sessions", "/recordings", "/notifications"):
        body = (await client.get(path, headers=hb)).json()
        assert body["total"] == 0 and body["items"] == [], path
    export = (await client.get("/me/export", headers=hb)).json()
    assert export["vehicles"] == [] and export["sessions"] == [] and export["telemetry"] == []
    # A still sees everything
    ha = world["a"]["headers"]
    assert (await client.get("/sessions", headers=ha)).json()["total"] == 1
    assert (await client.get("/vehicles", headers=ha)).json()["total"] == 1


async def test_rls_enforced_in_database_not_only_in_api(app, world, db):
    """Even a raw query on a user connection returns nothing of A's for B."""
    from sqlalchemy import func, select

    from automind.db import tables as t

    svc = app.state.services
    b_id = uuid.UUID(world["b"]["user"]["id"])
    async with svc.db.user(b_id) as conn:
        for table in (
            t.vehicles,
            t.diagnostic_sessions,
            t.telemetry_readings,
            t.telemetry_recordings,
            t.diagnostic_trouble_codes,
            t.diagnostic_findings,
            t.ai_diagnoses,
            t.diagnosis_evidence,
            t.obd_devices,
            t.audit_logs,
        ):
            n = (await conn.execute(select(func.count()).select_from(table))).scalar_one()
            assert n == 0, table.name
        assert (await conn.execute(select(func.count()).select_from(t.users))).scalar_one() == 1  # only himself
        foreign = select(func.count()).select_from(t.user_consents).where(t.user_consents.c.user_id != b_id)
        assert (await conn.execute(foreign)).scalar_one() == 0
    # and the owner connection really has the data
    assert await db.fetchval("select count(*) from automind.telemetry_readings") > 0


async def test_user_cannot_escalate_privileges_via_rls_session(app, world):
    from sqlalchemy import update
    from sqlalchemy.exc import DBAPIError

    from automind.db import tables as t

    svc = app.state.services
    b_id = uuid.UUID(world["b"]["user"]["id"])
    with pytest.raises(DBAPIError):
        async with svc.db.user(b_id) as conn:
            await conn.execute(update(t.users).where(t.users.c.id == b_id).values(platform_role="super_admin"))


async def test_org_share_grants_access_only_while_active_and_only_to_that_org(client, db, world):
    a, ha = world["a"], world["a"]["headers"]
    sid = world["session"]["id"]
    org_x = await make_org(db, "Workshop X")
    org_y = await make_org(db, "Workshop Y")
    tech_x = await register(client)
    tech_y = await register(client)
    await add_member(db, org_x, tech_x["user"]["id"])
    await add_member(db, org_y, tech_y["user"]["id"])

    # before sharing nobody sees it
    assert_envelope(await client.get(f"/sessions/{sid}", headers=tech_x["headers"]), 404, "not_found")

    # only the owner can share
    r = await client.post(
        f"/sessions/{sid}/shares", headers=tech_x["headers"], json={"organization_id": str(org_x), "consent_version": "v1"}
    )
    assert_envelope(r, 404, "not_found")
    r = await client.post(
        f"/sessions/{sid}/shares",
        headers=ha,
        json={
            "organization_id": str(org_x),
            "consent_version": "share-v1",
            "include_vin": False,
            "include_live_data": False,
            "expires_in_days": 7,
        },
    )
    assert r.status_code == 201, r.text
    share = r.json()
    assert share["organization_id"] == str(org_x)

    # member of org X can read the session, diagnosis and report — but not the vehicle itself
    hx = tech_x["headers"]
    assert (await client.get(f"/sessions/{sid}", headers=hx)).status_code == 200
    assert (await client.get(f"/sessions/{sid}/diagnosis", headers=hx)).status_code == 200
    rep = await client.get(f"/sessions/{sid}/report?format=json", headers=hx)
    assert rep.status_code == 200, rep.text
    assert "vin_masked" not in rep.json()["meta"]["vehicle"]  # include_vin = false
    assert_envelope(await client.get(f"/sessions/{sid}/telemetry", headers=hx), 403, "forbidden")  # live data off
    assert_envelope(await client.get(f"/vehicles/{world['vehicle']['id']}", headers=hx), 404, "not_found")
    # read-only: org X can't modify A's session, nor list it as its own
    assert_envelope(await client.post(f"/sessions/{sid}/diagnose", headers=hx, json={}), 403, "forbidden")
    assert (await client.get("/sessions", headers=hx)).json()["total"] == 0

    # member of org Y sees nothing
    assert_envelope(await client.get(f"/sessions/{sid}", headers=tech_y["headers"]), 404, "not_found")
    assert_envelope(await client.get(f"/sessions/{sid}/report", headers=tech_y["headers"]), 404, "not_found")

    # expired share → no access
    await db.execute(
        "update automind.report_shares set granted_at = now() - interval '2 days', "
        "expires_at = now() - interval '1 second' where id = $1",
        uuid.UUID(share["id"]),
    )
    assert_envelope(await client.get(f"/sessions/{sid}", headers=hx), 404, "not_found")
    await db.execute(
        "update automind.report_shares set expires_at = now() + interval '1 day' where id = $1", uuid.UUID(share["id"])
    )
    assert (await client.get(f"/sessions/{sid}", headers=hx)).status_code == 200

    # revoke → no access, audited
    assert (await client.delete(f"/sessions/{sid}/shares/{share['id']}", headers=ha)).status_code == 204
    assert_envelope(await client.get(f"/sessions/{sid}", headers=hx), 404, "not_found")
    actions = {
        r["action"]
        for r in await db.fetch("select action from automind.audit_logs where actor_user_id=$1", uuid.UUID(a["user"]["id"]))
    }
    assert {"share.create", "share.revoke"} <= actions
    consent = await db.fetchval(
        "select count(*) from automind.user_consents where purpose='share_with_workshop' and user_id=$1",
        uuid.UUID(a["user"]["id"]),
    )
    assert consent == 1


async def test_sharing_with_unknown_or_inactive_org_is_404(client, db, world):
    ha = world["a"]["headers"]
    sid = world["session"]["id"]
    org = await make_org(db, "Closed")
    await db.execute("update automind.organizations set status='closed' where id=$1", org)
    for oid in (org, uuid.uuid4()):
        r = await client.post(f"/sessions/{sid}/shares", headers=ha, json={"organization_id": str(oid), "consent_version": "v1"})
        assert_envelope(r, 404, "not_found")
