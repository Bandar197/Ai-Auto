# Security & privacy / الأمان والخصوصية

## Controls in place

| Area | Control |
|---|---|
| Passwords | Argon2id (argon2-cffi), rehash on parameter change, policy ≥ 10 chars, lockout after 5 failures (15 min) |
| Tokens | 15-min JWT access tokens; opaque refresh tokens stored as SHA-256, rotated on every use; re-use of a rotated token revokes the whole family |
| MFA | TOTP (RFC 6238); required for platform admins before any admin endpoint |
| Authorisation | Role checks in the API **and** PostgreSQL RLS per request (`automind_app`), triggers against privilege escalation |
| Tenant isolation | per-user / per-organization policies; workshops see a customer report only through an explicit, expiring, revocable share |
| Sensitive data | VIN, plate, TOTP secret encrypted with AES-256-GCM in the application (key outside the DB); HMAC blind index for VIN lookup; VIN masked in API responses, revealed to the owner only with an audit entry |
| Audit | append-only `audit_logs` for auth events, VIN reveal, shares, control operations, admin changes, privacy requests |
| API abuse | rate limiting (Redis sliding window; in-memory fallback), request size limits, CORS allow-list, security headers, request IDs |
| Secrets | none in the mobile app or web bundle; server secrets via environment; the app talks only to the AutoMind API (the Claude key stays server-side) |
| Vehicle safety | see `docs/ARCHITECTURE.md` §5 — server-side policy, DB-enforced prohibitions, consent + engine-off checks for service 04 |

## Saudi PDPL alignment (نظام حماية البيانات الشخصية)

* **Lawful basis & consent** — consents are versioned rows (`user_consents`: terms, privacy policy, diagnostic processing, AI processing, training use, marketing, workshop sharing).
* **Purpose limitation** — vehicle data is used for diagnosis; use for model improvement requires the separate `training_use` consent; recordings carry `consent_for_training`.
* **Data minimisation** — the VIN is optional in recordings (`--no-vin` / app setting); only the WMI is stored in clear.
* **Rights** — export (`GET /me/export`) and deletion (`DELETE /me` → `data_requests`), with audit.
* **Sharing** — only with an explicit per-workshop share; expires (default 30 days) and can be revoked.
* **Retention** — telemetry partitions dropped after the retention window; recordings expire per plan.
* **Residency** — current Supabase region is `ap-south-1`. For PDPL cross-border transfer requirements, plan a KSA-region deployment before commercial launch (review with legal counsel).

## Before production (checklist)

- [ ] Generate real `AUTOMIND_JWT_SECRET`, `AUTOMIND_DATA_ENCRYPTION_KEY`, `AUTOMIND_BLIND_INDEX_KEY` and store them in the host's secret manager (key rotation plan for the data key).
- [ ] Apply the pending Supabase hardening migration (revokes).
- [ ] Create a dedicated DB login role for the API instead of `postgres` (see migration 3 header).
- [ ] Turn on Supabase PITR backups; test restore.
- [ ] Penetration test of the API and mobile app; dependency scanning in CI.
- [ ] Privacy policy and terms (Arabic + English) reviewed by counsel; set their versions in the app.
