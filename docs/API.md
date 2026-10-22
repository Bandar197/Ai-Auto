# AutoMind AI — REST API contract (v1)

Base URL: `/api/v1`. JSON everywhere (UTF-8). Times are ISO-8601 UTC.
This document is the contract between the backend (`backend/`), the mobile app
(`mobile/`) and the admin dashboard (`web/`). Change it first, then the code.

## Conventions

* **Auth**: `Authorization: Bearer <access_token>` (JWT HS256/RS256, 15 min).
  Refresh tokens are opaque, 30 days, **rotated on every use**; re-use of a
  rotated token revokes the whole family.
* **Errors**: `{"error": {"code": "string", "message": "human text", "details": {}}}`
  with a meaningful HTTP status. Codes used across clients: `validation_error`,
  `unauthorized`, `forbidden`, `not_found`, `conflict`, `rate_limited`,
  `mfa_required`, `policy_rejected`, `plan_limit`.
* **Pagination**: `?limit=` (default 20, max 100) and `?offset=`. Responses:
  `{"items": [...], "total": n, "limit": l, "offset": o}`.
* **Request id**: every response carries `X-Request-ID` (echoed if supplied).
* **Rate limits**: auth endpoints 10/min/IP, others 120/min/user (Redis; in-memory fallback).
* **data_mode** is one of `live | demo | replay` and is returned on every
  session/report. Clients must label demo and replay data visibly.

## Health

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | liveness `{status:"ok", version}` |
| GET | `/health/ready` | checks DB (+ Redis if configured) |

## Auth & account

| Method | Path | Body → Response |
|---|---|---|
| POST | `/auth/register` | `{email, password, full_name?, locale?: "ar"|"en", accept_terms_version, accept_privacy_version}` → 201 `{user, tokens}` |
| POST | `/auth/login` | `{email, password, totp_code?}` → `{user, tokens}`; 403 `mfa_required` when an admin/staff account has MFA enabled and no code was sent |
| POST | `/auth/refresh` | `{refresh_token}` → `{tokens}` |
| POST | `/auth/logout` | `{refresh_token}` → 204 |
| POST | `/auth/mfa/setup` | → `{secret, otpauth_uri}` (TOTP, RFC 6238) |
| POST | `/auth/mfa/enable` | `{code}` → 204 |
| GET | `/me` | → `user` |
| PATCH | `/me` | `{full_name?, phone?, locale?}` → `user` |
| POST | `/me/consents` | `{purpose, document_version, granted}` → 201 |
| GET | `/me/export` | → JSON archive of all the user's data (PDPL right of access) |
| DELETE | `/me` | → 202; account set to `pending_deletion`, data erased by worker |

`tokens = {access_token, refresh_token, token_type: "bearer", expires_in}`
`user = {id, email, full_name, phone, locale, platform_role, mfa_enabled, created_at}`

Password policy: ≥ 10 chars, not equal to email, checked against a small
common-password list. Hashing: Argon2id. 5 failed logins → 15 min lock.

## Vehicles, devices, connections

| Method | Path | Notes |
|---|---|---|
| GET/POST | `/vehicles` | POST `{vin?, make?, model?, model_year?, engine?, fuel_type?, transmission?, nickname?, plate?, odometer_km?}` |
| GET/PATCH/DELETE | `/vehicles/{id}` | soft delete |
| GET/POST | `/vehicles/{id}/maintenance` | maintenance records |

Vehicle response: `{id, make, model, model_year, engine, fuel_type, transmission, nickname, odometer_km, vin_masked, vin_wmi, created_at}`.
The VIN is stored encrypted (AES-256-GCM) with an HMAC blind index. `vin_masked`
looks like `2C3CDZ*******1234`. `GET /vehicles/{id}?reveal_vin=true` returns
`vin` to the owner only (audited).

