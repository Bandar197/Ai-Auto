"""Shared fixtures.

Database tests run against a REAL PostgreSQL as a NON-superuser login role
(Supabase's ``postgres`` role is not a superuser either), which proves that the
migrations and the ``set local role automind_app`` RLS path work without
superuser rights.

* ``AUTOMIND_TEST_DATABASE_URL`` (default
  ``postgresql+asyncpg://automind_owner:automind_owner_pw@localhost:5432/automind_test``)
  names the test database. The fixture drops/re-creates it (the role needs
  CREATEDB) and applies ``supabase/migrations/*.sql`` in filename order as that
  role. Without CREATEDB it falls back to dropping and re-creating the
  ``automind`` schema inside the existing database.
* If the server is unreachable the DB tests are skipped with a clear reason.

If the DSN's role IS a superuser (e.g. ``postgres`` in a CI ``postgres:17`` service),
the fixture creates the non-superuser role ``automind_test_owner`` (LOGIN CREATEDB
CREATEROLE) and runs everything as that role instead.

One-time local setup without a superuser DSN (as a superuser)::

    create role automind_owner login createrole createdb password 'automind_owner_pw';
    -- only if automind_app already exists in the cluster (created by another role):
    grant automind_app to automind_owner with admin option, set true;
"""

from __future__ import annotations

import asyncio
import os
import uuid
from collections.abc import AsyncIterator
from pathlib import Path
from urllib.parse import urlparse, urlunparse

import pytest

os.environ.setdefault("AUTOMIND_ENVIRONMENT", "test")

REPO_ROOT = Path(__file__).resolve().parents[2]
MIGRATIONS_DIR = REPO_ROOT / "supabase" / "migrations"
DEFAULT_TEST_URL = "postgresql+asyncpg://automind_owner:automind_owner_pw@localhost:5432/automind_test"
TEST_DATABASE_URL = os.environ.get("AUTOMIND_TEST_DATABASE_URL", DEFAULT_TEST_URL)

DEFAULT_PASSWORD = "Correct-Horse-Battery-9"


def _asyncpg_dsn(url: str, dbname: str | None = None) -> str:
    u = urlparse(url.replace("postgresql+asyncpg://", "postgresql://"))
    if dbname is not None:
        u = u._replace(path="/" + dbname)
    return urlunparse(u)


BOOTSTRAP_ROLE = "automind_test_owner"
BOOTSTRAP_PASSWORD = "automind_test_owner_pw"  # noqa: S105 - local/CI test credential only


def _with_credentials(url: str, user: str, password: str) -> str:
    u = urlparse(url)
    host = u.hostname or "localhost"
    netloc = f"{user}:{password}@{host}" + (f":{u.port}" if u.port else "")
    return urlunparse(u._replace(netloc=netloc))


async def _bootstrap_if_superuser(url: str) -> str:
    """CI convenience: given a superuser DSN (e.g. postgres/postgres in a postgres:17 service),
    create a NON-superuser owner role and return a DSN for it. Non-superuser DSNs are returned as is."""
    import asyncpg

    conn = await asyncpg.connect(_asyncpg_dsn(url, "postgres"), timeout=5)
    try:
        if not await conn.fetchval("select rolsuper from pg_roles where rolname = current_user"):
            return url
        exists = await conn.fetchval("select 1 from pg_roles where rolname = $1", BOOTSTRAP_ROLE)
        verb = "alter" if exists else "create"
        await conn.execute(f"{verb} role {BOOTSTRAP_ROLE} login createdb createrole nosuperuser password '{BOOTSTRAP_PASSWORD}'")
        if await conn.fetchval("select 1 from pg_roles where rolname = 'automind_app'"):
            await conn.execute(f"grant automind_app to {BOOTSTRAP_ROLE} with admin option, set true")
        dbname = urlparse(url).path.lstrip("/")
        await conn.execute(f'drop database if exists "{dbname}" with (force)')
    finally:
        await conn.close()
    return _with_credentials(url, BOOTSTRAP_ROLE, BOOTSTRAP_PASSWORD)


