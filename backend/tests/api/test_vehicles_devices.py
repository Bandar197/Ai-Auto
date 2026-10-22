"""Vehicles (VIN encryption, masking, reveal), plan limits, maintenance, devices, connections."""

from __future__ import annotations

from datetime import UTC, datetime

from automind.core.crypto import mask_vin, normalize_vin
from tests.api.factories import VALID_VIN
from tests.api.test_health_errors import assert_envelope
from tests.conftest import register


async def test_vin_encrypted_masked_and_revealed_with_audit(client, db):
    u = await register(client)
    h = u["headers"]
    r = await client.post(
        "/vehicles",
        headers=h,
        json={"vin": " 2c3cdzag7jh101234 ", "make": "Dodge", "model": "Challenger", "model_year": 2018, "plate": "ABC 123"},
    )
    assert r.status_code == 201, r.text
    v = r.json()
    assert v["vin_masked"] == "2C3CDZ*******1234" and v["vin_wmi"] == "2C3"
    assert "vin" not in v
    row = await db.fetchrow("select * from automind.vehicles where id = $1", v["id"])
    assert VALID_VIN.encode() not in bytes(row["vin_ciphertext"]) and bytes(row["vin_ciphertext"])[:1] == b"\x01"
    assert len(bytes(row["vin_blind_index"])) == 32
    assert row["vin_model_year_code"] == "J"
    assert b"ABC" not in bytes(row["plate_ciphertext"])

    r = await client.get(f"/vehicles/{v['id']}", headers=h)
    assert "vin" not in r.json()
    r = await client.get(f"/vehicles/{v['id']}?reveal_vin=true", headers=h)
    assert r.status_code == 200 and r.json()["vin"] == VALID_VIN
    n = await db.fetchval(
        "select count(*) from automind.audit_logs where action = 'vehicle.reveal_vin' and entity_id = $1 and outcome = 'success'",
        v["id"],
    )
    assert n == 1

    # same VIN twice for the same owner → conflict (blind index lookup)
    await db.execute("update automind.subscriptions set status='expired' where user_id = $1", u["user"]["id"])
    pro = await db.fetchval("select id from automind.subscription_plans where key='pro'")
    await db.execute(
        "insert into automind.subscriptions (user_id, plan_id, status, billing_period, provider, "
        "current_period_start) values ($1,$2,'active','monthly','manual',now())",
        __import__("uuid").UUID(u["user"]["id"]),
        pro,
    )
    r = await client.post("/vehicles", headers=h, json={"vin": VALID_VIN})
    assert_envelope(r, 409, "conflict")


async def test_invalid_vin_rejected(client):
    u = await register(client)
    for bad in ("123", "2C3CDZAG7JH10123O", "2C3CDZAG7JH1012345"):
        r = await client.post("/vehicles", headers=u["headers"], json={"vin": bad})
        assert_envelope(r, 422, "validation_error")


def test_vin_helpers():
    assert normalize_vin("2c3-cdz ag7jh101234") == VALID_VIN
    assert mask_vin(VALID_VIN) == "2C3CDZ*******1234"
    assert mask_vin(None) is None


async def test_plan_limit_basic_allows_one_vehicle(client, db):
    u = await register(client)
    h = u["headers"]
    assert (await client.post("/vehicles", headers=h, json={"make": "Toyota"})).status_code == 201
    r = await client.post("/vehicles", headers=h, json={"make": "Nissan"})
    err = assert_envelope(r, 403, "plan_limit")
    assert err["details"] == {"limit": "vehicles", "max": 1, "plan": "basic"}
    # soft-deleted vehicles don't count
    vid = (await client.get("/vehicles", headers=h)).json()["items"][0]["id"]
    assert (await client.delete(f"/vehicles/{vid}", headers=h)).status_code == 204
    assert (await client.post("/vehicles", headers=h, json={"make": "Nissan"})).status_code == 201
    assert await db.fetchval("select count(*) from automind.audit_logs where action='vehicle.delete'") == 1


async def test_plan_limit_follows_subscription(client, db):
    import uuid

    u = await register(client)
    pro = await db.fetchval("select id from automind.subscription_plans where key='pro'")
    await db.execute(
        "insert into automind.subscriptions (user_id, plan_id, status, billing_period, provider, "
        "current_period_start) values ($1,$2,'active','monthly','manual',now())",
        uuid.UUID(u["user"]["id"]),
        pro,
    )
    for i in range(3):
        assert (await client.post("/vehicles", headers=u["headers"], json={"nickname": f"c{i}"})).status_code == 201
    assert_envelope(await client.post("/vehicles", headers=u["headers"], json={}), 403, "plan_limit")
    sub = (await client.get("/me/subscription", headers=u["headers"])).json()
    assert sub["plan"]["key"] == "pro" and sub["is_default"] is False


