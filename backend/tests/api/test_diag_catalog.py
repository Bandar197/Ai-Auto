"""Controller / profile diagnostic catalogue.

Covers the seed (459 unverified identifiers), the catalogue read endpoints, and
the admin-only, separation-of-duties profile submit/approve flow with RLS.
"""

from __future__ import annotations

from tests.api.test_admin import make_staff
from tests.api.test_health_errors import assert_envelope
from tests.conftest import register

PROTOCOL_CAN_11 = "ISO 15765-4 CAN (11 bit ID, 500 kbaud)"


def _profile_body(**overrides) -> dict:
    body = {
        "make": "Hyundai",
        "model": "Elantra",
        "year_from": 2017,
        "year_to": 2021,
        "controller_id": "hyundai_engine_controller",
        "protocol": PROTOCOL_CAN_11,
        "tx_header": "7E0",
        "rx_header": "7E8",
        "read_request": "0100",
        "id_bits": 11,
        "category": "powertrain",
        "notes": "candidate from a reported trace",
    }
    body.update(overrides)
    return body


# ----------------------------------------------------------------------------- seed
async def test_seed_imported_459_unverified(client, db):
    total = await db.fetchval("select count(*) from automind.diag_controller_catalog")
    distinct = await db.fetchval("select count(distinct id) from automind.diag_controller_catalog")
    hyundai = await db.fetchval("select count(*) from automind.diag_controller_catalog where make = 'hyundai'")
    not_unverified = await db.fetchval(
        "select count(*) from automind.diag_controller_catalog where verification_status <> 'unverified'"
    )
    assert total == 459
    assert distinct == 459
    assert hyundai == 55
    assert not_unverified == 0


async def test_manufacturers_sum_to_459(client):
    u = await register(client)
    r = await client.get("/diag/catalog/manufacturers", headers=u["headers"])
    assert r.status_code == 200, r.text
    rows = r.json()
    assert sum(row["count"] for row in rows) == 459
    assert {"make": "hyundai", "count": 55} in rows
    # sorted by make, each make unique
    makes = [row["make"] for row in rows]
    assert makes == sorted(makes) and len(makes) == len(set(makes))


async def test_manufacturers_requires_auth(client):
    assert_envelope(await client.get("/diag/catalog/manufacturers"), 401, "unauthorized")


# ----------------------------------------------------------------------------- controllers
async def test_controllers_filter_and_paginate(client):
    u = await register(client)
    h = u["headers"]
    full = (await client.get("/diag/catalog/controllers?make=bmw&limit=100", headers=h)).json()
    assert full["total"] == 32
    assert len(full["items"]) == 32
    assert all(item["make"] == "bmw" for item in full["items"])
    assert all(item["verification_status"] == "unverified" for item in full["items"])

    first = (await client.get("/diag/catalog/controllers?make=bmw&limit=10&offset=0", headers=h)).json()
    second = (await client.get("/diag/catalog/controllers?make=bmw&limit=10&offset=10", headers=h)).json()
    assert first["total"] == 32 and second["total"] == 32
    assert len(first["items"]) == 10 and len(second["items"]) == 10
    assert {i["id"] for i in first["items"]}.isdisjoint({i["id"] for i in second["items"]})


async def test_controllers_search(client):
    u = await register(client)
    r = (await client.get("/diag/catalog/controllers?q=abs&limit=100", headers=u["headers"])).json()
    assert r["total"] > 0
    assert all("abs" in (i["id"] + (i["label"] or "") + i["category"]).lower() for i in r["items"])


# ----------------------------------------------------------------------------- submit / approve
async def test_submit_defaults_unverified_and_hidden_until_approved(client, db):
    submitter = await make_staff(client, db, "admin")
    reviewer = await make_staff(client, db, "admin")
    user = await register(client)

    r = await client.post("/diag/admin/profiles", headers=submitter["headers"], json=_profile_body())
    assert r.status_code == 201, r.text
    created = r.json()
    assert created["verification_status"] == "unverified"
    assert created["version"] == 1
    assert created["submitted_by"] == submitter["user"]["id"]
    assert created["tx_header"] == "7E0" and created["rx_header"] == "7E8"
    pid = created["id"]

    # not visible to a normal user yet
    assert (await client.get("/diag/catalog/profiles?make=Hyundai", headers=user["headers"])).json() == []
    # but present in the admin pending-review queue
    pending = (await client.get("/diag/admin/profiles/pending-review", headers=reviewer["headers"])).json()
    assert [p["id"] for p in pending] == [pid]

    # a different admin approves it with evidence
    approve = await client.post(
        f"/diag/admin/profiles/{pid}/approve",
        headers=reviewer["headers"],
        json={
            "verification_status": "verified_vehicle_trace",
            "source_type": "vehicle_trace",
            "source_reference": "capture-2026-10-20 Elantra",
        },
    )
    assert approve.status_code == 200, approve.text
    approved = approve.json()
    assert approved["verification_status"] == "verified_vehicle_trace"
    assert approved["version"] == 2
    assert approved["reviewed_by"] == reviewer["user"]["id"]
    assert approved["reviewed_at"] is not None

    # now visible to the normal user and gone from the pending queue
    visible = (await client.get("/diag/catalog/profiles?make=Hyundai&year=2019", headers=user["headers"])).json()
    assert [p["id"] for p in visible] == [pid]
    assert (await client.get("/diag/admin/profiles/pending-review", headers=reviewer["headers"])).json() == []

    # audit trail written
    assert await db.fetchval("select count(*) from automind.audit_logs where action = 'diag.profile_submit'") == 1
    assert await db.fetchval(
        "select count(*) from automind.audit_logs where action = 'diag.profile_review' and outcome = 'success'"
    ) == 1


