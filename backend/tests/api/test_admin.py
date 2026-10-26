"""Admin endpoints: staff only, MFA for admins, correct aggregates on seeded data, audit, CSV."""

from __future__ import annotations

import csv
import io
import uuid
from datetime import UTC, datetime, timedelta

import pyotp
import pytest

from tests.api.test_health_errors import assert_envelope
from tests.conftest import DEFAULT_PASSWORD, auth, next_totp, register

ADMIN_PATHS = [
    "/admin/stats/overview",
    "/admin/stats/timeseries?metric=sessions",
    "/admin/stats/top-dtcs",
    "/admin/users",
    "/admin/errors",
    "/admin/audit-logs",
    "/admin/plans",
    "/admin/export/users.csv",
]


async def make_staff(client, db, role: str = "admin", mfa: bool = True) -> dict:
    u = await register(client)
    await db.execute("update automind.users set platform_role = $1 where id = $2", role, uuid.UUID(u["user"]["id"]))
    if not mfa:
        r = await client.post("/auth/login", json={"email": u["email"], "password": DEFAULT_PASSWORD})
        u["headers"] = auth(r.json()["tokens"])
        return u
    secret = (await client.post("/auth/mfa/setup", headers=u["headers"])).json()["secret"]
    assert (
        await client.post("/auth/mfa/enable", headers=u["headers"], json={"code": pyotp.TOTP(secret).now()})
    ).status_code == 204
    r = await client.post(
        "/auth/login", json={"email": u["email"], "password": DEFAULT_PASSWORD, "totp_code": next_totp(secret)}
    )
    assert r.status_code == 200, r.text
    u["headers"] = auth(r.json()["tokens"])
    u["secret"] = secret
    return u


async def test_admin_forbidden_for_normal_users(client):
    u = await register(client)
    for path in ADMIN_PATHS:
        assert_envelope(await client.get(path, headers=u["headers"]), 403, "forbidden")
    assert_envelope(await client.get("/admin/users"), 401, "unauthorized")


async def test_admin_requires_mfa(client, db):
    # admin without MFA enrolled
    a = await make_staff(client, db, "admin", mfa=False)
    for path in ADMIN_PATHS:
        err = assert_envelope(await client.get(path, headers=a["headers"]), 403, "mfa_required")
    assert err["details"]["mfa_enabled"] is False
    # MFA enrolled but token obtained without TOTP (e.g. an old token) → still refused
    b = await register(client)
    await db.execute("update automind.users set platform_role='super_admin' where id=$1", uuid.UUID(b["user"]["id"]))
    secret = (await client.post("/auth/mfa/setup", headers=b["headers"])).json()["secret"]
    await client.post("/auth/mfa/enable", headers=b["headers"], json={"code": pyotp.TOTP(secret).now()})
    assert_envelope(await client.get("/admin/users", headers=b["headers"]), 403, "mfa_required")
    # login without code → mfa_required at login
    r = await client.post("/auth/login", json={"email": b["email"], "password": DEFAULT_PASSWORD})
    assert_envelope(r, 403, "mfa_required")
    # with MFA → allowed
    ok = await make_staff(client, db, "admin", mfa=True)
    for path in ADMIN_PATHS:
        r = await client.get(path, headers=ok["headers"])
        assert r.status_code == 200, (path, r.text)


async def test_support_staff_also_need_mfa(client, db):
    s = await make_staff(client, db, "support", mfa=False)
    assert_envelope(await client.get("/admin/users", headers=s["headers"]), 403, "mfa_required")


async def test_support_reads_but_cannot_write(client, db):
    s = await make_staff(client, db, "support", mfa=True)
    assert (await client.get("/admin/users", headers=s["headers"])).status_code == 200
    assert (await client.get("/admin/stats/overview", headers=s["headers"])).status_code == 200
    u = await register(client)
    assert_envelope(
        await client.patch(f"/admin/users/{u['user']['id']}", headers=s["headers"], json={"status": "suspended"}),
        403,
        "forbidden",
    )
    assert_envelope(await client.patch("/admin/plans/pro", headers=s["headers"], json={"price_monthly": 1}), 403, "forbidden")
    assert_envelope(await client.get("/admin/export/users.csv", headers=s["headers"]), 403, "forbidden")


