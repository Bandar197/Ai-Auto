# AutoMind AI — backend

Python package `automind`: OBD-II client, ECU simulator, recordings, diagnosis
engine, reports and the REST API (FastAPI). The API contract is
[`docs/API.md`](../docs/API.md); the database schema, RLS and seed data are the
SQL files in [`supabase/migrations`](../supabase/migrations) (single source of truth).

## API

### Run locally

```bash
cd backend
python3.13 -m venv .venv && .venv/bin/pip install -e ".[dev,llm]"

# PostgreSQL 16+: one non-superuser owner role (Supabase's `postgres` is not a superuser either)
sudo -u postgres psql -c "create role automind_owner login createrole createdb password 'automind_owner_pw'"
sudo -u postgres psql -c "create database automind owner automind_owner"
# only if the cluster already has an `automind_app` role created by someone else:
sudo -u postgres psql -c "grant automind_app to automind_owner with admin option, set true"

# apply the migrations AS the owner role, in filename order
for f in ../supabase/migrations/*.sql; do
  PGPASSWORD=automind_owner_pw psql -h localhost -U automind_owner -d automind -v ON_ERROR_STOP=1 -f "$f"; done

cp .env.example .env   # then set AUTOMIND_DATABASE_URL and generate the secrets as described inside
.venv/bin/uvicorn automind.api.main:app --reload
# → http://localhost:8000/api/v1/health   docs (non-prod): http://localhost:8000/api/v1/docs
```

Docker (build context = repository root, the image bundles `shared/`):

```bash
docker build -f backend/Dockerfile -t automind-api .
docker run --env-file backend/.env -p 8000:8000 automind-api
```

The image runs as a non-root user, defaults to `AUTOMIND_ENVIRONMENT=prod` (refuses
default secrets) and has a `HEALTHCHECK` on `/api/v1/health`.

### Configuration

All settings are environment variables with the `AUTOMIND_` prefix; every one is
documented in [`.env.example`](.env.example). The important ones:

| Variable | Purpose |
|---|---|
| `AUTOMIND_DATABASE_URL` | `postgresql+asyncpg://…` as the schema **owner** role |
| `AUTOMIND_DB_APP_ROLE` | RLS role used for user requests (`automind_app`) |
| `AUTOMIND_JWT_SECRET` / `_ALGORITHM` / `_PRIVATE_KEY` / `_PUBLIC_KEY` | access-token signing |
| `AUTOMIND_ACCESS_TOKEN_TTL_S`, `AUTOMIND_REFRESH_TOKEN_TTL_S` | 15 min / 30 days by default |
| `AUTOMIND_DATA_ENCRYPTION_KEY` | base64 32-byte AES-256-GCM key (VIN, plate, MFA secret) |
| `AUTOMIND_BLIND_INDEX_KEY` | base64 32-byte HMAC key for the VIN blind index |
| `AUTOMIND_REDIS_URL` | shared rate limiter (in-memory fallback when empty) |
| `AUTOMIND_CORS_ORIGINS` | comma-separated origins (admin dashboard) |
| `AUTOMIND_ANTHROPIC_API_KEY`, `AUTOMIND_LLM_MODEL` | optional LLM narrative (`use_llm=true`) |
| `AUTOMIND_ENVIRONMENT` | `dev` / `test` / `prod` (prod refuses dev secrets, hides `/docs`) |

### How requests reach the database

* **System work** (register, login, refresh, logout, admin aggregates, workers) runs on
  the owner connection (`Database.system()`), which bypasses RLS.
* **Every user request** runs in one transaction that first executes
  `select set_config('app.user_id', '<uuid>', true); set local role automind_app;`
  (`Database.user(user_id)`), so PostgreSQL Row Level Security does tenant isolation.
  Ids sent by clients (vehicle, device, connection, recording) are looked up on that
  connection first, so an invisible id is a 404 and can never be linked to another
  tenant's row (FK checks alone would bypass RLS).
