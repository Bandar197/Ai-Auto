# Testing / الاختبارات

| # | Test plan item | How | Where |
|---|---|---|---|
| 1 | Real ELM327 Wi-Fi: TCP, init, protocol detection, ECU link, supported PIDs, DTCs, live data | `pytest -m hardware -s` with `AUTOMIND_HW_HOST` set (skipped otherwise) or `automind connect/scan` | `backend/tests/integration/test_hardware.py` |
| 2 | ECU simulator on a local TCP port with fault scenarios (P0106 …) | client ⇄ simulator over real sockets, CAN 11/29-bit, ISO 9141, KWP, J1850 | `tests/unit/test_elm327.py`, `tests/integration/test_pipeline.py` |
| 3 | 60–120 s session saved as JSON and replayed | schema validation, save/load identity, replay yields identical values | `test_recording_duration_and_schema`, `test_save_load_replay_identical` |
| 4 | Same diagnosis in Live / Demo / Replay | same findings, causes, confidence and input hash; only labels differ | `test_same_result_across_modes` |
| 5 | HTML + JSON reports | Arabic RTL + English, DEMO banner, refuses mode relabelling | `test_reports` |
| 6 | Security, permissions, tenant isolation, network failure | API tests against real PostgreSQL with RLS (non-superuser role); link drop + reconnect, unreachable adapter, ignition off, latency | `tests/api/*`, `test_reconnect_after_connection_drop`, … |

Also: PID/DTC/frame codec tests with byte-exact inputs, encode/decode round-trip for every linear PID, diagnosis invariants (no invented descriptions, code-only ≤ suspected, critical caps health, A/C asks for measurements), LLM layer with a fake client and failure fallback.

## Run

```bash
cd backend
pytest -q                          # everything that needs no hardware
pytest tests/unit tests/integration -q
pytest tests/api -q                # needs PostgreSQL (see backend/README.md)
python ../tools/validate_kb.py ../shared/kb/dtc_definitions.json ../shared/obd/pids.json
cd ../web && npm test && npm run build
cd ../mobile && flutter analyze && flutter test
```

## Not covered automatically (must be done by a person)

* Real vehicles (Test 1) — run on the Dodge Challenger 2019 and, ideally, one older K-line car.
* iOS build and device test (needs macOS + Xcode).
* App Store / Google Play billing.
* Live Claude API calls (needs an API key; the layer is unit-tested with a mock).