async def _seed(db, client):
    """Deterministic data set for the overview test."""
    users = [await register(client) for _ in range(3)]
    ids = [uuid.UUID(u["user"]["id"]) for u in users]
    now = datetime.now(UTC)
    # vehicles (one soft-deleted) and devices
    for i, uid in enumerate(ids):
        await db.execute(
            "insert into automind.vehicles (owner_user_id, make, deleted_at) values ($1, 'Toyota', $2)",
            uid,
            now if i == 2 else None,
        )
        await db.execute("insert into automind.obd_devices (owner_user_id, name, transport) values ($1,'d','ble')", uid)
    # sessions: 2 live, 1 demo, 1 replay (needs a recording) — all this month
    for mode, extra in (("live", {}), ("live", {}), ("demo", {"demo_scenario_key": "healthy"})):
        await db.execute(
            "insert into automind.diagnostic_sessions (user_id, data_mode, demo_scenario_key) values ($1,$2,$3)",
            ids[0],
            mode,
            extra.get("demo_scenario_key"),
        )
    rec = await db.fetchval(
        "insert into automind.telemetry_recordings (user_id, data_mode, duration_ms, sample_count,"
        " inline_payload) values ($1,'live',0,0,'{}') returning id",
        ids[0],
    )
    sid = await db.fetchval(
        "insert into automind.diagnostic_sessions (user_id, data_mode, source_recording_id) values ($1,'replay',$2) returning id",
        ids[0],
        rec,
    )
    # connections: 3 ok, 1 adapter ok + ecu failed → 0.75
    for a, e in (("connected", "connected"),) * 3 + (("connected", "no_response"),):
        await db.execute(
            "insert into automind.vehicle_connections (user_id, data_mode, adapter_status, ecu_status) values ($1,'live',$2,$3)",
            ids[1],
            a,
            e,
        )
    # old connection (outside 30 days) ignored
    await db.execute(
        "insert into automind.vehicle_connections (user_id, data_mode, adapter_status, ecu_status, "
        "started_at) values ($1,'live','timeout','not_attempted', now() - interval '40 days')",
        ids[1],
    )
    # ai diagnoses: 4 with feedback, 1 confirmed; 1 without feedback; one LLM call with tokens
    for fb, cause, model, tin, tout in (
        ("helpful", "map_sensor_fault", "claude-opus-5-5", 1000, 200),
        ("helpful", None, None, None, None),
        ("not_helpful", None, None, None, None),
        ("not_helpful", None, None, None, None),
        (None, None, None, None, None),
    ):
        await db.execute(
            """insert into automind.ai_diagnoses (session_id, engine, engine_version, language,
            input_sha256, summary_owner, summary_technician, user_feedback, confirmed_cause, model, input_tokens,
            output_tokens, cost_usd) values ($1,'rules','1.0.0','ar','x','s','t',$2,$3,$4,$5,$6,$7)""",
            sid,
            fb,
            cause,
            model,
            tin,
            tout,
            0.008 if model else None,
        )
    # subscriptions + payments
    pro = await db.fetchval("select id from automind.subscription_plans where key='pro'")
    await db.execute(
        "insert into automind.subscriptions (user_id, plan_id, status, billing_period, provider, "
        "current_period_start) values ($1,$2,'active','monthly','manual',now())",
        ids[0],
        pro,
    )
    sub2 = await db.fetchval(
        "insert into automind.subscriptions (user_id, plan_id, status, billing_period, provider, "
        "current_period_start, cancelled_at) values ($1,$2,'cancelled','monthly','manual',now(),"
        "now()) returning id",
        ids[1],
        pro,
    )
    await db.execute(
        "insert into automind.payments (user_id, subscription_id, amount, provider, status, paid_at) "
        "values ($1,$2,29,'manual','succeeded',now()), ($1,$2,29,'manual','failed',now()), "
        "($1,$2,500,'manual','succeeded',now() - interval '70 days')",
        ids[1],
        sub2,
    )
    # workshop + supplier + order, errors
    org = await db.fetchval("insert into automind.organizations (name, kind) values ('W','workshop') returning id")
    await db.execute("insert into automind.workshops (organization_id, name_ar, city) values ($1,'ورشة','Riyadh')", org)
    org2 = await db.fetchval("insert into automind.organizations (name, kind) values ('S','supplier') returning id")
    sup = await db.fetchval("insert into automind.suppliers (organization_id, name) values ($1,'S') returning id", org2)
    await db.execute(
        "insert into automind.parts_orders (user_id, supplier_id, diagnosis_confirmation) values ($1,$2,'confirmed_by_test')",
        ids[0],
        sup,
    )
    await db.execute("insert into automind.system_errors (component, error_code) values ('api','x'), ('obd','y')")
    await db.execute(
        "insert into automind.system_errors (component, error_code, occurred_at) values ('api','old', now() - interval '3 days')"
    )
    return users