* `INSERT … RETURNING` is avoided for `diagnostic_sessions` and `audit_logs`: their
  SELECT policies cannot see the row being inserted / are staff-only.

### Security notes

* Passwords: Argon2id (re-hashed on login when parameters change); policy ≥ 10 chars,
  not the e-mail, not in a common-password list. 5 failures → 15 min lock.
* Access JWT claims `sub, role, mfa, iat, exp, jti, typ=access`. Refresh tokens are
  opaque, stored as SHA-256, rotated on every use; re-use of a rotated token revokes the
  whole family and is audited (`auth.refresh_reuse_detected`).
* Admins/super-admins need MFA enrolled **and** an access token obtained with a TOTP
  code (`mfa=true`) → otherwise `403 mfa_required`. Support staff: read-only admin access.
* VINs: AES-256-GCM (AAD = vehicle id) + HMAC blind index; responses carry `vin_masked`;
  `?reveal_vin=true` is owner-only and audited. VINs inside uploaded recordings are masked
  before storage.
* Every response has `X-Request-ID`, security headers and the error envelope
  `{"error": {"code", "message", "details"}}` (validation errors never echo input).
* Rate limits: 10/min/IP on `/auth/*`, 120/min/user elsewhere → `429 rate_limited`.
* AutoMind Control: the server authorises (`automind/control/policy.py`, pure), the phone
  executes and reports back. Prohibited procedures are always rejected; `demo`/`replay`
  approvals are `simulated: true` with `commands: []` (only `simulated_commands`). Every
  request/result is stored in `control_operations` and `audit_logs`.

### Error codes beyond the shared list

`payload_too_large` (413, recordings ≥ 1 MB), `method_not_allowed` (405),
`upstream_unavailable` (503, demo simulator failure), `server_error` (500),
`not_ready` (503, `/health/ready`). Lockout is `401 unauthorized` with
`details.reason = "account_locked"` and `details.retry_after_s`.

### Contract clarifications (implemented behaviour)

* `GET /sessions/{id}/telemetry`: `t` is milliseconds since the session's `started_at`.
* `POST /recordings/{id}/replay` and `POST /demo/run` return **201** (they create a session).
* `GET /kb/dtc?q=` returns the standard page envelope.
* `GET /sessions/{id}/report?format=json` = `{format, generated_at, meta, diagnosis, data_mode}`.
* `GET /me/subscription` = `{subscription | null, plan, is_default}`.
* `GET /admin/stats/top-dtcs` counts **live** sessions only (simulated data excluded);
  `sessions_by_mode` covers the current calendar month (UTC); `users_active_30d` = login or
  token refresh in the last 30 days.
* Manual measurements are stored in `diagnostic_sessions.summary.measurements`; the latest
  full `diagnosis_result` in `summary.latest_diagnosis` (so `GET …/diagnosis` round-trips exactly).

### TODO / future work

* Plan limits: only `vehicles` is enforced (`403 plan_limit`). Not yet enforced:
  `scans_per_month`, `live_signals`, `recording_retention_days`, `ai_requests_per_month`,
  feature flags (`recordings`, `replay`, `ai_analysis`, …).
* Recordings ≥ 1 MB → object storage (Supabase Storage) instead of `413`.
* TOTP replay protection (remember the last used time step), MFA disable/recovery codes.
* Data-deletion worker for `pending_deletion` accounts; e-mail verification.

### Tests

```bash
.venv/bin/pytest tests/api            # API tests against a real PostgreSQL
.venv/bin/pytest                      # whole backend suite
```

`tests/conftest.py` creates a fresh database from the migrations for each test run,
**as a non-superuser role**. Configure it with `AUTOMIND_TEST_DATABASE_URL`
(default `postgresql+asyncpg://automind_owner:automind_owner_pw@localhost:5432/automind_test`).
If that DSN's role is a superuser (e.g. `postgres/postgres` in CI), the fixture creates
the non-superuser role `automind_test_owner` and runs everything as that role. If the
server is unreachable, DB tests are skipped with a clear message.