| Method | Path | Notes |
|---|---|---|
| GET/POST | `/devices` | `{name, transport: wifi_tcp|ble|usb_serial, host?, port?, ble_device_id?, ble_service_uuid?, ble_notify_uuid?, ble_write_uuid?, firmware_version?}` |
| PATCH/DELETE | `/devices/{id}` | |
| POST | `/connections` | Log one connection attempt: `{device_id?, vehicle_id?, data_mode, transport, adapter_status, ecu_status, protocol_code?, protocol_name?, adapter_firmware?, attempts, latency_ms?, error_code?, error_message?, app_platform?, app_version?, started_at, ended_at?}` → 201 `{id}` |

`adapter_status ∈ connected|unreachable|timeout|rejected|error`,
`ecu_status ∈ connected|no_response|bus_error|not_attempted|error`.

## Diagnostic sessions

| Method | Path | Body → Response |
|---|---|---|
| POST | `/sessions` | `{data_mode, vehicle_id?, device_id?, connection_id?, demo_scenario_key?, source_recording_id?, protocol_name?, app_platform?, app_version?}` → 201 `session` |
| GET | `/sessions` | `?vehicle_id=&data_mode=` → page of `session` |
| GET | `/sessions/{id}` | → `session` |
| POST | `/sessions/{id}/dtcs` | `{dtcs: [{code, status: stored|pending|permanent, source_service: "03"|"07"|"0A", ecu_address?, freeze_frame?}]}` → 204 |
| POST | `/sessions/{id}/telemetry` | `{samples: [{ts, pid, signal, value, unit?, ecu_address?}]}` (≤ 5000/call) → `{accepted}` |
| POST | `/sessions/{id}/recording` | body = recording v1 (see `shared/schemas/recording.v1.schema.json`) → 201 `recording_meta`. DTCs/telemetry are derived from it when not uploaded separately. |
| POST | `/sessions/{id}/measurements` | `{measurements: [{key, value, unit, note?}]}` — manual readings (e.g. A/C pressures) → 204 |
| POST | `/sessions/{id}/complete` | `{mil_on?, odometer_km?, readiness?: {mil_on, dtc_count, ignition, monitors: {name: {available, complete}}}, language?: "ar"|"en", use_llm?: bool}` → `diagnosis_result`; sets status `completed`, health score, findings, evidence. `readiness` (service 01 PID 01) is stored for clear-and-verify. |
| POST | `/sessions/{id}/diagnose` | `{language?, use_llm?}` → `diagnosis_result` (re-run, keeps history) |
| GET | `/sessions/{id}/diagnosis` | latest `diagnosis_result` |
| GET | `/sessions/{id}/telemetry` | `?signals=engine_rpm,map_kpa` → `{series: {signal: [{t, v}]}, units: {...}}` |
| GET | `/sessions/{id}/report` | `?format=json|html&lang=ar|en` → report |
| POST | `/sessions/{id}/shares` | `{organization_id, include_vin?, include_live_data?, consent_version, expires_in_days?}` → share (only owner) |
| DELETE | `/sessions/{id}/shares/{share_id}` | revoke |

`session = {id, data_mode, status, vehicle_id, device_id, demo_scenario_key, source_recording_id, protocol_name, mil_on, dtc_count, health_score, started_at, completed_at, engine_version, kb_version}`

## Recordings & replay

| Method | Path | Notes |
|---|---|---|
| POST | `/recordings` | body = recording v1 → 201 `recording_meta` (`{id, data_mode, duration_ms, sample_count, signals, created_at}`) |
| GET | `/recordings` | page of `recording_meta` |
| GET | `/recordings/{id}` | full recording v1 JSON |
| POST | `/recordings/{id}/replay` | `{language?, use_llm?}` → `{session, diagnosis}`; creates a `data_mode = replay` session linked to the recording |

## Stateless analysis & demo

| Method | Path | Notes |
|---|---|---|
| POST | `/diagnosis/analyze` | body `{recording: <v1>, language?, use_llm?}` → `diagnosis_result` (nothing stored; requires auth) |
| GET | `/demo/scenarios` | → `[{key, name_en, name_ar, description_en, description_ar, dtcs}]` |
| POST | `/demo/run` | `{scenario_key, duration_s?: 30..300, language?}` → `{session, diagnosis}` — runs the ECU simulator server-side through the real OBD client, stores a `demo` session |