async def _prepare_database(url: str) -> str:
    import asyncpg

    url = await _bootstrap_if_superuser(url)
    dbname = urlparse(url).path.lstrip("/")
    recreated = False
    try:
        admin = await asyncpg.connect(_asyncpg_dsn(url, "postgres"), timeout=5)
        try:
            await admin.execute(f'drop database if exists "{dbname}" with (force)')
            await admin.execute(f'create database "{dbname}"')
            recreated = True
        finally:
            await admin.close()
    except (asyncpg.InsufficientPrivilegeError, asyncpg.InvalidCatalogNameError):
        recreated = False
    conn = await asyncpg.connect(_asyncpg_dsn(url), timeout=5)
    try:
        if await conn.fetchval("select rolsuper from pg_roles where rolname = current_user"):
            raise RuntimeError("tests must run as a NON-superuser role (see tests/conftest.py)")
        if not recreated:
            await conn.execute("drop schema if exists automind cascade")
        for f in sorted(MIGRATIONS_DIR.glob("*.sql")):
            try:
                await conn.execute(f.read_text(encoding="utf-8"))
            except Exception as exc:  # pragma: no cover - surfaced as a hard failure
                raise RuntimeError(f"migration {f.name} failed as non-superuser: {exc!r}") from exc
    finally:
        await conn.close()
    return url


@pytest.fixture(scope="session")
def database_url() -> str:
    try:
        return asyncio.run(_prepare_database(TEST_DATABASE_URL))
    except (OSError, ConnectionError) as exc:
        pytest.skip(f"PostgreSQL not reachable at {TEST_DATABASE_URL}: {exc}")
    except Exception as exc:
        if type(exc).__name__ in ("InvalidPasswordError", "InvalidAuthorizationSpecificationError"):
            pytest.skip(f"cannot log in to test PostgreSQL: {exc}")
        raise


def make_settings(database_url: str, **overrides):
    from automind.core.config import Settings

    base = dict(
        environment="test",
        database_url=database_url,
        db_null_pool=True,
        argon2_time_cost=1,
        argon2_memory_kib=8192,
        argon2_parallelism=1,
        rate_limit_auth_per_min=100_000,
        rate_limit_user_per_min=100_000,
        log_json=False,
        redis_url=None,
        anthropic_api_key=None,
        demo_time_scale=20,
    )
    base.update(overrides)
    return Settings(**base)


@pytest.fixture
def settings(database_url):
    return make_settings(database_url)


@pytest.fixture
async def app(settings):
    from automind.api.main import create_app

    application = create_app(settings)
    async with application.router.lifespan_context(application):
        yield application


@pytest.fixture
async def client(app) -> AsyncIterator:
    import httpx

    transport = httpx.ASGITransport(app=app, client=("127.0.0.1", 50000))
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver/api/v1") as c:
        yield c


@pytest.fixture
async def db(database_url) -> AsyncIterator:
    """Raw asyncpg connection as the (non-superuser) owner, for seeding/inspection."""
    import asyncpg

    conn = await asyncpg.connect(_asyncpg_dsn(database_url))
    try:
        yield conn
    finally:
        await conn.close()


TRUNCATE_SQL = """
truncate automind.users, automind.organizations, automind.audit_logs, automind.system_errors,
         automind.procedure_allowlist, automind.payments, automind.telemetry_recordings,
         automind.parts, automind.subscription_plans, automind.service_procedures,
         automind.manufacturer_packs restart identity cascade
"""


def _seed_sql() -> str:
    seeds = sorted(MIGRATIONS_DIR.glob("*seed*.sql"))
    return "\n".join(f.read_text(encoding="utf-8") for f in seeds)


@pytest.fixture
async def clean_db(db):
    """Empty every tenant table and restore reference data (plans, procedures) from the seed migration."""
    async with db.transaction():
        await db.execute(TRUNCATE_SQL)
        await db.execute(_seed_sql())
    yield


# ----------------------------------------------------------------------------- helpers
def unique_email(prefix: str = "user") -> str:
    return f"{prefix}-{uuid.uuid4().hex[:10]}@example.com"


async def register(client, email: str | None = None, password: str = DEFAULT_PASSWORD, **extra) -> dict:
    email = email or unique_email()
    body = {"email": email, "password": password, "accept_terms_version": "2026-10", "accept_privacy_version": "2026-10", **extra}
    r = await client.post("/auth/register", json=body)
    assert r.status_code == 201, r.text
    data = r.json()
    data["email"] = email
    data["password"] = password
    data["headers"] = {"Authorization": f"Bearer {data['tokens']['access_token']}"}
    return data


def auth(tokens_or_access: dict | str) -> dict:
    token = tokens_or_access if isinstance(tokens_or_access, str) else tokens_or_access["access_token"]
    return {"Authorization": f"Bearer {token}"}