async def test_profiles_year_filter(client, db):
    submitter = await make_staff(client, db, "admin")
    reviewer = await make_staff(client, db, "admin")
    user = await register(client)
    pid = (await client.post("/diag/admin/profiles", headers=submitter["headers"], json=_profile_body())).json()["id"]
    await client.post(
        f"/diag/admin/profiles/{pid}/approve",
        headers=reviewer["headers"],
        json={"verification_status": "licensed_oem", "source_type": "oem", "source_reference": "doc-1"},
    )
    assert len((await client.get("/diag/catalog/profiles?make=Hyundai&year=2019", headers=user["headers"])).json()) == 1
    assert (await client.get("/diag/catalog/profiles?make=Hyundai&year=2025", headers=user["headers"])).json() == []


# ----------------------------------------------------------------------------- authz
async def test_non_admin_cannot_submit_or_approve(client, db):
    user = await register(client)
    assert_envelope(
        await client.post("/diag/admin/profiles", headers=user["headers"], json=_profile_body()), 403, "forbidden"
    )
    # support staff (non-admin) also cannot
    support = await make_staff(client, db, "support")
    assert_envelope(
        await client.post("/diag/admin/profiles", headers=support["headers"], json=_profile_body()), 403, "forbidden"
    )
    # create a real profile to try to approve
    submitter = await make_staff(client, db, "admin")
    pid = (await client.post("/diag/admin/profiles", headers=submitter["headers"], json=_profile_body())).json()["id"]
    assert_envelope(
        await client.post(
            f"/diag/admin/profiles/{pid}/approve",
            headers=user["headers"],
            json={"verification_status": "licensed_oem", "source_type": "oem", "source_reference": "x"},
        ),
        403,
        "forbidden",
    )
    assert_envelope(await client.get("/diag/admin/profiles/pending-review", headers=user["headers"]), 403, "forbidden")


async def test_submitter_cannot_approve_own_profile(client, db):
    submitter = await make_staff(client, db, "admin")
    pid = (await client.post("/diag/admin/profiles", headers=submitter["headers"], json=_profile_body())).json()["id"]
    r = await client.post(
        f"/diag/admin/profiles/{pid}/approve",
        headers=submitter["headers"],
        json={"verification_status": "verified_vehicle_trace", "source_type": "trace", "source_reference": "x"},
    )
    assert_envelope(r, 403, "forbidden")
    # still unverified, still pending, and the denial was audited
    pending = (await client.get("/diag/admin/profiles/pending-review", headers=submitter["headers"])).json()
    assert [p["id"] for p in pending] == [pid]
    assert pending[0]["verification_status"] == "unverified"
    assert await db.fetchval(
        "select count(*) from automind.audit_logs where action = 'diag.profile_review' and outcome = 'denied'"
    ) == 1


async def test_rls_user_cannot_see_others_unverified(client, db):
    submitter = await make_staff(client, db, "admin")
    await client.post("/diag/admin/profiles", headers=submitter["headers"], json=_profile_body(make="Kia", model="Rio"))
    other = await register(client)
    # user A sees no unverified profile submitted by admin B through the public endpoint
    assert (await client.get("/diag/catalog/profiles?make=Kia", headers=other["headers"])).json() == []
    assert (await client.get("/diag/catalog/profiles", headers=other["headers"])).json() == []


# ----------------------------------------------------------------------------- validation
async def test_submit_validation(client, db):
    admin = await make_staff(client, db, "admin")
    h = admin["headers"]
    # unknown protocol
    assert_envelope(
        await client.post("/diag/admin/profiles", headers=h, json=_profile_body(protocol="made up")), 422, "validation_error"
    )
    # non-hex header
    assert_envelope(
        await client.post("/diag/admin/profiles", headers=h, json=_profile_body(tx_header="ZZZ")), 422, "validation_error"
    )
    # header length wrong for the id width (11-bit wants 3 hex digits)
    assert_envelope(
        await client.post("/diag/admin/profiles", headers=h, json=_profile_body(tx_header="18DAF110")),
        422,
        "validation_error",
    )
    # protocol / id_bits mismatch (11-bit protocol, id_bits 29)
    assert_envelope(
        await client.post("/diag/admin/profiles", headers=h, json=_profile_body(id_bits=29, tx_header="18DAF110", rx_header="18DAF011")),
        422,
        "validation_error",
    )
    # bad make/model length and year range
    assert_envelope(
        await client.post("/diag/admin/profiles", headers=h, json=_profile_body(make="X" * 50)), 422, "validation_error"
    )
    assert_envelope(
        await client.post("/diag/admin/profiles", headers=h, json=_profile_body(year_from=2021, year_to=2017)),
        422,
        "validation_error",
    )
