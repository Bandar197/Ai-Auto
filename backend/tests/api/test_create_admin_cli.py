"""`automind create-admin` promotes an account and enables TOTP so the admin API accepts it."""

from __future__ import annotations

import argparse

import pyotp

from automind.cli import cmd_create_admin
from tests.conftest import DEFAULT_PASSWORD, register


async def test_create_admin_then_admin_api_works(client, db, settings, capsys):
    u = await register(client)
    email = u["user"]["email"]
    assert (await client.get("/admin/stats/overview", headers=u["headers"])).status_code == 403
    await cmd_create_admin(argparse.Namespace(email=email.upper(), name=None, role="super_admin"), settings=settings)
    out = capsys.readouterr().out
    secret = next(line.split(":", 1)[1].strip() for line in out.splitlines() if line.strip().startswith("secret"))
    r = await client.post("/auth/login", json={"email": email, "password": DEFAULT_PASSWORD})
    assert r.status_code == 403 and r.json()["error"]["code"] == "mfa_required"
    r = await client.post("/auth/login", json={"email": email, "password": DEFAULT_PASSWORD,
                                               "totp_code": pyotp.TOTP(secret).now()})
    assert r.status_code == 200, r.text
    h = {"authorization": f"Bearer {r.json()['tokens']['access_token']}"}
    assert (await client.get("/admin/stats/overview", headers=h)).status_code == 200
    row = await db.fetchrow("select action from automind.audit_logs where action='admin.bootstrap'")
    assert row is not None
