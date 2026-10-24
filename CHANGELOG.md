# Changelog — AutoMind AI

All notable changes to this project. Dates are UTC. The project keeps backward
compatibility within Phase 1 (no breaking API/schema renames).

## [Unreleased]

### Diagnostics engine & coverage
- **UDS (ISO 14229) extended diagnostics** over ELM327 (ISO-TP): read non-powertrain
  module codes (service 0x19 0x02); clearing (0x14) stays behind the server control gate.
  Write/reset/routine/security/session services are blocked in discovery.
- **Full scan by system**: standard OBD codes (services 03/07/0A across every responding
  ECU) grouped into engine / emissions / transmission / electrical / network, plus
  airbag (SRS) / ABS / body via UDS.
- **Honest read outcomes**: readSuccessCodes / readSuccessNoCodes / refused / noResponse.
  "No faults" is shown only after a genuine read; a module that didn't answer is never
  shown as healthy. The airbag shows "couldn't verify — specialist needed" when unreadable.
- **Deep module discovery**: read-only probe of the common 11-bit address band to find a
  module whose exact address isn't mapped yet (e.g. a Hyundai airbag unit), with progress.
- **Per-make module-address registry** (`shared/obd/modules.json`), all `verified:false`
  until field-validated; the scan picks the vehicle's make-specific addresses first.
- **Controller catalogue**: 459 unverified static identifiers (55 Hyundai) from the
  developer spec, browsable/searchable in-app, each labelled "unverified catalog entry".
- **DTC knowledge base** expanded 530 → 633 generic (SAE J2012 / ISO 15031-6) codes.

### AI & content
- `POST /kb/explain`: grounded fault-code explanation (Anthropic or local Ollama), with
  Google/YouTube search links and YouTube videos; falls back to the KB offline.
- In-app "Explain this code" screen with search + videos.

### Clear & verify
- Clear codes offered the moment they appear (scan result), with a "codes return if the
  fault is real" warning; clear-and-verify distinguishes real vs old (e.g. after a part
  change) using readiness monitors / ignition cycles.

### Admin console
- **ECU access-profile review** page: platform admins review unverified candidate
  profiles and record a verification decision (approved tier or rejected) with
  evidence. Separation of duties is enforced server-side (a profile can't be
  approved by its submitter); non-admin staff see an "admins only" notice.

### App & platforms
- Precise make/model/year pickers (Saudi-market catalogue) + fuel/transmission enums.
- Windows / Android release builds hardened (signing, obfuscation, no cloud backup);
  Microsoft Store (MSIX) package; HTTPS-only API from the app.

### Security & infra
- CI security scans (gitleaks, pip-audit, npm audit, osv-scanner, bandit) + Dependabot.
- Stronger tokens (iss/aud), MFA for all staff, one-time TOTP (no replay).
- Cloudflare Containers deployment setup + guide; DB on Supabase.

### Docs
- DIAGNOSTICS_COVERAGE, COMPATIBILITY_RISKS, DTC_SOURCES, DEPLOY_CLOUDFLARE,
  WINDOWS_TRUST, ANDROID_RELEASE, IOS.

### Not yet field-tested
- SRS/ABS read/clear on a real vehicle (incl. Sonata 2012); all `modules.json` addresses.
  Passing CI is a software result, not proof of a real-car connection.
