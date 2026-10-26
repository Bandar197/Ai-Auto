# AutoMind AI — أوتومايند

منصة ذكية لتشخيص السيارات عبر OBD-II والذكاء الاصطناعي، موجهة للسوق السعودي أولا.
An OBD-II + AI vehicle diagnostics platform, built for the Saudi market first.

> **Status / الحالة:** Phase 1 (MVP) — see [docs/ROADMAP.md](docs/ROADMAP.md) for exactly what is done, tested, and pending.

## المكونات / Components

| Folder | What | Stack |
|---|---|---|
| `backend/` | OBD engine, ECU simulator, recorder/replay, diagnosis engine, reports, REST API, CLI | Python 3.12+, FastAPI, SQLAlchemy, asyncpg |
| `mobile/` | iOS/Android app (Live · Demo · Replay), Arabic RTL + English | Flutter / Dart |
| `web/` | Admin dashboard | Next.js 16, TypeScript, Tailwind, Recharts |
| `supabase/migrations/` | PostgreSQL schema `automind` (47 tables, RLS, partitions, seed) | PostgreSQL 17 on Supabase |
| `shared/` | Single source for both engines: PID table, protocols, recording schema, demo scenarios, DTC knowledge base (530 codes, ar/en) | JSON |
| `docs/` | Architecture, database, API contract, security & privacy, roadmap, Windows guide | |

## ابدأ بسرعة / Quick start

```bash
cd backend && python -m venv .venv && . .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -e ".[dev]"

automind demo --scenario p0106_map_sensor --report demo.html --lang ar      # simulator → client → diagnosis
automind simulate --scenario p0171_vacuum_leak --port 35000                 # fake Wi-Fi adapter
automind connect --host 192.168.0.10 --port 35000                           # your real ELM327 Wi-Fi
automind scan --host 192.168.0.10 --duration 90 --out car.json --report car.html
pytest -q                                                                   # unit + integration tests
```

Full stack locally: `cp .env.example .env` (fill the secrets) then `docker compose up --build` → API on :8000, admin on :3000, simulator on :35000.

* Windows + real car: **[docs/GETTING_STARTED_WINDOWS.md](docs/GETTING_STARTED_WINDOWS.md)**
* Architecture: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · Database: [docs/DATABASE.md](docs/DATABASE.md) · API: [docs/API.md](docs/API.md) · Security: [docs/SECURITY_PRIVACY.md](docs/SECURITY_PRIVACY.md)
* Mobile: [mobile/README.md](mobile/README.md) · Admin: [web/README.md](web/README.md) · Backend: [backend/README.md](backend/README.md)

## مبادئ / Principles

* اتصال حقيقي بجهاز ELM327 (Wi-Fi/BLE/USB) — لا بيانات وهمية في الوضع الحي. البيانات التجريبية معلّمة دائما ولا يمكن حفظها كبيانات حقيقية.
  Real adapter communication; demo data is always labelled and cannot be stored as live.
* التشخيص يفصل القراءات الفعلية عن الاستنتاجات، ولا يجزم بعطل من الكود وحده، ويطلب اختبار تأكيد قبل أي قطعة.
  Diagnosis separates measurements from inferences, never concludes from a code alone, and requires a confirming test before any part.
* لا أوامر غير موثقة على سيارة حقيقية؛ الوظائف الخطرة معطلة افتراضيا والمحظورة (العداد، الانبعاثات، مانع التشغيل) لا يمكن تفعيلها.
  No undocumented commands; dangerous functions are off by default and prohibited ones cannot be enabled.