async def test_overview_counts_on_seeded_data(client, db):
    await _seed(db, client)
    admin = await make_staff(client, db, "admin")
    r = await client.get("/admin/stats/overview", headers=admin["headers"])
    assert r.status_code == 200, r.text
    o = r.json()
    assert o["users_total"] == 4  # 3 seeded + admin
    assert o["users_active_30d"] == 4  # all signed in/registered recently
    assert o["vehicles_total"] == 2 and o["devices_total"] == 3
    assert o["sessions_today"] == 4 and o["sessions_month"] == 4
    assert o["sessions_by_mode"] == {"live": 2, "demo": 1, "replay": 1}
    assert o["connection_success_rate_30d"] == 0.75
    assert o["diagnosis_confirmed_rate"] == 0.25
    assert o["active_subscriptions_by_plan"] == {"basic": 0, "pro": 1, "garage_business": 0}
    assert o["revenue_month_sar"] == 29.0
    assert o["cancelled_subscriptions_month"] == 1
    assert o["workshops_total"] == 1 and o["suppliers_total"] == 1 and o["orders_month"] == 1
    assert o["errors_24h"] == 2
    assert o["ai_usage_month"] == {"requests": 1, "input_tokens": 1000, "output_tokens": 200, "cost_usd": 0.008}


async def test_overview_ratios_null_without_data(client, db):
    admin = await make_staff(client, db, "admin")
    o = (await client.get("/admin/stats/overview", headers=admin["headers"])).json()
    assert o["connection_success_rate_30d"] is None and o["diagnosis_confirmed_rate"] is None
    assert o["revenue_month_sar"] == 0


async def test_timeseries_and_top_dtcs(client, db):
    users = await _seed(db, client)
    admin = await make_staff(client, db, "admin")
    h = admin["headers"]
    ts = (await client.get("/admin/stats/timeseries?metric=connections&days=7", headers=h)).json()
    assert ts["metric"] == "connections" and len(ts["points"]) == 7
    today = ts["points"][-1]
    assert today["date"] == datetime.now(UTC).date().isoformat()
    assert today == {"date": today["date"], "value": 4, "success": 3, "failure": 1}
    rev = (await client.get("/admin/stats/timeseries?metric=revenue&days=30", headers=h)).json()
    assert rev["points"][-1]["value"] == 29.0 and sum(p["value"] for p in rev["points"]) == 29.0
    signups = (await client.get("/admin/stats/timeseries?metric=signups&days=1", headers=h)).json()
    assert signups["points"][0]["value"] == 4
    assert_envelope(await client.get("/admin/stats/timeseries?metric=bogus", headers=h), 422, "validation_error")

    # top DTCs only count live sessions
    uid = uuid.UUID(users[0]["user"]["id"])
    live = await db.fetchval("insert into automind.diagnostic_sessions (user_id, data_mode) values ($1,'live') returning id", uid)
    live2 = await db.fetchval(
        "insert into automind.diagnostic_sessions (user_id, data_mode) values ($1,'live') returning id", uid
    )
    demo = await db.fetchval(
        "insert into automind.diagnostic_sessions (user_id, data_mode, demo_scenario_key) values ($1,'demo','x') returning id",
        uid,
    )
    for s, code in ((live, "P0106"), (live2, "P0106"), (live, "P0171"), (demo, "P0300"), (demo, "P0300"), (demo, "P0302")):
        await db.execute(
            "insert into automind.diagnostic_trouble_codes (session_id, code, status, source_service) "
            "values ($1,$2,'stored','03')",
            s,
            code,
        )
    top = (await client.get("/admin/stats/top-dtcs?days=30&limit=10", headers=h)).json()
    assert [(d["code"], d["count"]) for d in top] == [("P0106", 2), ("P0171", 1)]
    assert top[0]["description_en"]  # from the KB