## Knowledge base

| Method | Path | Notes |
|---|---|---|
| GET | `/kb/dtc/{code}` | → `{code, system, description_en, description_ar, severity, is_generic, common_causes?: [...], source}` ; 404 when unknown (never invented) |
| GET | `/kb/dtc` | `?q=` search |
| GET | `/kb/pids` | the shared PID table |

## Clear and verify

Owners clear a warning light and watch whether it comes back. The platform makes that a verdict:
the codes + freeze frame are saved in a session **before** clearing (a live clear without `session_id`
is rejected with 422), and every later scan of the same vehicle is compared with them.

| Method | Path | Notes |
|---|---|---|
| GET | `/vehicles/{id}/clear-verification` | for the latest successful `clear_dtcs` operation of the vehicle → `clear_verification` (404 when none) |
| POST | `/diagnosis/clear-verification` | stateless: `{record: {cleared_at, before: snapshot, data_mode?}, checks: [snapshot]}` → `clear_verification` |

`snapshot = {taken_at, dtcs: [{code, status, ecu?}], readiness?, warmups_since_clear?, distance_since_clear_km?, engine_running?}`

`clear_verification = {overall: problem_confirmed|likely_resolved|verifying|nothing_cleared, data_mode, cleared_at, checks_after_clear, summary_en, summary_ar, codes: [{code, ecu, family, verdict, is_real_problem, monitor, monitor_complete, returned_in_check, title_en/ar, explanation_en/ar, next_step_en/ar}]}`

`verdict ∈ returned_immediately | returned_confirmed | returned_pending | new_code | still_permanent | not_returned_verified | not_returned_yet`.
Powertrain codes count as verified only when their readiness monitor (or, for circuit codes, the comprehensive
component monitor plus a warm-up/drive) has run since the clear. Airbag (B) and network (U) codes are self-tested at
each ignition-on, so two key cycles without the code verify them. Permanent codes (0A) alone are not a return.

## AutoMind Control

The phone holds the OBD connection, so the **server authorises** and the
**device executes**, then reports back.

| Method | Path | Notes |
|---|---|---|
| GET | `/control/procedures` | `?vehicle_id=&device_id=` → `[{key, level, name_en, name_ar, risk_level, safety_category, available: bool, reason_en?, reason_ar?, preconditions}]` |
| POST | `/control/operations` | `{procedure_key, vehicle_id?, session_id?, device_id?, data_mode, consent_text, confirmed: true, conditions: {engine_running: bool, vehicle_speed_kmh: number}}` → 201 `{id, status: "approved"|"rejected_policy", reason?, commands?: ["04"]}` |
| PATCH | `/control/operations/{id}` | `{status: succeeded|failed, request_frames, response_frames, result?}` → 204 |

`conditions` may also carry `active_faults` (int) and `repair_confirmed` (bool) — required by `clear_srs_dtcs`.

Policy: prohibited procedures are always rejected; `clear_srs_dtcs` (stored airbag codes) is refused while any SRS fault is active or the repair is not confirmed, and for live vehicles needs a validated allow-list entry (manufacturer pack + certified adapter); anything not
`enabled_by_default` needs an active allow-list match (vehicle/ECU/device,
certified device); `clear_dtcs` requires engine off and speed 0. Every request
and result is written to `audit_logs`. In `demo`/`replay` mode no command ever
reaches a real vehicle.

## Commerce & notifications

| Method | Path | Notes |
|---|---|---|
| GET | `/plans` | active plans |
| GET | `/me/subscription` | current subscription + plan (defaults to Basic) |
| GET | `/notifications` | page |
| POST | `/notifications/{id}/read` | 204 |

## Admin (platform staff; admins must have MFA)