async def test_vehicle_crud_and_maintenance(client):
    u = await register(client)
    h = u["headers"]
    v = (await client.post("/vehicles", headers=h, json={"make": "Toyota", "fuel_type": "gasoline"})).json()
    r = await client.patch(f"/vehicles/{v['id']}", headers=h, json={"odometer_km": 120000, "vin": VALID_VIN})
    assert r.status_code == 200 and r.json()["odometer_km"] == 120000 and r.json()["vin_masked"]
    r = await client.post(
        f"/vehicles/{v['id']}/maintenance",
        headers=h,
        json={"service_date": "2026-10-01", "category": "oil_change", "description": "5W-30", "cost_amount": 250},
    )
    assert r.status_code == 201, r.text
    page = (await client.get(f"/vehicles/{v['id']}/maintenance", headers=h)).json()
    assert page["total"] == 1 and page["items"][0]["category"] == "oil_change"
    assert_envelope(await client.post("/vehicles", headers=h, json={"fuel_type": "plutonium"}), 422, "validation_error")
    assert (await client.delete(f"/vehicles/{v['id']}", headers=h)).status_code == 204
    assert_envelope(await client.get(f"/vehicles/{v['id']}", headers=h), 404, "not_found")


async def test_devices_and_connections(client, db):
    u = await register(client)
    h = u["headers"]
    assert_envelope(
        await client.post("/devices", headers=h, json={"name": "x", "transport": "wifi_tcp"}), 422, "validation_error"
    )
    d = await client.post(
        "/devices", headers=h, json={"name": "Vgate", "transport": "wifi_tcp", "host": "192.168.0.10", "port": 35000}
    )
    assert d.status_code == 201
    did = d.json()["id"]
    assert d.json()["is_certified"] is False
    r = await client.patch(f"/devices/{did}", headers=h, json={"name": "Vgate iCar"})
    assert r.json()["name"] == "Vgate iCar"
    now = datetime.now(UTC).isoformat()
    r = await client.post(
        "/connections",
        headers=h,
        json={
            "device_id": did,
            "data_mode": "live",
            "transport": "wifi_tcp",
            "adapter_status": "connected",
            "ecu_status": "connected",
            "attempts": 1,
            "latency_ms": 120,
            "started_at": now,
        },
    )
    assert r.status_code == 201 and r.json()["id"]
    assert await db.fetchval("select last_seen_at is not null from automind.obd_devices where id=$1", did)
    assert (await client.get("/devices", headers=h)).json()["total"] == 1
    assert (await client.delete(f"/devices/{did}", headers=h)).status_code == 204
    assert_envelope(await client.patch(f"/devices/{did}", headers=h, json={"name": "y"}), 404, "not_found")


async def test_me_patch_consents_export_and_delete(client, db):
    u = await register(client)
    h = u["headers"]
    r = await client.patch("/me", headers=h, json={"full_name": "سارة", "locale": "en", "phone": "+966500000000"})
    assert r.status_code == 200 and r.json()["full_name"] == "سارة" and r.json()["locale"] == "en"
    r = await client.post("/me/consents", headers=h, json={"purpose": "ai_processing", "document_version": "v1", "granted": True})
    assert r.status_code == 201
    await client.post("/vehicles", headers=h, json={"vin": VALID_VIN, "make": "Dodge"})
    export = (await client.get("/me/export", headers=h)).json()
    assert export["user"]["email"] == u["email"] and "password_hash" not in export["user"]
    assert export["vehicles"][0]["vin"] == VALID_VIN
    assert {c["purpose"] for c in export["consents"]} >= {"terms", "privacy_policy", "ai_processing"}
    assert export["auth_sessions"] and "refresh_token_hash" not in export["auth_sessions"][0]

    r = await client.delete("/me", headers=h)
    assert r.status_code == 202
    row = await db.fetchrow("select status from automind.users where id = $1", __import__("uuid").UUID(u["user"]["id"]))
    assert row["status"] == "pending_deletion"
    kinds = {r["kind"] for r in await db.fetch("select kind from automind.data_requests")}
    assert kinds == {"export", "delete"}
    # all refresh tokens revoked, access denied
    assert_envelope(await client.post("/auth/refresh", json={"refresh_token": u["tokens"]["refresh_token"]}), 401, "unauthorized")
    assert_envelope(await client.get("/me", headers=h), 401, "unauthorized")


async def test_plans_public_and_notifications(client, db):
    import uuid

    plans = (await client.get("/plans")).json()
    assert [p["key"] for p in plans] == ["basic", "pro", "garage_business"]
    assert plans[1]["price_monthly"] == 29.0
    u = await register(client)
    nid = await db.fetchval(
        "insert into automind.notifications (user_id, kind, title) values ($1,'x','Hello') returning id",
        uuid.UUID(u["user"]["id"]),
    )
    page = (await client.get("/notifications", headers=u["headers"])).json()
    assert page["total"] == 1 and page["items"][0]["read_at"] is None
    assert (await client.post(f"/notifications/{nid}/read", headers=u["headers"])).status_code == 204
    page = (await client.get("/notifications?unread_only=true", headers=u["headers"])).json()
    assert page["total"] == 0
