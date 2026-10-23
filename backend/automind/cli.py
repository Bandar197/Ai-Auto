"""AutoMind command line (Windows / macOS / Linux).

automind connect --host 192.168.0.10 --port 35000        # real ELM327 Wi-Fi
automind scan --host 192.168.0.10 --duration 90 --out session.json --report report.html
automind live --host 192.168.0.10 --pids 0C,0D,05,0B
automind simulate --scenario p0106_map_sensor --port 35000
automind demo --scenario p0171_vacuum_leak --out demo.json
automind replay session.json --speed 4
automind diagnose session.json --lang ar --report report.html
automind ble-scan
automind kb P0106
automind clear --host 192.168.0.10 --out clear_record.json    # save codes, clear with consent, re-check
automind verify clear_record.json --host 192.168.0.10         # later: did the codes come back?
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from pathlib import Path

from automind.obd.client import ObdClient
from automind.obd.transport.base import Transport


def _transport(a: argparse.Namespace) -> Transport:
    if getattr(a, "ble", None):
        from automind.obd.transport.ble import BleTransport

        return BleTransport(a.ble, notify_uuid=a.ble_notify, write_uuid=a.ble_write)
    if getattr(a, "serial", None):
        from automind.obd.transport.serial import SerialTransport

        return SerialTransport(a.serial, baudrate=a.baud)
    from automind.obd.transport.tcp import TcpTransport

    return TcpTransport(a.host, a.port, connect_timeout=a.connect_timeout)


def _add_link_args(p: argparse.ArgumentParser) -> None:
    g = p.add_argument_group("adapter link")
    g.add_argument("--host", default="192.168.0.10", help="Wi-Fi adapter IP (default 192.168.0.10)")
    g.add_argument("--port", type=int, default=35000, help="Wi-Fi adapter TCP port (default 35000)")
    g.add_argument("--connect-timeout", type=float, default=5.0)
    g.add_argument("--ble", metavar="ADDRESS", help="use a BLE adapter (address from `automind ble-scan`)")
    g.add_argument("--ble-notify", help="override notify characteristic UUID")
    g.add_argument("--ble-write", help="override write characteristic UUID")
    g.add_argument("--serial", metavar="PORT", help="use a USB/virtual COM port, e.g. COM3 or /dev/ttyUSB0")
    g.add_argument("--baud", type=int, default=38400)
    g.add_argument("--protocol", default="0", help="ELM327 protocol 0 (auto) or 1-9")
    g.add_argument("--timeout", type=float, default=2.5, help="per-command timeout (s)")


def _state_printer(adapter, ecu, msg) -> None:  # noqa: ANN001
    print(f"  [adapter: {adapter.value:<12} | vehicle ECU: {ecu.value:<11}] {msg}", flush=True)


async def _connect(a: argparse.Namespace) -> ObdClient:
    client = ObdClient(_transport(a), protocol=a.protocol, timeout=a.timeout, on_state=_state_printer)
    print(f"Connecting to {client.transport.description} …")
    rep = await client.connect(retries=3)
    print("\n== Connection report ==")
    print(f"  phone/PC ↔ adapter : {rep.adapter_status}" + (f"  ({rep.adapter_firmware})" if rep.adapter_firmware else ""))
    print(f"  adapter ↔ vehicle  : {rep.ecu_status}" + (f"  via {rep.protocol_name}" if rep.protocol_name else ""))
    if rep.battery_voltage is not None:
        print(f"  battery (ATRV)     : {rep.battery_voltage:.1f} V")
    if rep.is_simulator:
        print("  NOTE: this adapter is the AutoMind SIMULATOR → data is DEMO, not a real vehicle.")
    if rep.error_code:
        print(f"  error              : {rep.error_code} — {rep.error_message}")
    print(f"  attempts={rep.attempts} time={rep.latency_ms} ms")
    if not rep.ok:
        await client.close()
        hint = (
            "Check that this device is joined to the adapter's Wi-Fi and the IP/port are right."
            if rep.adapter_status != "connected"
            else "Adapter reachable but the car did not answer: switch the ignition ON (or start the engine) and retry."
        )
        raise SystemExit(f"\nConnection failed. {hint}")
    return client


async def cmd_connect(a: argparse.Namespace) -> None:
    c = await _connect(a)
    try:
        print(f"\nECUs: {', '.join(e for e in c.ecus if e)}   primary: {c.primary_ecu}")
        print(f"Supported service 01 PIDs ({len(c.supported_pids())}): {' '.join(sorted(c.supported_pids()))}")
        ms = await c.monitor_status()
        if ms:
            print(f"MIL: {'ON' if ms['mil_on'] else 'off'}   confirmed DTCs: {ms['dtc_count']}")
        print(f"VIN: {await c.read_vin() or 'not reported'}")
        dtcs = await c.read_all_dtcs()
        from automind.diagnosis.kb import get_kb

        kb = get_kb()
        print(f"DTCs: {len(dtcs) or 'none'}")
        for d in dtcs:
            k = kb.lookup(d.code)
            print(f"  {d.code} [{d.status}] ecu {d.ecu}: {k['en'] if k else '(not in knowledge base)'}")
    finally:
        await c.close()


async def cmd_uds_read(a: argparse.Namespace) -> None:
    """Read a non-powertrain module's fault codes over UDS (service 0x19 0x02). Read-only.

    Use this to capture real responses from a module (SRS/ABS/BCM) on your own car, so its
    CAN addresses can be validated before the app offers it. Nothing is written or cleared.
    """
    from automind.obd.uds import UdsClient, UdsError, UdsModule

    c = await _connect(a)
    try:
        req_id = int(a.request_id, 16)
        resp_id = int(a.response_id, 16) if a.response_id else (req_id + 8)
        module = UdsModule(
            key=a.module,
            name_en=a.module,
            name_ar=a.module,
            request_id=req_id,
            response_id=resp_id,
            id_bits=a.id_bits,
            safety_category=a.category,
        )
        print(f"Module '{a.module}'  request {req_id:#05x} → response {resp_id:#05x} ({a.id_bits}-bit)")
        uds = UdsClient(c.elm)
        try:
            res = await uds.read_module_dtcs(module)
        except UdsError as e:
            print(f"  UDS error: {e.code} — {e.detail}")
            print("  raw: no usable answer; the address may be wrong for this vehicle")
            return
        print(f"  request:  {res.request}")
        print(f"  raw resp: {res.response_raw!r}")
        print(f"  codes: {len(res.dtcs) or 'none'}")
        from automind.diagnosis.kb import get_kb

        kb = get_kb()
        for d in res.dtcs:
            k = kb.lookup(d.code)
            flags = ", ".join(d.flags) or "-"
            print(f"    {d.display} [{flags}] {k['en'] if k else '(not in knowledge base)'}")
    finally:
        await c.close()


async def cmd_scan(a: argparse.Namespace) -> None:
    from automind.diagnosis.engine import diagnose_async
    from automind.diagnosis.input_builder import from_recording
    from automind.recording.recorder import capture_session

    c = await _connect(a)
    try:

        def prog(step: str, kw: dict) -> None:
            print(f"  · {step} {kw if kw else ''}", flush=True)

        rec = await capture_session(c, duration_s=a.duration, include_vin=not a.no_vin, on_progress=prog)
    finally:
        await c.close()
    out = Path(a.out)
    rec.save(out)
    print(f"\nRecording saved: {out} ({rec.data_mode}, {len(rec.samples)} samples, {rec.duration_ms / 1000:.0f} s)")
    result = await diagnose_async(from_recording(rec), language=a.lang, use_llm=a.llm)
    _print_result(result, a.lang)
    _write_reports(result, rec, a)


async def cmd_live(a: argparse.Namespace) -> None:
    c = await _connect(a)
    pids = [p.strip().upper() for p in a.pids.split(",") if p.strip()]
    pids = [p for p in pids if c.is_supported(p)] or sorted(c.supported_pids() & {"0C", "0D", "05", "0B"})
    print(f"Polling {', '.join(pids)} — Ctrl+C to stop")
    try:
        while True:
            vals = {}
            for p in pids:
                try:
                    vals.update((await c.read_pid(p)).values)
                except Exception as e:  # noqa: BLE001
                    vals[p] = f"ERR {e}"
            print("  " + "  ".join(f"{k}={v}" for k, v in vals.items()), flush=True)
            await asyncio.sleep(a.interval)
    except (KeyboardInterrupt, asyncio.CancelledError):
        pass
    finally:
        await c.close()


async def cmd_simulate(a: argparse.Namespace) -> None:
    from automind.simulator.server import SimulatorConfig, serve_forever

    await serve_forever(
        SimulatorConfig(
            scenario=a.scenario,
            host=a.host,
            port=a.port,
            time_scale=a.time_scale,
            seed=a.seed,
            protocol=a.protocol,
            ignition_on=not a.ignition_off,
            engine_running=not a.engine_off,
            drop_after=a.drop_after,
            latency_ms=a.latency_ms,
            start_engine_after_clear_s=a.start_engine_after_clear,
        )
    )


async def cmd_demo(a: argparse.Namespace) -> None:
    from automind.diagnosis.engine import diagnose_async
    from automind.diagnosis.input_builder import from_recording
    from automind.simulator.runner import run_demo

    rec = await run_demo(a.scenario, duration_s=a.duration, time_scale=a.time_scale)
    rec.save(a.out)
    print(f"Demo recording saved: {a.out} ({len(rec.samples)} samples)")
    result = await diagnose_async(from_recording(rec), language=a.lang, use_llm=a.llm)
    _print_result(result, a.lang)
    _write_reports(result, rec, a)


async def cmd_replay(a: argparse.Namespace) -> None:
    from automind.diagnosis.engine import diagnose_async
    from automind.diagnosis.input_builder import from_recording
    from automind.recording.format import Recording
    from automind.recording.recorder import ReplaySource

    rec = Recording.load(a.file)
    print(f"Replaying {a.file}: originally {rec.data_mode.upper()} data, {rec.duration_ms / 1000:.0f} s, speed x{a.speed}")
    if a.speed > 0:
        last = {}
        async for s in ReplaySource(rec, speed=a.speed):
            last.update({k: v for k, v in s.values.items() if v is not None})
            if a.verbose:
                print(f"  t={s.t_ms / 1000:7.2f}s {s.pid} {s.values}")
        print("Last values:", {k: round(v, 2) for k, v in list(last.items())[:12]})
    result = await diagnose_async(from_recording(rec, data_mode="replay"), language=a.lang, use_llm=a.llm)
    _print_result(result, a.lang)
    _write_reports(result, rec, a, mode="replay")


async def cmd_diagnose(a: argparse.Namespace) -> None:
    from automind.diagnosis.engine import diagnose_async
    from automind.diagnosis.input_builder import from_recording
    from automind.recording.format import Recording

    rec = Recording.load(a.file)
    mode = "replay" if a.as_replay else None
    result = await diagnose_async(from_recording(rec, data_mode=mode), language=a.lang, use_llm=a.llm)
    _print_result(result, a.lang)
    _write_reports(result, rec, a, mode=mode)


async def cmd_ble_scan(a: argparse.Namespace) -> None:
    from automind.obd.transport.ble import scan

    for d in await scan(a.timeout):
        flag = "OBD?" if d["likely_obd"] else "    "
        print(f"{flag} {d['address']}  rssi={d['rssi']}  {d['name'] or ''}")


def cmd_kb(a: argparse.Namespace) -> None:
    from automind.diagnosis.kb import get_kb

    kb = get_kb()
    k = kb.lookup(a.code)
    if not k:
        print(f"{a.code.upper()}: not in the knowledge base (v{kb.version}). Structure: {kb.structure(a.code)}")
        return
    print(json.dumps(k, ensure_ascii=False, indent=1))


# ---------------------------------------------------------------- clear & verify
CLEAR_FORMAT = "automind.clear_record.v1"
CONSENT_EN = (
    "I understand that clearing erases the stored trouble codes and freeze-frame data and resets the "
    "readiness monitors (the vehicle may not pass an emissions inspection until it has been driven), and "
    "that clearing does not repair any fault."
)
CONSENT_AR = (
    "أفهم أن المسح يحذف أكواد الأعطال المخزنة وبيانات الإطار المجمد ويعيد ضبط مؤشرات الجاهزية "
    "(قد لا تجتاز السيارة فحص الانبعاثات حتى تتم قيادتها)، وأن المسح لا يصلح أي عطل."
)


async def _snapshot(c: ObdClient):  # noqa: ANN202
    from datetime import UTC, datetime

    from automind.diagnosis.models import InputDTC
    from automind.diagnosis.recurrence import ScanSnapshot

    dtcs = [InputDTC(code=d.code, status=d.status, ecu=d.ecu) for d in await c.read_all_dtcs()]
    readiness = await c.monitor_status() if c.is_supported("01") else None
    vals: dict = {}
    for pid in ("0C", "30", "31"):
        if c.is_supported(pid):
            try:
                vals.update((await c.read_pid(pid)).values)
            except Exception:  # noqa: BLE001,S110 - optional evidence
                pass
    return ScanSnapshot(
        taken_at=datetime.now(UTC),
        dtcs=dtcs,
        readiness=readiness or None,
        warmups_since_clear=vals.get("warmups_since_clear"),
        distance_since_clear_km=vals.get("distance_since_clear"),
        engine_running=(vals["engine_rpm"] > 300) if vals.get("engine_rpm") is not None else None,
    )


def _print_verification(v, lang: str) -> None:  # noqa: ANN001
    ar = lang == "ar"
    labels = {
        "problem_confirmed": ("REAL PROBLEM", "يوجد عطل حقيقي"),
        "likely_resolved": ("LIKELY RESOLVED", "غالبا انتهى"),
        "verifying": ("STILL VERIFYING", "التحقق مستمر"),
        "nothing_cleared": ("NOTHING TO VERIFY", "لا يوجد ما يُتحقق منه"),
    }
    label = labels[v.overall][1 if ar else 0]
    print(
        f"\n== {'نتيجة التحقق بعد المسح' if ar else 'Clear verification'}: {label} "
        f"({v.checks_after_clear} {'فحص' if ar else 'check(s)'}) =="
    )
    print(v.summary_ar if ar else v.summary_en)
    for cv in v.codes:
        flag = {True: "!!", False: "OK", None: ".."}[cv.is_real_problem]
        print(f"\n  [{flag}] {cv.title_ar if ar else cv.title_en}")
        print(f"       {cv.explanation_ar if ar else cv.explanation_en}")
        print(f"       → {cv.next_step_ar if ar else cv.next_step_en}")


def _load_clear_file(path: str) -> dict:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if data.get("format") != CLEAR_FORMAT:
        raise SystemExit(f"{path} is not an AutoMind clear record")
    return data


async def cmd_clear(a: argparse.Namespace) -> None:
    import uuid
    from datetime import UTC, datetime

    from automind.diagnosis.recurrence import ClearRecord, assess_after_clear
    from automind.obd.client import ClearAuthorization
    from automind.obd.errors import PolicyViolation

    c = await _connect(a)
    try:
        before = await _snapshot(c)
        ff = await c.read_freeze_frame()
        mode = "demo" if c.is_simulator else "live"
        codes = sorted({d.code for d in before.dtcs})
        print(f"\nCodes saved before clearing: {', '.join(codes) or 'none'}")
        if ff.get("dtc"):
            print(f"Freeze frame saved (for {ff['dtc']}): {ff['values']}")
        if not codes:
            print("Nothing to clear.")
            return
        print("\n" + CONSENT_AR + "\n" + CONSENT_EN)
        if not a.yes:
            answer = (await asyncio.to_thread(input, "Type YES / اكتب نعم to clear: ")).strip().lower()
            if answer not in ("yes", "نعم"):
                print("Cancelled — nothing was sent to the vehicle.")
                return
        auth = ClearAuthorization(operation_id=f"local-{uuid.uuid4()}", approved=True, consent_text=CONSENT_EN)
        try:
            res = await c.clear_dtcs(auth)
        except PolicyViolation as e:
            raise SystemExit(f"Not cleared: {e}") from e
        cleared_at = datetime.now(UTC)
        print(f"Service 04 sent — adapter response: {res['response']!r} ({'OK' if res['ok'] else 'NOT ACKNOWLEDGED'})")
        record = ClearRecord(cleared_at=cleared_at, before=before, operation_id=auth.operation_id, data_mode=mode)
        await asyncio.sleep(a.settle)
        first = await _snapshot(c)  # same key cycle: catches faults that are present right now
    finally:
        await c.close()
    out = {
        "format": CLEAR_FORMAT,
        "record": record.model_dump(mode="json"),
        "freeze_frame": ff,
        "checks": [first.model_dump(mode="json")],
    }
    Path(a.out).write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    audit = Path.home() / ".automind" / "audit.log"
    audit.parent.mkdir(exist_ok=True)
    with audit.open("a", encoding="utf-8") as fh:
        fh.write(
            json.dumps(
                {
                    "at": cleared_at.isoformat(),
                    "action": "clear_dtcs",
                    "operation_id": auth.operation_id,
                    "data_mode": mode,
                    "codes": codes,
                    "adapter": c.transport.description,
                }
            )
            + "\n"
        )
    print(f"Clear record saved: {a.out}  (local audit: {audit})")
    _print_verification(assess_after_clear(record, [first]), a.lang)
    print("\nNext: drive normally, then run  automind verify " + a.out)


async def cmd_verify(a: argparse.Namespace) -> None:
    from automind.diagnosis.recurrence import ClearRecord, ScanSnapshot, assess_after_clear, snapshot_from_recording
    from automind.recording.format import Recording

    data = _load_clear_file(a.record)
    record = ClearRecord.model_validate(data["record"])
    checks = [ScanSnapshot.model_validate(x) for x in data.get("checks", [])]
    if a.from_recordings:
        for f in a.from_recordings:
            checks.append(snapshot_from_recording(Recording.load(f)))
    else:
        c = await _connect(a)
        try:
            checks.append(await _snapshot(c))
        finally:
            await c.close()
    data["checks"] = [x.model_dump(mode="json") for x in checks]
    Path(a.record).write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    _print_verification(assess_after_clear(record, checks), a.lang)


# ---------------------------------------------------------------- admin bootstrap
async def cmd_create_admin(a: argparse.Namespace, settings=None) -> None:  # noqa: ANN001
    """Promote (or create) an account to platform admin and enable TOTP MFA in one step.

    Runs against AUTOMIND_DATABASE_URL with the backend's own settings (same keys as the API),
    so the encrypted MFA secret is readable by the API.
    """
    import getpass
    import uuid

    from sqlalchemy import func, insert, select, update
    from sqlalchemy.ext.asyncio import create_async_engine

    from automind.core.config import get_settings
    from automind.core.crypto import Cipher
    from automind.core.security import (
        Passwords,
        check_password_policy,
        encrypt_mfa_secret,
        new_totp_secret,
        totp_uri,
    )
    from automind.db import tables as t

    settings = settings or get_settings()
    email = a.email.strip()
    engine = create_async_engine(settings.database_url)
    try:
        async with engine.begin() as conn:
            row = (
                await conn.execute(
                    select(t.users.c.id).where(func.lower(t.users.c.email) == email.lower(), t.users.c.deleted_at.is_(None))
                )
            ).first()
            if row is None:
                pw = await asyncio.to_thread(getpass.getpass, f"No account for {email}. New password (min 10 chars): ")
                check_password_policy(pw, email)
                user_id = uuid.uuid4()
                await conn.execute(
                    insert(t.users).values(
                        id=user_id,
                        email=email,
                        password_hash=await Passwords(settings).hash(pw),
                        full_name=a.name,
                        locale="ar",
                        email_verified_at=func.now(),
                    )
                )
                print(f"Created account {email}")
            else:
                user_id = row.id
            secret = new_totp_secret()
            await conn.execute(
                update(t.users)
                .where(t.users.c.id == user_id)
                .values(
                    platform_role=a.role,
                    status="active",
                    mfa_enabled=True,
                    mfa_secret_ciphertext=encrypt_mfa_secret(Cipher(settings.data_key_bytes), user_id, secret),
                )
            )
            await conn.execute(
                insert(t.audit_logs).values(
                    action="admin.bootstrap", entity_type="user", entity_id=str(user_id), metadata={"role": a.role, "via": "cli"}
                )
            )
    finally:
        await engine.dispose()
    print(f"\n{email} is now '{a.role}' with two-factor sign-in enabled.")
    print("Add this account to an authenticator app (Google Authenticator, Microsoft Authenticator, …):")
    print(f"  secret : {secret}")
    print(f"  link   : {totp_uri(secret, email)}")
    print("Then sign in to the admin dashboard with the email, password and the 6-digit code.")


# ---------------------------------------------------------------- output helpers
def _print_result(r, lang: str) -> None:  # noqa: ANN001
    print(f"\n== Diagnosis ({r.data_mode}) — health {r.health_score}/100 [{r.health_band}] ==")
    print(r.summary.ar if lang == "ar" else r.summary.en)
    for f in r.findings:
        title = f.title_ar if lang == "ar" else f.title_en
        print(f"\n  [{f.severity} | {f.status} | conf {f.confidence:.2f}] {title}")
        for c in f.causes[:3]:
            print(f"     {c.rank}. {(c.title_ar if lang == 'ar' else c.title_en)}  ({c.likelihood:.0%})")
        if f.tests:
            t = f.tests[0]
            print(f"     → {'الاختبار التالي' if lang == 'ar' else 'next test'}: {t.title_ar if lang == 'ar' else t.title_en}")
    if r.llm:
        print("\n" + (r.llm.narrative_ar if lang == "ar" else r.llm.narrative_en))


def _write_reports(result, rec, a: argparse.Namespace, mode: str | None = None) -> None:  # noqa: ANN001
    from automind.reports import ReportMeta, render_report_html, render_report_json

    meta = ReportMeta(
        data_mode=mode or rec.data_mode,
        protocol_name=rec.source.protocol_name,
        adapter_firmware=rec.source.adapter_firmware,
        demo_scenario=rec.source.demo_scenario,
        source_recording_id=rec.recording_id if mode == "replay" else None,
        vehicle={
            "make": rec.vehicle.make,
            "model": rec.vehicle.model,
            "model_year": rec.vehicle.model_year,
            "vin_masked": (rec.vehicle.vin[:6] + "*" * 7 + rec.vehicle.vin[-4:]) if rec.vehicle.vin else None,
        },
    )
    if getattr(a, "report", None):
        Path(a.report).write_text(render_report_html(result, meta, a.lang), encoding="utf-8")
        print(f"\nHTML report: {a.report}")
    if getattr(a, "json", None):
        Path(a.json).write_text(json.dumps(render_report_json(result, meta), ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"JSON report: {a.json}")


def _add_output_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--lang", choices=["ar", "en"], default="ar")
    p.add_argument("--report", help="write an HTML report to this path")
    p.add_argument("--json", help="write a JSON report to this path")
    p.add_argument("--llm", action="store_true", help="add an AI narrative (needs ANTHROPIC_API_KEY)")


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="automind", description="AutoMind AI — OBD-II tools")
    ap.add_argument("-v", "--verbose", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("connect", help="connect to an adapter and read VIN, supported PIDs and DTCs")
    _add_link_args(p)
    p.set_defaults(fn=cmd_connect)

    p = sub.add_parser("scan", help="full scan + live capture + diagnosis + report")
    _add_link_args(p)
    p.add_argument("--duration", type=float, default=90.0, help="live capture seconds (60-120 recommended)")
    p.add_argument("--out", default="session.json")
    p.add_argument("--no-vin", action="store_true", help="do not store the VIN in the recording")
    _add_output_args(p)
    p.set_defaults(fn=cmd_scan)

    p = sub.add_parser("live", help="print live values")
    _add_link_args(p)
    p.add_argument("--pids", default="0C,0D,05,0B,10,11,04,06,07,42")
    p.add_argument("--interval", type=float, default=0.2)
    p.set_defaults(fn=cmd_live)

    p = sub.add_parser("simulate", help="run the ECU simulator as a Wi-Fi adapter (TCP)")
    p.add_argument("--scenario", default="healthy")
    p.add_argument("--host", default="127.0.0.1", help="use 0.0.0.0 to reach it from a phone on the same network")
    p.add_argument("--port", type=int, default=35000)
    p.add_argument("--protocol", default=None, help="vehicle protocol to emulate (6 CAN11, 7 CAN29, 3 ISO9141…)")
    p.add_argument("--time-scale", type=float, default=1.0)
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--ignition-off", action="store_true", help="adapter answers but the car does not")
    p.add_argument("--engine-off", action="store_true", help="ignition on, engine off")
    p.add_argument("--drop-after", type=int, default=None, help="close the connection after N commands")
    p.add_argument("--latency-ms", type=int, default=0)
    p.add_argument(
        "--start-engine-after-clear",
        type=float,
        default=None,
        metavar="S",
        help="with --engine-off: the simulated driver starts the engine S seconds after a clear",
    )
    p.set_defaults(fn=cmd_simulate)

    p = sub.add_parser("demo", help="simulate a scenario end-to-end and diagnose it")
    p.add_argument("--scenario", default="p0106_map_sensor")
    p.add_argument("--duration", type=float, default=110.0)
    p.add_argument("--time-scale", type=float, default=None)
    p.add_argument("--out", default="demo_session.json")
    _add_output_args(p)
    p.set_defaults(fn=cmd_demo)

    p = sub.add_parser("replay", help="replay a recording with its timing and re-diagnose (data_mode=replay)")
    p.add_argument("file")
    p.add_argument("--speed", type=float, default=0, help="0 = no playback, analyse only")
    _add_output_args(p)
    p.set_defaults(fn=cmd_replay)

    p = sub.add_parser("diagnose", help="diagnose a recording file")
    p.add_argument("file")
    p.add_argument("--as-replay", action="store_true")
    _add_output_args(p)
    p.set_defaults(fn=cmd_diagnose)

    p = sub.add_parser("clear", help="save codes + freeze frame, clear DTCs (service 04) with consent, re-check")
    _add_link_args(p)
    p.add_argument("--out", default="clear_record.json", help="clear record used later by `automind verify`")
    p.add_argument("--yes", action="store_true", help="skip the interactive confirmation (consent text still applies)")
    p.add_argument("--settle", type=float, default=5.0, help="seconds to wait before the immediate re-check")
    p.add_argument("--lang", choices=["ar", "en"], default="ar")
    p.set_defaults(fn=cmd_clear)

    p = sub.add_parser("verify", help="re-scan after a clear and tell whether each code came back")
    p.add_argument("record", help="file written by `automind clear`")
    _add_link_args(p)
    p.add_argument("--from-recordings", nargs="*", metavar="REC", help="use saved scan recordings instead of connecting")
    p.add_argument("--lang", choices=["ar", "en"], default="ar")
    p.set_defaults(fn=cmd_verify)

    p = sub.add_parser("create-admin", help="make an account a platform admin with two-factor sign-in")
    p.add_argument("--email", required=True)
    p.add_argument("--name", default=None)
    p.add_argument("--role", choices=["admin", "super_admin", "support"], default="super_admin")
    p.set_defaults(fn=cmd_create_admin)

    p = sub.add_parser("uds-read", help="read a non-powertrain module's codes over UDS (read-only; for SRS/ABS/BCM)")
    _add_link_args(p)
    p.add_argument("--module", default="module", help="label, e.g. srs, abs, bcm")
    p.add_argument("--request-id", required=True, help="module request CAN id in hex, e.g. 7E0 or a maker SRS id")
    p.add_argument("--response-id", help="module response CAN id in hex (default: request-id + 8)")
    p.add_argument("--id-bits", type=int, default=11, choices=(11, 29), help="CAN id length")
    p.add_argument("--category", default="other", choices=("airbag", "abs", "other"))
    p.set_defaults(fn=cmd_uds_read)

    p = sub.add_parser("ble-scan", help="list nearby BLE OBD adapters")
    p.add_argument("--timeout", type=float, default=6.0)
    p.set_defaults(fn=cmd_ble_scan)

    p = sub.add_parser("kb", help="look up a DTC in the knowledge base")
    p.add_argument("code")
    p.set_defaults(fn=cmd_kb)
    return ap


def main(argv: list[str] | None = None) -> None:
    a = build_parser().parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if a.verbose else logging.WARNING, format="%(levelname)s %(name)s: %(message)s")
    if sys.platform == "win32":
        sys.stdout.reconfigure(encoding="utf-8")  # Arabic output in Windows terminals
    res = a.fn(a)
    if asyncio.iscoroutine(res):
        try:
            asyncio.run(res)
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
