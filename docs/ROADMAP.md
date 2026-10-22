# AutoMind AI — Delivery phases / مراحل التنفيذ

Status legend: ✅ done and tested here · 🟡 built, not yet verified on real hardware/stores · ⏳ next · 🔒 future (needs licences/partners)

## Phase 1 — MVP (current)

| Item | Status | Evidence |
|---|---|---|
| Architecture, database (47 tables, RLS, partitions, seed) on Supabase | ✅ | `docs/ARCHITECTURE.md`, `docs/DATABASE.md`; migrations applied (one hardening step pending approval) |
| Python OBD engine: TCP/BLE/serial, ELM327 layer, CAN 11/29 + ISO-TP, J1850/ISO9141/KWP, DTC 03/07/0A, freeze frame, VIN, ATRV, reconnect | ✅ (simulator) · 🟡 (real car) | `backend/tests/unit`, `tests/integration` |
| ECU simulator (TCP :35000) with 6 scenarios incl. P0106, fault injection (drop, latency, ignition off) | ✅ | `automind simulate` |
| Recording v1 (JSON schema) + replay | ✅ | test 3 |
| Diagnosis engine (11 specialised rules + generic KB rule), health score, evidence separation | ✅ | test 4, scenario tests |
| Bilingual KB: 530 generic DTCs | ✅ | `tools/validate_kb.py` |
| HTML + JSON reports (Arabic RTL / English) | ✅ | test 5 |
| Optional Claude narrative (structured output, refusal fallback) | 🟡 | tested with a mock; needs `ANTHROPIC_API_KEY` |
| FastAPI backend (auth, Argon2, JWT rotation, MFA, sessions, recordings, replay, demo, control policy, admin) | see backend report | `backend/tests/api` |
| Flutter app (Live/Demo/Replay, Arabic/English) | see mobile report | `mobile/test` |
| Admin dashboard (Next.js) | ✅ build/tests · 🟡 not yet run against the live API | `web/` |
| Docker Compose, CI | ✅ written · 🟡 CI runs on first push | `docker-compose.yml`, `.github/workflows/ci.yml` |
| **Real ELM327 test on the Dodge Challenger 2019** | ⏳ needs you | `automind connect --host 192.168.0.10 --port 35000`, then `pytest -m hardware` |

**Exit criteria before Phase 2**: hardware test passes on at least the Challenger (CAN 11/500) and one older K-line car; Android build installed and scanned a real car; API deployed with real secrets; the pending Supabase hardening applied.

## Phase 2 — Advanced AI

* Multi-sensor analysis across sessions (trend vs previous scans using `telemetry_aggregates`), vehicle health tracking.
* Service 06 (on-board monitor test results, misfire counters per cylinder) — big accuracy gain for misfire/catalyst/O2.
* A/C module with guided measurement flow in the app (rule exists; UI flow next).
* Retrieval of licensed technical information (service manuals/TSBs) into the KB; learning from confirmed repairs (`ai_diagnoses.confirmed_cause`, with consent `training_use`).
* PDF reports (render the HTML via headless Chromium).

## Phase 3 — Advanced maintenance functions 🔒

* Manufacturer Packs with licensed data (extended PIDs, ECU lists), validated per make/model/year.
* Level 2 service functions (oil reset, battery registration, throttle relearn) only on certified adapters (e.g. STN/J2534) after bench + vehicle validation and an allow-list entry.
* Level 3 active tests and Level 4 coding/adaptation only with OEM licences; safety-critical systems stay workshop-only.

## Phase 4 — Commercial platform

* Store billing (App Store / Google Play in-app subscriptions, server-side receipt validation), plan limits beyond vehicle count, notifications (push/email), admin MFA enrolment UI, production deployment, store listings.

## Phase 5 — Garage & Parts 🔒

* Workshop accounts, bookings, quotes, invoices (ZATCA e-invoicing), reviews — tables exist, API/UI next.
* Parts catalogue with licensed fitment data (VIN decoding via a catalogue provider), supplier inventory feeds, orders with mandatory diagnosis-confirmation step.

---

## بالعربية

* **المرحلة الأولى (الحالية)**: المعمارية وقاعدة البيانات ومحرك الاتصال والمحاكي والتسجيل وإعادة التشغيل ومحرك التشخيص والتقارير والخادم والتطبيق ولوحة الإدارة. المتبقي الأساسي: **اختبار حقيقي على سيارتك** بجهاز ELM327.
* **الثانية**: تحليل متعدد الجلسات، وقراءة الخدمة 06، وتقييم المكيف بخطوات موجهة، وتقارير PDF.
* **الثالثة**: وظائف صيانة متقدمة بحزم مرخصة وأجهزة معتمدة فقط.
* **الرابعة**: الاشتراكات عبر المتاجر والتنبيهات والنشر.
* **الخامسة**: الورش وقطع الغيار.
