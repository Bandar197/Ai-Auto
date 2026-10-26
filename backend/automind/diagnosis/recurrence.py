"""Clear-and-verify: did a cleared trouble code come back?

Owners routinely clear the check-engine (or airbag) light and watch whether it
returns. This module turns that habit into a reliable verdict by comparing the
codes saved just before clearing with every scan taken afterwards:

* back immediately (same key cycle, no driving)  → the fault is present right now
* back as confirmed/stored later                 → real fault (intermittent or load-dependent)
* back as pending                                → detected once again → very likely real
* not back AND the vehicle's self-test for it has run since the clear
                                                 → most likely an old fault (e.g. a part was
                                                   replaced or a connector was unplugged)
* not back but the self-test has not run yet     → keep driving; not proven either way

The self-test evidence comes from the OBD-II readiness monitors (service 01
PID 01) and the "warm-ups / distance since codes cleared" PIDs (0x30 / 0x31)
for powertrain codes. Airbag (SRS, B-codes) and network (U-codes) faults are
self-tested by their module at every ignition-on, so two key cycles without
the code are the verification there.

Permanent codes (service 0A) cannot be erased by a scan tool; they leave on
their own after the self-test passes, so their presence alone is not a return.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

from automind.diagnosis.models import InputDTC

Verdict = Literal[
    "returned_immediately", "returned_confirmed", "returned_pending", "new_code",
    "still_permanent", "not_returned_verified", "not_returned_yet",
]


class ScanSnapshot(BaseModel):
    taken_at: datetime
    session_id: str | None = None
    dtcs: list[InputDTC] = Field(default_factory=list)
    # decode_monitor_status() output: {"mil_on", "dtc_count", "monitors": {name: {available, complete}}}
    readiness: dict | None = None
    warmups_since_clear: float | None = None
    distance_since_clear_km: float | None = None
    engine_running: bool | None = None


class ClearRecord(BaseModel):
    cleared_at: datetime
    before: ScanSnapshot
    operation_id: str | None = None
    data_mode: Literal["live", "demo", "replay"] = "live"


class CodeVerdict(BaseModel):
    code: str
    ecu: str | None = None
    family: Literal["powertrain", "airbag_body", "network", "chassis"]
    verdict: Verdict
    is_real_problem: bool | None  # None = not decided yet
    monitor: str | None = None
    monitor_complete: bool | None = None
    returned_in_check: int | None = None  # 1-based index of the post-clear scan where it came back
    title_en: str
    title_ar: str
    explanation_en: str
    explanation_ar: str
    next_step_en: str
    next_step_ar: str


class ClearVerification(BaseModel):
    overall: Literal["problem_confirmed", "likely_resolved", "verifying", "nothing_cleared"]
    data_mode: Literal["live", "demo", "replay"]
    cleared_at: datetime
    checks_after_clear: int
    summary_en: str
    summary_ar: str
    codes: list[CodeVerdict]


# --------------------------------------------------------------------------- monitors
_MONITOR_RANGES: list[tuple[str, list[tuple[int, int]] | None, list[str] | None]] = [
    ("misfire", [(300, 316)], None),
    ("fuel_system", [(170, 175), (87, 93)], ["P2187", "P2188", "P2189", "P2190"]),
    ("o2_sensor_heater", [(30, 64), (135, 135), (141, 141), (155, 155), (161, 161)], None),
    ("o2_sensor", [(130, 167)], ["P2195", "P2196", "P2197", "P2198", "P2270", "P2271", "P2272", "P2273"]),
    ("catalyst", [(420, 439)], None),
    ("evap_system", [(440, 457), (496, 499)], None),
    ("egr_system", [(400, 409), (486, 489)], None),
    ("secondary_air", [(410, 419)], None),
]
MONITOR_NAMES = {
    "misfire": ("misfire monitor", "مراقب الاحتراق غير المكتمل"),
    "fuel_system": ("fuel system monitor", "مراقب نظام الوقود"),
    "o2_sensor": ("oxygen sensor monitor", "مراقب حساس الأكسجين"),
    "o2_sensor_heater": ("oxygen sensor heater monitor", "مراقب سخان حساس الأكسجين"),
    "catalyst": ("catalyst monitor", "مراقب المحول الحفاز (الدبة)"),
    "evap_system": ("EVAP monitor", "مراقب نظام EVAP"),
    "egr_system": ("EGR monitor", "مراقب EGR"),
    "secondary_air": ("secondary air monitor", "مراقب الهواء الثانوي"),
    "components": ("comprehensive component monitor", "مراقب المكونات الشامل"),
}


def monitor_for(code: str) -> str | None:
    """Readiness monitor that re-tests this powertrain code (None for non-P codes)."""
    if not code.startswith("P"):
        return None
    numeric = code.startswith("P0") and code[1:].isdigit()
    num = int(code[1:]) if numeric else -1
    for name, ranges, exact in _MONITOR_RANGES:
        if exact and code in exact:
            return name
        if ranges and numeric and any(lo <= num <= hi for lo, hi in ranges):
            return name
    # circuit/sensor codes and everything else: checked continuously by the comprehensive component monitor
    return "components"


def _family(code: str) -> Literal["powertrain", "airbag_body", "network", "chassis"]:
    return {"P": "powertrain", "B": "airbag_body", "U": "network", "C": "chassis"}.get(code[:1], "powertrain")  # type: ignore[return-value]


def _status_in(snap: ScanSnapshot, code: str) -> set[str]:
    return {d.status for d in snap.dtcs if d.code == code}


def _immediate(snap: ScanSnapshot, cleared_at: datetime) -> bool:
    driven = (snap.distance_since_clear_km or 0) > 0 or (snap.warmups_since_clear or 0) > 0
    return not driven and (snap.taken_at - cleared_at).total_seconds() < 15 * 60


def _monitor_complete(snap: ScanSnapshot | None, monitor: str | None) -> bool | None:
    if not snap or not snap.readiness or not monitor:
        return None
    m = (snap.readiness.get("monitors") or {}).get(monitor)
    if m is None:
        return None
    return bool(m.get("complete")) if m.get("available", True) else None


# --------------------------------------------------------------------------- texts
def _drive_hint(monitor: str | None, family: str) -> tuple[str, str]:
    if family in ("airbag_body", "network", "chassis"):
        return ("Switch the ignition off and on at least twice (wait for the warning-lamp self-check each time), then scan again.",
                "أطفئ الإشعال وشغّله مرتين على الأقل (انتظر فحص اللمبات الذاتي في كل مرة) ثم افحص مرة أخرى.")
    if monitor in ("catalyst", "evap_system", "o2_sensor", "o2_sensor_heater", "egr_system", "secondary_air"):
        en_m, ar_m = MONITOR_NAMES[monitor]
        return (f"Drive normally for 2–3 days, including a cold start and 15+ minutes of steady 60–100 km/h, so the {en_m} can run; then scan again.",
                f"قُد السيارة بشكل طبيعي يومين إلى ثلاثة، مع تشغيل والمحرك بارد و15 دقيقة أو أكثر بسرعة ثابتة 60–100 كم/س حتى يعمل {ar_m}، ثم افحص مرة أخرى.")
    return ("Start the engine, let it reach normal temperature and drive 10–20 minutes in mixed conditions, then scan again.",
            "شغّل المحرك حتى يصل للحرارة الطبيعية وقُد 10–20 دقيقة في ظروف متنوعة، ثم افحص مرة أخرى.")


def _texts(v: Verdict, code: str, family: str, monitor: str | None, check_no: int | None) -> tuple[str, str, str, str, str, str]:
    airbag = family == "airbag_body"
    hint_en, hint_ar = _drive_hint(monitor, family)
    if v == "returned_immediately":
        return (
            f"{code} came back immediately — real fault present now",
            f"{code} رجع فورا — العطل موجود الآن",
            "The code returned in the same key cycle, without driving. The module still detects the fault, so clearing cannot fix it."
            + (" Do not assume the airbags will deploy correctly until it is repaired." if airbag else ""),
            "رجع الكود في نفس دورة التشغيل ودون قيادة، أي أن الكمبيوتر ما زال يكتشف العطل، والمسح لا يصلحه."
            + (" لا تعتمد على عمل الوسائد الهوائية حتى يتم الإصلاح." if airbag else ""),
            "Do not keep clearing it. Follow the tests in the diagnosis report for this code and repair the cause.",
            "لا تكرر المسح. اتبع اختبارات التشخيص لهذا الكود في التقرير وأصلح السبب.",
        )
    if v == "returned_confirmed":
        return (
            f"{code} came back — real fault",
            f"{code} رجع — يوجد عطل حقيقي",
            f"The code was stored again (scan #{check_no} after clearing). The fault is real but appears only under certain conditions (intermittent or load-related).",
            f"تم تخزين الكود مرة أخرى (الفحص رقم {check_no} بعد المسح). العطل حقيقي لكنه يظهر في ظروف معينة (متقطع أو مع الحمل).",
            "Have it diagnosed and repaired; the freeze frame saved before clearing shows the conditions when it happened.",
            "افحصه وأصلحه؛ الإطار المجمد المحفوظ قبل المسح يوضح الظروف التي حدث فيها.",
        )
    if v == "returned_pending":
        return (
            f"{code} detected again (pending) — very likely real",
            f"{code} اكتُشف مرة أخرى (معلق) — غالبا عطل حقيقي",
            "The module detected the fault again once; the light usually turns on if it repeats on the next drive.",
            "اكتشف الكمبيوتر العطل مرة أخرى؛ عادة تضيء اللمبة إذا تكرر في القيادة التالية.",
            "Treat it as a real fault and plan the repair; scan again after the next drive to confirm.",
            "تعامل معه كعطل حقيقي وخطط للإصلاح، وافحص بعد القيادة التالية للتأكيد.",
        )
    if v == "new_code":
        return (
            f"{code} is new since clearing",
            f"{code} كود جديد بعد المسح",
            "This code was not present before clearing; it is a separate issue that needs its own diagnosis.",
            "هذا الكود لم يكن موجودا قبل المسح، فهو مشكلة مستقلة تحتاج تشخيصا خاصا.",
            "Run a full scan with live data so the diagnosis engine can analyse it.",
            "شغّل فحصا كاملا مع البيانات الحية حتى يحلله محرك التشخيص.",
        )
    if v == "still_permanent":
        return (
            f"{code} still listed as permanent — waiting for the self-test",
            f"{code} ما زال مسجلا كدائم — بانتظار الاختبار الذاتي",
            "Permanent codes cannot be erased by a scan tool. They disappear by themselves after the vehicle re-runs its self-test and passes. On its own this is not a sign the fault is back.",
            "الأكواد الدائمة لا يمكن مسحها بجهاز الفحص، وتختفي وحدها بعد أن تعيد السيارة اختبارها الذاتي وتنجح. وجوده وحده لا يعني أن العطل رجع.",
            hint_en, hint_ar,
        )
    if v == "not_returned_verified":
        en_m = MONITOR_NAMES.get(monitor or "", ("self-test", ""))[0]
        ar_m = MONITOR_NAMES.get(monitor or "", ("", "الاختبار الذاتي"))[1]
        return (
            f"{code} did not come back — most likely an old fault",
            f"{code} لم يرجع — غالبا عطل قديم",
            ("The airbag module self-tests at every ignition-on; the code stayed away over several key cycles. Typical causes of such an old code: a connector unplugged with the ignition on, low battery voltage, or a part (e.g. steering-wheel clock spring, seat connector) replaced."
             if family == "airbag_body" else
             f"The {en_m} has run since clearing and the code did not return. Typical causes of such an old code: a part already replaced or repaired, a connector unplugged with the ignition on, or a one-off condition (e.g. low battery, loose fuel cap)."),
            ("كمبيوتر الوسائد يختبر نفسه عند كل تشغيل للإشعال، والكود لم يرجع خلال عدة دورات تشغيل. أسباب الكود القديم عادة: فصل فيش والإشعال يعمل، أو ضعف البطارية، أو تغيير قطعة مثل فحمة الدركسون (الساعة) أو فيش المقعد."
             if family == "airbag_body" else
             f"تم تشغيل {ar_m} بعد المسح ولم يرجع الكود. أسباب الكود القديم عادة: قطعة تم تغييرها أو إصلاحها، أو فصل فيش والإشعال يعمل، أو حالة عابرة (مثل ضعف البطارية أو غطاء البنزين غير محكم)."),
            "No action needed now. If the light returns later, scan again — the history is kept.",
            "لا يلزم إجراء الآن. إذا رجعت اللمبة لاحقا افحص مرة أخرى، فالسجل محفوظ.",
        )
    # not_returned_yet
    return (
        f"{code} not back yet — verification still running",
        f"{code} لم يرجع حتى الآن — التحقق مستمر",
        "The code has not returned, but the vehicle has not yet completed the self-test that would detect it, so this is not proof that it is fixed.",
        "الكود لم يرجع، لكن السيارة لم تكمل بعد الاختبار الذاتي الذي يكتشفه، لذلك هذا ليس دليلا على أنه انتهى.",
        hint_en, hint_ar,
    )


# --------------------------------------------------------------------------- main
def assess_after_clear(record: ClearRecord, after: list[ScanSnapshot]) -> ClearVerification:
    after = sorted([s for s in after if s.taken_at >= record.cleared_at], key=lambda s: s.taken_at)
    before_codes: dict[str, str | None] = {}
    for d in record.before.dtcs:
        before_codes.setdefault(d.code, d.ecu)
    last = after[-1] if after else None
    verdicts: list[CodeVerdict] = []

    for code, ecu in sorted(before_codes.items()):
        fam = _family(code)
        mon = monitor_for(code) if fam == "powertrain" else None
        verdict: Verdict | None = None
        check_no = None
        for i, snap in enumerate(after, 1):
            st = _status_in(snap, code)
            if "stored" in st:
                verdict = "returned_immediately" if i == 1 and _immediate(snap, record.cleared_at) else "returned_confirmed"
                check_no = i
                break
            if "pending" in st and verdict is None:
                verdict, check_no = "returned_pending", i
        mc = _monitor_complete(last, mon)
        if verdict is None:
            if last and "permanent" in _status_in(last, code) and len(_status_in(last, code)) == 1:
                verdict = "still_permanent"
            elif fam != "powertrain":
                verdict = "not_returned_verified" if len(after) >= 2 else "not_returned_yet"
            elif last is not None:
                driven = (last.warmups_since_clear or 0) >= 1 or (last.distance_since_clear_km or 0) >= 10
                if mon == "components":
                    ok = driven or sum(1 for s in after if s.engine_running) >= 2
                else:
                    ok = bool(mc) and driven
                verdict = "not_returned_verified" if ok else "not_returned_yet"
            else:
                verdict = "not_returned_yet"
        real = {"returned_immediately": True, "returned_confirmed": True, "returned_pending": True,
                "not_returned_verified": False}.get(verdict)
        te, ta, ee, ea, ne, na = _texts(verdict, code, fam, mon, check_no)
        verdicts.append(CodeVerdict(code=code, ecu=ecu, family=fam, verdict=verdict, is_real_problem=real, monitor=mon,
                                    monitor_complete=mc, returned_in_check=check_no, title_en=te, title_ar=ta,
                                    explanation_en=ee, explanation_ar=ea, next_step_en=ne, next_step_ar=na))

    # codes that appeared only after the clear
    seen_new: set[str] = set()
    for snap in after:
        for d in snap.dtcs:
            if d.code not in before_codes and d.code not in seen_new and d.status in ("stored", "pending"):
                seen_new.add(d.code)
                fam = _family(d.code)
                te, ta, ee, ea, ne, na = _texts("new_code", d.code, fam, None, None)
                verdicts.append(CodeVerdict(code=d.code, ecu=d.ecu, family=fam, verdict="new_code", is_real_problem=True,
                                            title_en=te, title_ar=ta, explanation_en=ee, explanation_ar=ea,
                                            next_step_en=ne, next_step_ar=na))

    if not before_codes:
        overall = "nothing_cleared"
    elif any(v.is_real_problem for v in verdicts):
        overall = "problem_confirmed"
    elif verdicts and all(v.verdict == "not_returned_verified" for v in verdicts):
        overall = "likely_resolved"
    else:
        overall = "verifying"
    real = [v.code for v in verdicts if v.is_real_problem]
    summary = {
        "problem_confirmed": (f"Real problem: {', '.join(real)} came back after clearing. Clearing the light does not fix it.",
                              f"يوجد عطل حقيقي: {'، '.join(real)} رجع بعد المسح. مسح اللمبة لا يصلحه."),
        "likely_resolved": ("No cleared code came back after the vehicle re-ran its self-tests — most likely old faults (e.g. after replacing a part).",
                            "لم يرجع أي كود بعد أن أعادت السيارة اختباراتها الذاتية — غالبا أعطال قديمة (مثلا بعد تغيير قطعة)."),
        "verifying": (f"Nothing has come back so far ({len(after)} scan(s) since clearing), but the self-tests are not complete yet — keep driving and scan again.",
                      f"لم يرجع شيء حتى الآن ({len(after)} فحص بعد المسح)، لكن الاختبارات الذاتية لم تكتمل بعد — استمر في القيادة وافحص مرة أخرى."),
        "nothing_cleared": ("There were no codes saved before clearing, so there is nothing to verify.",
                            "لم تكن هناك أكواد محفوظة قبل المسح، فلا يوجد ما يتم التحقق منه."),
    }[overall]
    if record.data_mode != "live":
        tag_en, tag_ar = ("[DEMO] ", "[تجريبي] ") if record.data_mode == "demo" else ("[REPLAY] ", "[إعادة تشغيل] ")
        summary = (tag_en + summary[0], tag_ar + summary[1])
    order = {"returned_immediately": 0, "returned_confirmed": 1, "returned_pending": 2, "new_code": 3,
             "not_returned_yet": 4, "still_permanent": 5, "not_returned_verified": 6}
    verdicts.sort(key=lambda v: (order[v.verdict], v.code))
    return ClearVerification(overall=overall, data_mode=record.data_mode, cleared_at=record.cleared_at,
                             checks_after_clear=len(after), summary_en=summary[0], summary_ar=summary[1], codes=verdicts)


def snapshot_from_recording(rec, taken_at: datetime | None = None, session_id: str | None = None) -> ScanSnapshot:  # noqa: ANN001
    """Build a post-clear (or pre-clear) snapshot from a Recording v1."""
    series = rec.series()

    def last(key: str) -> float | None:
        pts = series.get(key)
        return pts[-1][1] if pts else None

    rpm = series.get("engine_rpm") or []
    return ScanSnapshot(
        taken_at=taken_at or rec.created_at,
        session_id=session_id,
        dtcs=[InputDTC(code=d.code, status=d.status, ecu=d.ecu) for d in rec.dtcs],
        readiness=rec.readiness,
        warmups_since_clear=last("warmups_since_clear"),
        distance_since_clear_km=last("distance_since_clear"),
        engine_running=any(v > 300 for _, v in rpm) if rpm else None,
    )