| Method | Path | Response |
|---|---|---|
| GET | `/admin/stats/overview` | `{users_total, users_active_30d, vehicles_total, devices_total, sessions_today, sessions_month, sessions_by_mode: {live, demo, replay}, connection_success_rate_30d, diagnosis_confirmed_rate, active_subscriptions_by_plan: {basic, pro, garage_business}, revenue_month_sar, cancelled_subscriptions_month, workshops_total, suppliers_total, orders_month, errors_24h, ai_usage_month: {requests, input_tokens, output_tokens, cost_usd}}` |
| GET | `/admin/stats/timeseries` | `?metric=sessions|connections|signups|revenue&days=30` → `{metric, points: [{date, value, success?, failure?}]}` |
| GET | `/admin/stats/top-dtcs` | `?days=30&limit=10` → `[{code, count, description_en, description_ar}]` |
| GET | `/admin/users` | `?q=&limit=&offset=` → page of `{id, email, full_name, platform_role, status, created_at, last_login_at, vehicles, sessions}` |
| PATCH | `/admin/users/{id}` | `{status?, platform_role?}` (super_admin for role changes) |
| GET | `/admin/errors` | page of system_errors |
| GET | `/admin/audit-logs` | page of audit_logs |
| GET | `/admin/plans` / PATCH `/admin/plans/{key}` | edit prices, features, limits |
| GET | `/admin/export/{dataset}.csv` | `dataset ∈ users|sessions|connections|top-dtcs` |

## diagnosis_result

Produced by `automind.diagnosis.engine` (identical for live, demo and replay
input). Shape (see `backend/automind/diagnosis/models.py`, source of truth):

```jsonc
{
  "engine_version": "1.0.0", "kb_version": "2026.10", "data_mode": "live",
  "generated_at": "...",
  "health_score": 72, "health_band": "attention",          // good|fair|attention|critical
  "summary": {"en": "...", "ar": "..."},                     // owner-friendly
  "technician_summary": {"en": "...", "ar": "..."},
  "dtcs": [{"code": "P0106", "status": "stored", "ecu": "7E8", "description_en": "...", "description_ar": "...", "system": "powertrain", "severity": "medium", "known": true}],
  "findings": [{
    "id": "f1", "rule_id": "map_sensor_plausibility", "rule_version": "1.0.0",
    "system": "air_intake", "title_en": "...", "title_ar": "...",
    "severity": "medium", "status": "likely", "confidence": 0.74, "related_dtcs": ["P0106"],
    "causes": [{"key": "map_sensor_fault", "title_en": "...", "title_ar": "...", "likelihood": 0.62, "rank": 1, "supporting_evidence": ["e1", "e2"], "contradicting_evidence": []}],
    "evidence": [{"id": "e1", "kind": "pid_statistic", "is_measured": true, "signal": "map_kpa", "observed_value": 61.2, "unit": "kPa", "expected_min": 25, "expected_max": 45, "expected_context": "warm idle", "assessment": "abnormal", "weight": 0.8, "note_en": "...", "note_ar": "..."}],
    "tests": [{"key": "map_key_on_engine_off", "title_en": "...", "title_ar": "...", "how_en": "...", "how_ar": "...", "expected_en": "...", "expected_ar": "...", "tools": ["scan tool"]}],
    "actions": [{"title_en": "...", "title_ar": "...", "after_test": "map_key_on_engine_off"}],
    "parts_candidates": [{"name_en": "MAP sensor", "name_ar": "حساس MAP", "category": "sensors", "requires_confirmation": true, "condition_en": "Only if test X fails", "condition_ar": "..."}],
    "missing_data": [{"signal": "baro_kpa", "description_en": "...", "description_ar": "..."}]
  }],
  "system_status": [{"system": "cooling", "status": "ok|warning|fault|unknown", "note_en": "...", "note_ar": "..."}],
  "data_quality": {"signals": ["engine_rpm", "..."], "sample_count": 1200, "duration_s": 110.0, "conditions_seen": ["warm_idle", "cruise"], "warnings": []},
  "disclaimers": [{"en": "...", "ar": "..."}],
  "llm": null   // or {model, prompt_version, narrative_en, narrative_ar, input_tokens, output_tokens}
}
```