async def test_admin_users_list_patch_and_audit(client, db):
    users = await _seed(db, client)
    admin = await make_staff(client, db, "admin")
    h = admin["headers"]
    page = (await client.get(f"/admin/users?q={users[0]['email'][:12]}", headers=h)).json()
    assert page["total"] == 1
    row = page["items"][0]
    assert row["vehicles"] == 1 and row["sessions"] == 4 and row["status"] == "active"
    assert (await client.get("/admin/users?q=%25", headers=h)).json()["total"] == 0  # LIKE wildcards escaped

    target = users[1]["user"]["id"]
    r = await client.patch(f"/admin/users/{target}", headers=h, json={"status": "suspended"})
    assert r.status_code == 200 and r.json()["status"] == "suspended"
    assert_envelope(
        await client.post("/auth/refresh", json={"refresh_token": users[1]["tokens"]["refresh_token"]}), 401, "unauthorized"
    )
    # admins can't change roles (super_admin only) nor themselves
    assert_envelope(await client.patch(f"/admin/users/{target}", headers=h, json={"platform_role": "admin"}), 403, "forbidden")
    assert_envelope(
        await client.patch(f"/admin/users/{admin['user']['id']}", headers=h, json={"status": "active"}), 403, "forbidden"
    )
    sup = await make_staff(client, db, "super_admin")
    r = await client.patch(f"/admin/users/{target}", headers=sup["headers"], json={"platform_role": "support"})
    assert r.status_code == 200 and r.json()["platform_role"] == "support"
    logs = (await client.get("/admin/audit-logs?action=admin.user_update", headers=h)).json()
    outcomes = sorted(i["outcome"] for i in logs["items"])
    assert outcomes == ["denied", "success", "success"]
    ok = [i for i in logs["items"] if i["outcome"] == "success"]
    assert any(i["before_state"] == {"platform_role": "user", "status": "active"} for i in ok)
    errors = (await client.get("/admin/errors?limit=2", headers=h)).json()
    assert errors["total"] == 3 and len(errors["items"]) == 2


async def test_admin_plans_patch_and_csv_export(client, db):
    await _seed(db, client)
    admin = await make_staff(client, db, "admin")
    h = admin["headers"]
    plans = (await client.get("/admin/plans", headers=h)).json()
    assert isinstance(plans, list) and {p["key"] for p in plans} == {"basic", "pro", "garage_business"}
    r = await client.patch("/admin/plans/pro", headers=h, json={"price_monthly": 35, "limits": {"vehicles": 5}})
    assert r.status_code == 200 and r.json()["price_monthly"] == 35.0 and r.json()["limits"] == {"vehicles": 5}
    assert_envelope(await client.patch("/admin/plans/pro", headers=h, json={"limits": {"vehicles": -1}}), 422, "validation_error")
    assert_envelope(await client.patch("/admin/plans/nope", headers=h, json={"active": False}), 404, "not_found")
    assert await db.fetchval("select count(*) from automind.audit_logs where action='admin.plan_update'") == 1
    # plan change is effective immediately for limits
    assert (await client.get("/plans")).json()[1]["price_monthly"] == 35.0

    await db.execute("update automind.users set full_name = '=HYPERLINK(\"x\")' where email = $1", admin["email"])
    r = await client.get("/admin/export/users.csv", headers=h)
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv")
    assert "attachment" in r.headers["content-disposition"]
    rows = list(csv.reader(io.StringIO(r.content.decode("utf-8-sig"))))
    assert rows[0][:3] == ["id", "email", "full_name"] and len(rows) == 1 + 4
    assert any(row[2].startswith("'=") for row in rows[1:])  # formula injection neutralised
    for ds in ("sessions", "connections", "top-dtcs"):
        assert (await client.get(f"/admin/export/{ds}.csv", headers=h)).status_code == 200
    assert_envelope(await client.get("/admin/export/secrets.csv", headers=h), 404, "not_found")
    assert await db.fetchval("select count(*) from automind.audit_logs where action='admin.export'") == 4


@pytest.mark.parametrize("days", [0, 400])
async def test_timeseries_validates_days(client, db, days):
    admin = await make_staff(client, db, "admin")
    assert_envelope(await client.get(f"/admin/stats/timeseries?days={days}", headers=admin["headers"]), 422, "validation_error")


async def test_session_started_yesterday_not_today(client, db):
    u = await register(client)
    admin = await make_staff(client, db, "admin")
    y = datetime.now(UTC) - timedelta(days=1, hours=1)
    await db.execute(
        "insert into automind.diagnostic_sessions (user_id, data_mode, started_at) values ($1,'live',$2)",
        uuid.UUID(u["user"]["id"]),
        y,
    )
    o = (await client.get("/admin/stats/overview", headers=admin["headers"])).json()
    assert o["sessions_today"] == 0
