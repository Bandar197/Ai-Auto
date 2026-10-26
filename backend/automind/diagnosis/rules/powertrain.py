"""Powertrain diagnostic rules.

Expected ranges are generic values for warm, naturally-aspirated gasoline
engines (public service-training references), NOT manufacturer specifications.
Every evidence item states the context it applies to, and findings never go
beyond 'likely' without a confirmation test.
"""

from __future__ import annotations

import re

from automind.diagnosis.features import Context
from automind.diagnosis.kb import get_kb
from automind.diagnosis.models import Finding
from automind.diagnosis.rules.base import FindingBuilder, Rule

IDLE = ("warm_idle",)
RUNNING = ("warm_idle", "cold_idle", "free_rev", "cruise", "accel", "decel", "other")
HIGH_RPM = ("free_rev", "cruise", "accel")
CTX_WARM_IDLE = "warm idle | خمول والمحرك دافئ"
CTX_RUNNING = "engine running | المحرك يعمل"
CTX_HIGH = "≥1500 rpm or cruising | دورات عالية أو سير ثابت"


def _dtc_status(ctx: Context, code: str) -> str:
    for d in ctx.inp.dtcs:
        if d.code == code:
            return d.status
    return "stored"


def _add_dtcs(fb: FindingBuilder, ctx: Context, codes: list[str]) -> list[str]:
    kb = get_kb()
    ids = []
    for c in codes:
        k = kb.lookup(c)
        ids.append(fb.ev_dtc(c, _dtc_status(ctx, c), k and k.get("en"), k and k.get("ar")))
    return ids


def _engine_liters(ctx: Context) -> float | None:
    m = re.search(r"(\d(?:\.\d)?)\s*L", ctx.inp.vehicle.engine or "", re.IGNORECASE)
    return float(m.group(1)) if m else None


def _baro(ctx: Context) -> tuple[float, bool]:
    st = ctx.stats("baro_kpa")
    if st:
        return st.mean, True
    return 101.3, False


# =============================================================================
class MapSensorRule(Rule):
    id = "map_sensor_plausibility"
    dtc_triggers = ("P0105", "P0106", "P0107", "P0108", "P0109")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        idle = ctx.stats("map_kpa", IDLE)
        baro, baro_measured = _baro(ctx)
        idle_abnormal_hint = bool(idle and idle.n >= 10 and idle.mean > baro * 0.55)
        if not codes and not idle_abnormal_hint:
            return None
        fb = FindingBuilder(
            fid, self, system="air_intake", severity="medium", related_dtcs=codes,
            title_en="Manifold absolute pressure (MAP) reading implausible",
            title_ar="قراءة حساس ضغط مجمع السحب (MAP) غير منطقية",
        )
        dtc_ids = _add_dtcs(fb, ctx, codes)
        circuit_code = any(c in ("P0107", "P0108", "P0109") for c in codes)

        if not ctx.has("map_kpa"):
            fb.ev_missing("map_kpa", "Live MAP data (PID 0x0B) not available from this vehicle/adapter.",
                          "بيانات MAP الحية (PID 0x0B) غير متوفرة من هذه السيارة أو الجهاز.")
        idle_hi = noise = corr_low = koeo = trims_normal = trims_lean = None
        if idle and idle.n >= 10:
            lo, hi = round(baro * 0.20, 1), round(baro * 0.45, 1)
            idle_hi, abn = fb.ev_stat(
                "map_kpa", idle, lo=lo, hi=hi, unit="kPa", context=CTX_WARM_IDLE, weight=0.8,
                en=f"Average MAP at warm idle {idle.mean:.1f} kPa (typical {lo:.0f}–{hi:.0f} kPa at baro {baro:.0f} kPa)",
                ar=f"متوسط MAP في الخمول {idle.mean:.1f} كيلوباسكال (المعتاد {lo:.0f}–{hi:.0f} عند ضغط جوي {baro:.0f})",
            )
            noise, _ = fb.ev_stat(
                "map_kpa", idle, lo=None, hi=3.0, unit="kPa", context=CTX_WARM_IDLE, use="std", weight=0.7,
                en=f"MAP fluctuation at steady idle: σ = {idle.std:.2f} kPa (a healthy sensor is usually < 3 kPa)",
                ar=f"تذبذب MAP في الخمول المستقر: σ = {idle.std:.2f} كيلوباسكال (الحساس السليم عادة أقل من 3)",
            )
        elif ctx.has("map_kpa"):
            fb.ev_missing(None, "Not enough warm-idle samples to judge the MAP value; idle the warm engine for 30 s.",
                          "لا توجد قراءات كافية في الخمول والمحرك دافئ؛ اترك المحرك دافئا في الخمول 30 ثانية.")
        if not baro_measured:
            fb.ev_missing("baro_kpa", "Barometric pressure (PID 0x33) not available; 101.3 kPa (sea level) assumed.",
                          "الضغط الجوي (PID 0x33) غير متوفر؛ تم افتراض 101.3 كيلوباسكال (مستوى البحر).")
        ref = "maf_gs" if ctx.has("maf_gs", 10) else "throttle_pos" if ctx.has("throttle_pos", 10) else None
        if ref:
            r = ctx.correlation("map_kpa", ref, RUNNING)
            if r is not None:
                corr_low = fb.ev(
                    "pid_statistic", measured=True, assessment="abnormal" if r < 0.5 else "normal", weight=0.7,
                    signal="map_kpa", value=r, lo=0.5, hi=1.0, context=CTX_RUNNING,
                    en=f"MAP tracks {ref} with correlation r = {r:.2f} (expected > 0.5 — MAP must rise with load)",
                    ar=f"ارتباط MAP مع {ref} هو r = {r:.2f} (المتوقع أكبر من 0.5 لأن MAP يرتفع مع الحمل)",
                )
        off = ctx.stats("map_kpa", ("engine_off",))
        if off and off.n >= 3:
            koeo = fb.ev(
                "pid_statistic", measured=True, weight=0.9, signal="map_kpa", value=off.mean, unit="kPa",
                lo=baro - 3, hi=baro + 3, context="key on, engine off | تشغيل الإشعال والمحرك مطفأ",
                assessment="abnormal" if abs(off.mean - baro) > 3 else "normal",
                en=f"MAP with engine off {off.mean:.1f} kPa vs barometric {baro:.1f} kPa (should match within 3 kPa)",
                ar=f"MAP والمحرك مطفأ {off.mean:.1f} مقابل الضغط الجوي {baro:.1f} (يجب أن يتطابقا ضمن 3)",
            )
        else:
            fb.ev_missing("map_kpa", "No engine-off reading: a key-on/engine-off MAP vs barometric comparison was not possible.",
                          "لا توجد قراءة والمحرك مطفأ، لذلك لم تتم مقارنة MAP بالضغط الجوي.")
        trim = _total_trim(ctx, 1, IDLE)
        if trim is not None:
            tnorm = -10 <= trim <= 10
            eid = fb.ev(
                "pid_statistic", measured=True, assessment="normal" if tnorm else "abnormal", weight=0.6,
                signal="ltft_b1", value=trim, unit="%", lo=-10, hi=10, context=CTX_WARM_IDLE,
                en=f"Total fuel trim bank 1 at idle {trim:+.1f} % (STFT+LTFT, normal ±10 %)",
                ar=f"إجمالي تصحيح الوقود للبنك 1 في الخمول {trim:+.1f}% (الطبيعي ±10%)",
            )
            trims_normal = eid if tnorm else None
            trims_lean = eid if trim > 10 else None
        for ff in ctx.inp.freeze_frames:
            if ff.dtc in codes and ff.values.get("map_kpa") is not None:
                fb.ev("freeze_frame", measured=True, assessment="supports", weight=0.4, signal="map_kpa",
                      value=ff.values["map_kpa"], unit="kPa",
                      en=f"Freeze frame for {ff.dtc}: MAP {ff.values['map_kpa']} kPa at {ff.values.get('engine_rpm', '?')} rpm",
                      ar=f"الإطار المجمد للكود {ff.dtc}: MAP {ff.values['map_kpa']} عند {ff.values.get('engine_rpm', '?')} دورة")

        ids = lambda *xs: [x for x in xs if x]  # noqa: E731
        fb.cause("map_sensor_fault", "MAP sensor itself faulty or biased", "حساس MAP نفسه تالف أو قراءته منحرفة",
                 0.35, ids(noise, idle_hi, corr_low, koeo), ids(trims_lean))
        fb.cause("map_circuit", "Wiring/connector fault (5 V reference, ground or signal)",
                 "خلل في الأسلاك أو الفيش (مرجع 5 فولت أو الأرضي أو الإشارة)",
                 0.45 if circuit_code else 0.25, ids(noise, corr_low, *(dtc_ids if circuit_code else [])))
        fb.cause("vacuum_leak", "Vacuum leak / cracked MAP hose raising real manifold pressure",
                 "تسريب هواء أو خرطوم MAP مشقوق يرفع الضغط الفعلي في مجمع السحب", 0.25,
                 ids(idle_hi, trims_lean), ids(trims_normal, corr_low, koeo))
        fb.cause("mechanical_low_vacuum", "Engine producing low vacuum (valve timing, restricted exhaust)",
                 "المحرك ينتج تخلخلا منخفضا (توقيت الصمامات أو انسداد العادم)", 0.1, ids(idle_hi), ids(noise, koeo))

        fb.test("map_koeo", "Compare MAP to barometric pressure, key on / engine off",
                "مقارنة MAP بالضغط الجوي والإشعال يعمل والمحرك مطفأ",
                "Ignition ON, engine OFF for 30 s; read MAP and BARO (or local barometric pressure).",
                "شغّل الإشعال دون تشغيل المحرك 30 ثانية واقرأ MAP والضغط الجوي.",
                "Both within ±3 kPa. A larger difference points to the sensor or its circuit.",
                "يجب أن يتطابقا ضمن ±3 كيلوباسكال، والفرق الأكبر يشير إلى الحساس أو دائرته.", ["scan tool"])
        fb.test("vacuum_gauge", "Measure intake vacuum with a gauge at warm idle", "قياس التخلخل بمقياس في الخمول",
                "Tee a vacuum gauge into a manifold port; compare to the scan-tool MAP.",
                "اربط مقياس تخلخل بمنفذ في مجمع السحب وقارن بقراءة MAP في جهاز الفحص.",
                "Typically 17–21 inHg (≈ 30–43 kPa absolute). Gauge normal but MAP high → sensor/circuit.",
                "المعتاد 17–21 إنش زئبق (≈ 30–43 كيلوباسكال مطلق). المقياس سليم وMAP مرتفع ← الحساس أو الدائرة.",
                ["vacuum gauge"])
        fb.test("map_circuit", "Check MAP circuit: 5 V reference, ground and signal (wiggle test)",
                "فحص دائرة MAP: مرجع 5 فولت والأرضي والإشارة مع اختبار هز الأسلاك",
                "Back-probe the connector; watch live MAP while flexing the harness.",
                "افحص الفيش من الخلف وراقب MAP الحي أثناء تحريك الأسلاك.",
                "≈5.0 V reference, <0.1 V ground drop, signal steady while flexing.",
                "مرجع ≈5 فولت، فقد الأرضي أقل من 0.1 فولت، والإشارة ثابتة أثناء التحريك.", ["multimeter"])
        fb.test("smoke_test", "Smoke-test the intake for leaks", "اختبار الدخان لكشف تسريب الهواء",
                "Inject smoke into the intake with the engine off; inspect hoses, gaskets, PCV, MAP hose.",
                "أدخل الدخان في نظام السحب والمحرك مطفأ وافحص الخراطيم والجوانات وصمام PCV وخرطوم MAP.",
                "No smoke escaping.", "عدم خروج دخان.", ["smoke machine"])
        fb.action("Repair wiring/connector faults found in the MAP circuit", "إصلاح أي خلل في أسلاك أو فيش دائرة MAP", "map_circuit")
        fb.action("Repair any vacuum leak found", "إصلاح أي تسريب هواء يتم اكتشافه", "smoke_test")
        fb.action("Replace the MAP sensor only if the KOEO and gauge comparisons prove it reads wrong with a good circuit",
                  "استبدال حساس MAP فقط إذا أثبتت المقارنة بالضغط الجوي والمقياس خطأ قراءته مع سلامة الدائرة", "map_koeo")
        fb.action("Clear codes after repair and verify on a test drive", "مسح الأكواد بعد الإصلاح والتحقق بتجربة قيادة")
        fb.part("MAP sensor", "حساس ضغط مجمع السحب (MAP)", "sensors",
                "Only after the KOEO/vacuum-gauge comparison confirms a sensor error and the circuit tests pass.",
                "فقط بعد تأكيد خطأ الحساس بالمقارنة بالضغط الجوي ومقياس التخلخل وسلامة الدائرة.")
        fb.part("Vacuum hose / intake gasket", "خرطوم تخلخل / جوان مجمع السحب", "engine",
                "Only if the smoke test locates a leak.", "فقط إذا كشف اختبار الدخان عن تسريب.")
        return fb.build(0.35 if codes else 0.2)


def _total_trim(ctx: Context, bank: int, conds: tuple[str, ...]) -> float | None:
    pairs = ctx.paired(f"stft_b{bank}", f"ltft_b{bank}", conds)
    if len(pairs) < 8:
        return None
    return sum(a + b for a, b in pairs) / len(pairs)


# =============================================================================
class FuelTrimRule(Rule):
    id = "fuel_trim_balance"
    dtc_triggers = ("P0170", "P0171", "P0172", "P0173", "P0174", "P0175", "P2187", "P2188", "P2189", "P2190")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        idle1, high1 = _total_trim(ctx, 1, IDLE), _total_trim(ctx, 1, HIGH_RPM)
        idle2, high2 = _total_trim(ctx, 2, IDLE), _total_trim(ctx, 2, HIGH_RPM)
        vals = [v for v in (idle1, high1, idle2, high2) if v is not None]
        lean = any(c in ("P0171", "P0174", "P2187", "P2189") for c in codes) or any(v > 15 for v in vals)
        rich = any(c in ("P0172", "P0175", "P2188", "P2190") for c in codes) or any(v < -15 for v in vals)
        if not codes and not (lean or rich):
            return None
        direction = "rich" if rich and not lean else "lean"
        fb = FindingBuilder(
            fid, self, system="fuel", severity="medium", related_dtcs=codes,
            title_en=f"Air-fuel mixture running {direction} (fuel trim out of range)",
            title_ar="الخليط فقير (تصحيح الوقود خارج النطاق)" if direction == "lean" else "الخليط غني (تصحيح الوقود خارج النطاق)",
        )
        _add_dtcs(fb, ctx, codes)
        if not (ctx.has("stft_b1") and ctx.has("ltft_b1")):
            fb.ev_missing("ltft_b1", "Fuel trim PIDs (0x06/0x07) not available — cannot quantify the mixture error.",
                          "معاملات تصحيح الوقود (0x06/0x07) غير متوفرة، فلا يمكن قياس خطأ الخليط.")
        e = {}

        def trim_ev(name: str, val: float | None, ctx_label: str, bank: int) -> str | None:
            if val is None:
                return None
            ab = val > 10 or val < -10
            return fb.ev("pid_statistic", measured=True, assessment="abnormal" if ab else "normal", weight=0.75,
                         signal=f"ltft_b{bank}", value=val, unit="%", lo=-10, hi=10, context=ctx_label,
                         en=f"Total fuel trim bank {bank} ({name}) {val:+.1f} % (STFT+LTFT; normal within ±10 %)",
                         ar=f"إجمالي تصحيح الوقود للبنك {bank} ({'خمول' if name == 'idle' else 'دورات عالية'}) {val:+.1f}% (الطبيعي ±10%)")

        e["idle1"] = trim_ev("idle", idle1, CTX_WARM_IDLE, 1)
        e["high1"] = trim_ev("high rpm", high1, CTX_HIGH, 1)
        e["idle2"] = trim_ev("idle", idle2, CTX_WARM_IDLE, 2)
        e["high2"] = trim_ev("high rpm", high2, CTX_HIGH, 2)
        if idle1 is not None and high1 is None:
            fb.ev_missing(None, "No data above 1500 rpm: hold 2500 rpm for 30 s (or drive) to tell a vacuum leak from a fuel-delivery problem.",
                          "لا توجد بيانات فوق 1500 دورة: ثبّت المحرك على 2500 دورة 30 ثانية (أو قُد السيارة) للتمييز بين تسريب الهواء ومشكلة إمداد الوقود.")
        leak_sig = load_sig = None
        if idle1 is not None and high1 is not None and direction == "lean":
            if idle1 - high1 >= 8:
                leak_sig = fb.ev("pid_statistic", measured=True, assessment="abnormal", weight=0.85, signal="ltft_b1",
                                 value=idle1 - high1, unit="%",
                                 en=f"Lean correction drops by {idle1 - high1:.1f} points from idle to high rpm — typical of unmetered air (vacuum leak).",
                                 ar=f"التصحيح ينخفض {idle1 - high1:.1f} نقطة من الخمول إلى الدورات العالية، وهذا نمط تسريب هواء غير مقاس.")
            elif high1 - idle1 >= 5:
                load_sig = fb.ev("pid_statistic", measured=True, assessment="abnormal", weight=0.8, signal="ltft_b1",
                                 value=high1 - idle1, unit="%",
                                 en=f"Lean correction grows by {high1 - idle1:.1f} points under load — typical of insufficient fuel delivery.",
                                 ar=f"التصحيح يزيد {high1 - idle1:.1f} نقطة تحت الحمل، وهذا نمط نقص إمداد الوقود.")
        both_banks = None
        if idle1 is not None and idle2 is not None:
            same = (idle1 > 10 and idle2 > 10) or (idle1 < -10 and idle2 < -10)
            both_banks = fb.ev("pid_statistic", measured=True, assessment="supports" if same else "contradicts",
                               weight=0.5, en="Both banks deviate the same way → common cause (intake, MAF, fuel pressure)."
                               if same else "Only one bank deviates → cause specific to that bank (injector, gasket, exhaust leak).",
                               ar="البنكان ينحرفان بنفس الاتجاه ← سبب مشترك (السحب أو MAF أو ضغط الوقود)."
                               if same else "بنك واحد فقط ينحرف ← سبب خاص بهذا البنك (بخاخ أو جوان أو تسريب عادم).")
        o2 = ctx.stats("o2_b1s1_voltage", ("warm_idle", "cruise", "free_rev"))
        o2_ev = None
        if o2 and o2.n >= 10:
            biased = o2.mean < 0.35 if direction == "lean" else o2.mean > 0.6
            o2_ev = fb.ev("pid_statistic", measured=True, assessment="supports" if biased else "inconclusive", weight=0.4,
                          signal="o2_b1s1_voltage", value=o2.mean, unit="V", lo=0.35, hi=0.6,
                          en=f"Upstream O2 (B1S1) average {o2.mean:.2f} V", ar=f"متوسط حساس الأكسجين الأمامي {o2.mean:.2f} فولت")
        maf_ev = None
        liters = _engine_liters(ctx)
        maf_idle = ctx.stats("maf_gs", IDLE)
        if maf_idle and liters:
            lo, hi = round(liters * 0.8, 1), round(liters * 1.6, 1)
            maf_ev, _ = fb.ev_stat("maf_gs", maf_idle, lo=lo, hi=hi, unit="g/s", context=CTX_WARM_IDLE, weight=0.6,
                                   en=f"MAF at idle {maf_idle.mean:.2f} g/s (rule of thumb for {liters} L: {lo}–{hi} g/s)",
                                   ar=f"تدفق الهواء في الخمول {maf_idle.mean:.2f} غ/ث (القاعدة التقريبية لمحرك {liters} لتر: {lo}–{hi})")
        elif maf_idle:
            fb.ev_missing("maf_gs", "Engine displacement unknown — MAF idle value could not be compared to a reference.",
                          "سعة المحرك غير معروفة، فلم تتم مقارنة قيمة MAF بمرجع.")

        ids = lambda *xs: [x for x in xs if x]  # noqa: E731
        if direction == "lean":
            fb.cause("vacuum_leak", "Unmetered air: vacuum leak, PCV hose, intake gasket",
                     "هواء غير مقاس: تسريب تخلخل أو خرطوم PCV أو جوان السحب", 0.35, ids(leak_sig, e["idle1"], both_banks), ids(load_sig))
            fb.cause("low_fuel_pressure", "Low fuel pressure/volume (pump, filter, regulator)",
                     "ضغط أو كمية وقود منخفضة (الطرمبة أو الفلتر أو المنظم)", 0.25, ids(load_sig, e["high1"], both_banks), ids(leak_sig))
            fb.cause("maf_under_reading", "MAF sensor under-reporting airflow (contaminated)",
                     "حساس MAF يقرأ تدفقا أقل من الحقيقي (متسخ)", 0.2, ids(maf_ev, both_banks))
            fb.cause("injector_restriction", "Restricted injector(s)", "بخاخ أو أكثر مسدود جزئيا", 0.1, ids(e["high1"]), ids(both_banks))
            fb.cause("exhaust_leak", "Exhaust leak before the O2 sensor (false lean)", "تسريب عادم قبل حساس الأكسجين (قراءة فقر كاذبة)",
                     0.1, ids(o2_ev))
        else:
            fb.cause("leaking_injector", "Leaking injector(s)", "بخاخ يسرب", 0.25, ids(e["idle1"]))
            fb.cause("high_fuel_pressure", "Excessive fuel pressure (regulator)", "ضغط وقود زائد (المنظم)", 0.2, ids(both_banks))
            fb.cause("evap_purge_stuck", "EVAP purge valve stuck open", "صمام تطهير EVAP عالق مفتوحا", 0.2, ids(e["idle1"]))
            fb.cause("maf_over_reading", "MAF over-reporting airflow", "حساس MAF يقرأ تدفقا أعلى من الحقيقي", 0.15, ids(maf_ev))
            fb.cause("o2_sensor_bias", "Biased upstream O2 sensor", "حساس أكسجين أمامي منحرف القراءة", 0.1, ids(o2_ev))

        fb.test("smoke_test", "Smoke-test the intake and PCV system", "اختبار الدخان لنظام السحب وPCV",
                "Engine off, inject smoke into the intake; check hoses, intake gasket, PCV, brake booster hose.",
                "والمحرك مطفأ أدخل الدخان في السحب وافحص الخراطيم وجوان السحب وPCV وخرطوم البريك.",
                "No smoke escaping.", "عدم خروج دخان.", ["smoke machine"])
        fb.test("fuel_pressure", "Fuel pressure and volume test", "اختبار ضغط وكمية الوقود",
                "Connect a fuel pressure gauge; compare key-on, idle and snap-throttle pressure to the vehicle specification.",
                "اربط مقياس ضغط الوقود وقارن الضغط عند تشغيل الإشعال والخمول والتسارع المفاجئ بمواصفات السيارة.",
                "Within the manufacturer specification and holding steady under load.",
                "ضمن مواصفات المصنع وثابت تحت الحمل.", ["fuel pressure gauge"])
        fb.test("maf_check", "MAF plausibility check", "فحص منطقية حساس MAF",
                "Compare MAF g/s at idle and at 2500 rpm with expected values; inspect the sensor element for contamination.",
                "قارن قراءة MAF في الخمول وعلى 2500 دورة بالقيم المتوقعة وافحص عنصر الحساس من الاتساخ.",
                "Idle ≈ 1 g/s per litre of displacement, rising smoothly with rpm.",
                "في الخمول ≈ 1 غ/ث لكل لتر من سعة المحرك، ويرتفع بسلاسة مع الدورات.", ["scan tool"])
        fb.action("Fix any leak found by the smoke test, then reset fuel trims and re-check",
                  "إصلاح أي تسريب يكشفه اختبار الدخان ثم إعادة ضبط التصحيحات وإعادة الفحص", "smoke_test")
        fb.action("Clean the MAF sensor with dedicated cleaner if contaminated", "تنظيف حساس MAF بمنظف مخصص إذا كان متسخا", "maf_check")
        fb.action("Repair the fuel supply only if the pressure/volume test fails", "إصلاح إمداد الوقود فقط إذا فشل اختبار الضغط والكمية", "fuel_pressure")
        fb.part("Vacuum hose / intake gasket / PCV valve", "خرطوم تخلخل / جوان سحب / صمام PCV", "engine",
                "Only for the component the smoke test proves is leaking.", "فقط للقطعة التي يثبت اختبار الدخان أنها تسرب.")
        fb.part("Fuel pump / fuel filter", "طرمبة البنزين / فلتر البنزين", "fuel",
                "Only if fuel pressure or volume is below specification.", "فقط إذا كان ضغط الوقود أو كميته أقل من المواصفات.")
        fb.part("MAF sensor", "حساس تدفق الهواء (MAF)", "sensors",
                "Only if readings stay implausible after cleaning and the circuit is good.",
                "فقط إذا بقيت القراءات غير منطقية بعد التنظيف مع سلامة الدائرة.")
        return fb.build(0.35 if codes else 0.25)


# =============================================================================
class CoolantWarmupRule(Rule):
    id = "coolant_warmup"
    dtc_triggers = ("P0125", "P0126", "P0128")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        ect = ctx.stats("coolant_temp", RUNNING)
        rt = ctx.max_run_time()
        long_run = (rt is not None and rt >= 600) or len(ctx.values("vehicle_speed", ("cruise",))) >= 30
        cold = bool(ect and ect.n >= 10 and ect.max < 75 and long_run)
        if not codes and not cold:
            return None
        fb = FindingBuilder(fid, self, system="cooling", severity="low", related_dtcs=codes,
                            title_en="Engine not reaching normal operating temperature",
                            title_ar="المحرك لا يصل إلى حرارة التشغيل الطبيعية")
        _add_dtcs(fb, ctx, codes)
        low_ev = rt_ev = None
        if ect and ect.n >= 10:
            low_ev, _ = fb.ev_stat("coolant_temp", ect, lo=80, hi=None, unit="°C", context=CTX_RUNNING, use="max",
                                   weight=0.85, en=f"Highest coolant temperature in the session {ect.max:.0f} °C (warm engine normally 85–105 °C)",
                                   ar=f"أعلى حرارة لسائل التبريد في الجلسة {ect.max:.0f}°م (المحرك الدافئ عادة 85–105)")
        else:
            fb.ev_missing("coolant_temp", "Coolant temperature (PID 0x05) not available.", "حرارة سائل التبريد (PID 0x05) غير متوفرة.")
        if rt is not None:
            rt_ev = fb.ev("pid_reading", measured=True, assessment="supports" if rt >= 600 else "inconclusive",
                          weight=0.5, signal="run_time", value=rt, unit="s",
                          en=f"Engine had been running {rt / 60:.0f} min — long enough to be fully warm" if rt >= 600 else
                          f"Engine had been running only {rt / 60:.0f} min — may simply not be warm yet",
                          ar=f"المحرك يعمل منذ {rt / 60:.0f} دقيقة — مدة كافية للوصول للحرارة الطبيعية" if rt >= 600 else
                          f"المحرك يعمل منذ {rt / 60:.0f} دقيقة فقط — ربما لم يسخن بعد")
        else:
            fb.ev_missing("run_time", "Run time since start (PID 0x1F) not available — warm-up duration unknown.",
                          "زمن التشغيل منذ البدء (PID 0x1F) غير متوفر، فمدة التسخين غير معروفة.")
        ids = lambda *xs: [x for x in xs if x]  # noqa: E731
        fb.cause("thermostat_stuck_open", "Thermostat stuck open or opening too early", "ثرموستات عالق مفتوحا أو يفتح مبكرا",
                 0.55, ids(low_ev, rt_ev))
        fb.cause("ect_sensor_low", "Coolant temperature sensor reading lower than actual", "حساس حرارة المحرك يقرأ أقل من الحقيقة",
                 0.3, ids(low_ev))
        fb.cause("fan_always_on", "Cooling fan running continuously", "مروحة التبريد تعمل باستمرار", 0.15, ids(low_ev))
        fb.test("ir_compare", "Compare actual temperature with an infrared thermometer", "مقارنة الحرارة الفعلية بمقياس حرارة بالأشعة تحت الحمراء",
                "With the engine warm, measure the thermostat housing / ECT sensor area and compare with the scan value.",
                "والمحرك دافئ قِس حرارة بيت الثرموستات أو منطقة الحساس وقارنها بقراءة جهاز الفحص.",
                "Within ~5–10 °C. A large difference → ECT sensor/circuit; both low → thermostat.",
                "ضمن 5–10 درجات تقريبا. فرق كبير ← الحساس أو دائرته؛ وكلاهما منخفض ← الثرموستات.", ["IR thermometer"])
        fb.test("upper_hose", "Upper radiator hose warm-up check (cold start)", "فحص خرطوم الرديتر العلوي من تشغيل بارد",
                "From a cold start, feel/measure the upper hose: it should stay cool until the thermostat opens.",
                "من تشغيل بارد راقب الخرطوم العلوي: يجب أن يبقى باردا حتى يفتح الثرموستات.",
                "Hose warms quickly together with the engine → thermostat stuck open.",
                "إذا سخن الخرطوم مبكرا مع المحرك ← الثرموستات عالق مفتوحا.")
        fb.test("fan_check", "Check cooling fan operation", "فحص عمل مروحة التبريد",
                "With a cold engine at idle, the electric fan should normally be off (A/C off).",
                "والمحرك بارد في الخمول يجب أن تكون المروحة الكهربائية متوقفة عادة (المكيف مطفأ).")
        fb.action("Replace the thermostat if the hose/IR tests confirm it opens early", "استبدال الثرموستات إذا أكدت الاختبارات أنه يفتح مبكرا", "upper_hose")
        fb.action("Replace the ECT sensor only if its reading differs from the measured temperature", "استبدال حساس الحرارة فقط إذا اختلفت قراءته عن الحرارة المقاسة", "ir_compare")
        fb.part("Thermostat + gasket", "ثرموستات مع الجوان", "cooling",
                "Only if the upper-hose or IR test confirms it opens early.", "فقط إذا أكد اختبار الخرطوم أو مقياس الحرارة أنه يفتح مبكرا.")
        fb.part("Coolant temperature sensor", "حساس حرارة سائل التبريد", "sensors",
                "Only if the IR comparison shows the sensor reads wrong.", "فقط إذا أظهرت المقارنة أن الحساس يقرأ خطأ.")
        return fb.build(0.35 if codes else 0.25)


class OverheatRule(Rule):
    id = "engine_overheat"
    dtc_triggers = ("P0217", "P0218")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        ect = ctx.stats("coolant_temp", RUNNING)
        hot = bool(ect and ect.max >= 110)
        if not codes and not hot:
            return None
        fb = FindingBuilder(fid, self, system="cooling", severity="critical", related_dtcs=codes,
                            title_en="Engine overheating — stop driving", title_ar="ارتفاع حرارة المحرك — أوقف القيادة")
        _add_dtcs(fb, ctx, codes)
        hot_ev = None
        if ect:
            hot_ev, _ = fb.ev_stat("coolant_temp", ect, lo=None, hi=108, unit="°C", context=CTX_RUNNING, use="max", weight=0.95,
                                   en=f"Coolant reached {ect.max:.0f} °C", ar=f"وصلت حرارة سائل التبريد إلى {ect.max:.0f}°م")
        ids = [x for x in (hot_ev,) if x]
        fb.cause("low_coolant", "Low coolant / leak", "نقص سائل التبريد أو تسريب", 0.3, ids)
        fb.cause("fan_failure", "Cooling fan not operating", "مروحة التبريد لا تعمل", 0.25, ids)
        fb.cause("thermostat_stuck_closed", "Thermostat stuck closed", "ثرموستات عالق مغلقا", 0.2, ids)
        fb.cause("water_pump", "Water pump failure", "عطل في طرمبة الماء", 0.15, ids)
        fb.cause("head_gasket", "Head gasket / combustion gases in coolant", "تلف جوان الرأس أو غازات احتراق في سائل التبريد", 0.1, ids)
        fb.test("coolant_level", "Check coolant level — ONLY with the engine cold", "فحص مستوى سائل التبريد — والمحرك بارد فقط",
                "Never open the cap on a hot engine. Check reservoir and radiator level when cold.",
                "لا تفتح الغطاء والمحرك ساخن أبدا. افحص الخزان والرديتر والمحرك بارد.")
        fb.test("fan_operation", "Verify fan switches on at high temperature", "التأكد من تشغيل المروحة عند ارتفاع الحرارة",
                "Watch the fan as coolant passes ~100 °C, or command it with a scan tool if supported.",
                "راقب المروحة عند تجاوز الحرارة 100 درجة تقريبا أو شغّلها بجهاز الفحص إن كان يدعم ذلك.")
        fb.test("pressure_test", "Cooling system pressure test and combustion-gas (block) test",
                "اختبار ضغط نظام التبريد واختبار غازات الاحتراق", "Pressurise to cap rating; check for leaks and pressure drop.",
                "اضغط النظام حتى قيمة الغطاء وافحص التسريب وانخفاض الضغط.", tools=["cooling system pressure tester", "block tester"])
        fb.action("Stop the engine and let it cool; do not continue driving while overheating",
                  "أوقف المحرك واتركه يبرد ولا تواصل القيادة مع ارتفاع الحرارة")
        return fb.build(0.6 if hot else 0.4)


# =============================================================================
class ChargingRule(Rule):
    id = "charging_system"
    dtc_triggers = ("P0560", "P0561", "P0562", "P0563", "P0620", "P0621", "P0622", "P0625", "P0626")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        run = ctx.stats("module_voltage", RUNNING)
        off_meas = ctx.measurement("battery_voltage_engine_off")
        low = bool(run and run.n >= 5 and run.mean < 13.2)
        high = bool(run and run.n >= 5 and run.mean > 15.0)
        if not codes and not (low or high):
            return None
        over = high or "P0563" in codes
        fb = FindingBuilder(
            fid, self, system="charging", related_dtcs=codes,
            severity="high" if (run and run.mean < 12.6) or (run and run.mean > 15.5) else "medium",
            title_en="Charging system voltage too high" if over else "Charging system not maintaining voltage",
            title_ar="جهد نظام الشحن مرتفع أكثر من اللازم" if over else "نظام الشحن لا يحافظ على الجهد المطلوب",
        )
        _add_dtcs(fb, ctx, codes)
        v_ev = None
        if run and run.n >= 5:
            v_ev, _ = fb.ev_stat("module_voltage", run, lo=13.2, hi=14.8, unit="V", context=CTX_RUNNING, weight=0.9,
                                 en=f"Control-module voltage with engine running {run.mean:.2f} V (normal 13.2–14.8 V)",
                                 ar=f"جهد وحدة التحكم والمحرك يعمل {run.mean:.2f} فولت (الطبيعي 13.2–14.8)")
        else:
            fb.ev_missing("module_voltage", "Module voltage (PID 0x42) not available; measure battery voltage with a multimeter.",
                          "جهد وحدة التحكم (PID 0x42) غير متوفر؛ قِس جهد البطارية بالملتيميتر.")
        off_ev = None
        if off_meas is not None:
            off_ev = fb.ev("user_measurement", measured=True, assessment="abnormal" if off_meas < 12.2 else "normal",
                           weight=0.6, signal="battery_voltage_engine_off", value=off_meas, unit="V", lo=12.2, hi=12.9,
                           en=f"Battery voltage engine off {off_meas:.2f} V (measured)", ar=f"جهد البطارية والمحرك مطفأ {off_meas:.2f} فولت (مقاس)")
        ids = lambda *xs: [x for x in xs if x]  # noqa: E731
        if over:
            fb.cause("regulator_fault", "Voltage regulator / alternator control fault", "خلل في منظم الجهد أو تحكم الدينامو", 0.6, ids(v_ev))
            fb.cause("sense_wiring", "Poor battery-sense / ground connection", "ضعف توصيلة حساس البطارية أو الأرضي", 0.4, ids(v_ev))
        else:
            fb.cause("alternator", "Alternator not charging", "الدينامو لا يشحن", 0.4, ids(v_ev))
            fb.cause("wiring_ground", "Charging wiring, fuse or ground fault", "خلل في أسلاك الشحن أو الفيوز أو الأرضي", 0.25, ids(v_ev))
            fb.cause("belt", "Drive belt slipping or broken", "سير المحرك يفلت أو مقطوع", 0.15, ids(v_ev))
            fb.cause("battery", "Battery fault loading the system", "عطل في البطارية يحمّل النظام", 0.2, ids(off_ev))
        fb.test("battery_terminals", "Measure battery voltage engine off and running", "قياس جهد البطارية والمحرك مطفأ ويعمل",
                "Multimeter on the battery posts: engine off (rested), then at 2000 rpm with loads off.",
                "ملتيميتر على أقطاب البطارية: المحرك مطفأ ثم على 2000 دورة مع إطفاء الأحمال.",
                "Off: 12.4–12.7 V. Running: 13.8–14.7 V.", "مطفأ: 12.4–12.7 فولت. يعمل: 13.8–14.7 فولت.", ["multimeter"])
        fb.test("voltage_drop", "Voltage-drop test on charging and ground cables", "اختبار فقد الجهد في كابلات الشحن والأرضي",
                "Under load, measure drop between alternator B+ and battery +, and engine block to battery −.",
                "تحت الحمل قِس الفقد بين B+ الدينامو وموجب البطارية وبين جسم المحرك وسالب البطارية.",
                "< 0.3 V positive side, < 0.2 V ground side.", "أقل من 0.3 فولت للموجب وأقل من 0.2 فولت للأرضي.", ["multimeter"])
        fb.test("belt_inspect", "Inspect drive belt and tensioner", "فحص سير المحرك والشداد", "Look for glazing, cracks, slipping noise.",
                "ابحث عن لمعان أو تشققات أو صوت انزلاق.")
        fb.test("load_test", "Alternator output and battery load/conductance test", "اختبار خرج الدينامو واختبار تحميل البطارية",
                "Use a charging-system tester.", "استخدم جهاز اختبار نظام الشحن.", tools=["battery/charging tester"])
        fb.action("Repair wiring/ground or belt problems first", "إصلاح مشاكل الأسلاك أو الأرضي أو السير أولا", "voltage_drop")
        fb.part("Alternator", "دينامو", "electrical", "Only if the output test fails with good wiring and belt.",
                "فقط إذا فشل اختبار الخرج مع سلامة الأسلاك والسير.")
        fb.part("Battery", "بطارية", "electrical", "Only if the load/conductance test fails.", "فقط إذا فشل اختبار التحميل.")
        return fb.build(0.35 if codes else 0.3)


# =============================================================================
class MisfireRule(Rule):
    id = "misfire"
    dtc_triggers = ("P0300", "P0301", "P0302", "P0303", "P0304", "P0305", "P0306", "P0307", "P0308",
                    "P0309", "P0310", "P0311", "P0312")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        if not codes:
            return None
        cyl = sorted({int(c[3:]) for c in codes if c != "P0300"})
        fb = FindingBuilder(
            fid, self, system="ignition", severity="high", related_dtcs=codes,
            title_en="Engine misfire" + (f" — cylinder {', '.join(map(str, cyl))}" if cyl else " — random/multiple cylinders"),
            title_ar="احتراق غير مكتمل في المحرك" + (f" — الأسطوانة {', '.join(map(str, cyl))}" if cyl else " — عشوائي أو عدة أسطوانات"),
        )
        _add_dtcs(fb, ctx, codes)
        rough = None
        idle = ctx.stats("engine_rpm", IDLE)
        if idle and idle.n >= 10:
            rough, _ = fb.ev_stat("engine_rpm", idle, lo=None, hi=25, unit="rpm", context=CTX_WARM_IDLE, use="std", weight=0.7,
                                  en=f"Idle speed variation σ = {idle.std:.0f} rpm (smooth idle is usually < 25 rpm)",
                                  ar=f"تذبذب دورات الخمول σ = {idle.std:.0f} دورة (الخمول السلس عادة أقل من 25)")
        fb.ev_missing(None, "Per-cylinder misfire counters (service 06) are not read in this version.",
                      "عدادات الاحتراق غير المكتمل لكل أسطوانة (الخدمة 06) لا تُقرأ في هذا الإصدار.")
        ids = [x for x in (rough,) if x]
        if cyl:
            fb.cause("ignition_coil", "Ignition coil on the affected cylinder", "ملف الإشعال في الأسطوانة المصابة", 0.3, ids)
            fb.cause("spark_plug", "Worn or fouled spark plug", "بوجي (شمعة إشعال) متآكلة أو متسخة", 0.3, ids)
            fb.cause("injector", "Fuel injector fault on that cylinder", "خلل في بخاخ هذه الأسطوانة", 0.2, ids)
            fb.cause("compression", "Low compression (valve, rings)", "ضعف الكمبريشن (صمامات أو شنابر)", 0.1, ids)
            fb.cause("intake_leak_runner", "Vacuum leak at that cylinder's intake runner", "تسريب هواء عند مدخل هذه الأسطوانة", 0.1, ids)
        else:
            fb.cause("vacuum_leak", "Vacuum leak (lean misfire)", "تسريب هواء (احتراق غير مكتمل بسبب الخليط الفقير)", 0.3, ids)
            fb.cause("fuel_pressure", "Low fuel pressure", "ضغط وقود منخفض", 0.25, ids)
            fb.cause("ignition_multiple", "Several worn plugs/coils", "عدة بواجي أو ملفات متآكلة", 0.3, ids)
            fb.cause("egr", "EGR flow at idle", "تدفق EGR في الخمول", 0.15, ids)
        fb.test("swap_coil", "Swap the coil with a neighbouring cylinder", "تبديل ملف الإشعال مع أسطوانة مجاورة",
                "Swap coils, clear codes, drive; see whether the misfire code moves to the other cylinder.",
                "بدّل الملفات وامسح الأكواد وقد السيارة؛ لاحظ هل ينتقل الكود للأسطوانة الأخرى.",
                "Code follows the coil → coil. Stays → plug/injector/compression.",
                "إذا انتقل الكود مع الملف ← الملف. إذا بقي ← البوجي أو البخاخ أو الكمبريشن.")
        fb.test("plug_inspect", "Remove and inspect the spark plug(s)", "فك وفحص البواجي", "Check gap, electrode wear, oil/fuel fouling, cracked insulator.",
                "افحص الفجوة وتآكل القطب والاتساخ بالزيت أو الوقود وتشقق العازل.")
        fb.test("compression_test", "Compression test", "اختبار الكمبريشن", "Measure all cylinders; compare.",
                "قِس جميع الأسطوانات وقارن.", "All within ~10 % of each other.", "جميعها ضمن 10% تقريبا من بعضها.", ["compression gauge"])
        fb.action("Avoid hard driving: a flashing check-engine light means catalyst damage risk",
                  "تجنب القيادة العنيفة: وميض لمبة فحص المحرك يعني خطر تلف المحول الحفاز")
        fb.part("Ignition coil", "ملف إشعال", "ignition", "Only if the misfire follows the coil after a swap test.",
                "فقط إذا انتقل الخلل مع الملف بعد اختبار التبديل.")
        fb.part("Spark plugs (set)", "طقم بواجي", "ignition", "If plugs are worn/fouled or past the service interval.",
                "إذا كانت البواجي متآكلة أو متسخة أو تجاوزت موعد التغيير.")
        return fb.build(0.4)


# =============================================================================
class TempSensorCircuitRule(Rule):
    id = "temp_sensor_circuit"
    dtc_triggers = ("P0110", "P0112", "P0113", "P0115", "P0117", "P0118")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        hits = []
        for sig in ("coolant_temp", "intake_air_temp"):
            st = ctx.stats(sig)
            if st and st.n >= 3 and (st.min <= -39 or st.max >= 140):
                hits.append((sig, st))
        if not codes and not hits:
            return None
        fb = FindingBuilder(fid, self, system="engine", severity="medium", related_dtcs=codes,
                            title_en="Temperature sensor circuit reading out of range",
                            title_ar="قراءة دائرة حساس الحرارة خارج النطاق")
        _add_dtcs(fb, ctx, codes)
        evs = []
        for sig, st in hits:
            open_c = st.min <= -39
            eid, _ = fb.ev_stat(sig, st, lo=-30, hi=130, unit="°C", context="any | أي حالة", use="min" if open_c else "max",
                                weight=0.9,
                                en=f"{sig} reads {(st.min if open_c else st.max):.0f} °C — the value an ECU reports for an {'open' if open_c else 'shorted'} circuit",
                                ar=f"{sig} يقرأ {(st.min if open_c else st.max):.0f}°م — وهي القيمة التي تظهر عند {'انقطاع' if open_c else 'قصر'} الدائرة")
            evs.append(eid)
        fb.cause("wiring_connector", "Wiring or connector fault (open/short)", "خلل في الأسلاك أو الفيش (انقطاع أو قصر)", 0.5, evs)
        fb.cause("sensor", "Sensor failed", "الحساس تالف", 0.5, evs)
        fb.test("sensor_resistance", "Measure sensor resistance and circuit voltage", "قياس مقاومة الحساس وجهد الدائرة",
                "Unplug, measure sensor resistance vs temperature chart; check 5 V reference and ground at the connector.",
                "افصل الحساس وقِس مقاومته وقارنها بجدول الحرارة وافحص مرجع 5 فولت والأرضي في الفيش.", tools=["multimeter"])
        fb.part("Temperature sensor", "حساس حرارة", "sensors", "Only if its resistance is out of specification.",
                "فقط إذا كانت مقاومته خارج المواصفات.")
        return fb.build(0.35 if codes else 0.3)


# =============================================================================
class O2SensorRule(Rule):
    id = "o2_sensor_activity"
    dtc_triggers = ("P0130", "P0131", "P0132", "P0133", "P0134", "P0135", "P0136", "P0137", "P0138", "P0139",
                    "P0140", "P0141", "P0150", "P0151", "P0152", "P0153", "P0154", "P0155", "P0156", "P0157",
                    "P0158", "P0159", "P0160", "P0161", "P2195", "P2196", "P2197", "P2198", "P2270", "P2271",
                    "P2272", "P2273")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        if not codes:
            return None
        heater = any(c in ("P0135", "P0141", "P0155", "P0161") for c in codes)
        fb = FindingBuilder(fid, self, system="emissions", severity="low", related_dtcs=codes,
                            title_en="Oxygen sensor " + ("heater circuit" if heater else "signal") + " fault",
                            title_ar="خلل في " + ("دائرة سخان" if heater else "إشارة") + " حساس الأكسجين")
        _add_dtcs(fb, ctx, codes)
        sw_ev = None
        pairs = ctx.series.get("o2_b1s1_voltage")
        if pairs and len(pairs) >= 20:
            v = pairs.v
            crossings = sum(1 for a, b in zip(v, v[1:], strict=False) if (a - 0.45) * (b - 0.45) < 0)
            dur = (pairs.t[-1] - pairs.t[0]) / 1000 or 1
            rate = crossings / dur * 10
            sw_ev = fb.ev("pid_statistic", measured=True, assessment="abnormal" if rate < 2 else "normal", weight=0.6,
                          signal="o2_b1s1_voltage", value=rate, unit="crossings/10s", lo=2, hi=None,
                          en=f"Upstream O2 crosses 0.45 V {rate:.1f} times per 10 s (an active sensor in closed loop switches several times)",
                          ar=f"حساس الأكسجين الأمامي يعبر 0.45 فولت {rate:.1f} مرة كل 10 ثوان (الحساس النشط يتبدل عدة مرات)")
        else:
            fb.ev_missing("o2_b1s1_voltage", "Not enough O2 sensor data to judge switching activity.",
                          "لا توجد بيانات كافية لحساس الأكسجين للحكم على نشاطه.")
        ids = [x for x in (sw_ev,) if x]
        if heater:
            fb.cause("heater_circuit", "Heater circuit open/short or blown fuse", "انقطاع أو قصر في دائرة السخان أو فيوز محروق", 0.5)
            fb.cause("sensor_heater", "Sensor heater element failed", "عنصر السخان في الحساس تالف", 0.5)
            fb.test("heater_resistance", "Measure heater resistance and supply", "قياس مقاومة السخان والتغذية",
                    "Check fuse, 12 V supply with key on and heater resistance (typically a few ohms).",
                    "افحص الفيوز وتغذية 12 فولت مع الإشعال ومقاومة السخان (عادة بضعة أوم).", tools=["multimeter"])
        else:
            fb.cause("sensor_aged", "Aged/slow oxygen sensor", "حساس أكسجين قديم أو بطيء الاستجابة", 0.4, ids)
            fb.cause("exhaust_leak", "Exhaust leak near the sensor", "تسريب عادم قرب الحساس", 0.2)
            fb.cause("wiring", "Sensor wiring damage", "تلف أسلاك الحساس", 0.2)
            fb.cause("real_mixture_fault", "Actual lean/rich condition", "مشكلة حقيقية في الخليط (فقر أو غنى)", 0.2)
            fb.test("o2_response", "O2 response test (snap throttle / propane)", "اختبار استجابة الحساس (تسارع مفاجئ أو بروبان)",
                    "Watch sensor voltage while enriching/leaning the mixture.", "راقب جهد الحساس أثناء إغناء أو إفقار الخليط.",
                    "Fast swing to > 0.8 V rich and < 0.2 V lean.", "تأرجح سريع فوق 0.8 فولت للغني وتحت 0.2 فولت للفقير.")
        fb.part("Oxygen sensor", "حساس أكسجين", "sensors", "Only after wiring/heater supply and exhaust leaks are ruled out.",
                "فقط بعد استبعاد الأسلاك وتغذية السخان وتسريب العادم.")
        return fb.build(0.35)


class CatalystRule(Rule):
    id = "catalyst_efficiency"
    dtc_triggers = ("P0420", "P0421", "P0430", "P0431")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        if not codes:
            return None
        fb = FindingBuilder(fid, self, system="emissions", severity="low", related_dtcs=codes,
                            title_en="Catalytic converter efficiency below threshold",
                            title_ar="كفاءة المحول الحفاز (الدبة) أقل من الحد")
        _add_dtcs(fb, ctx, codes)
        up, down = ctx.stats("o2_b1s1_voltage", RUNNING), ctx.stats("o2_b1s2_voltage", RUNNING)
        ratio_ev = None
        if up and down and up.n >= 20 and down.n >= 20 and up.std > 0.05:
            ratio = down.std / up.std
            ratio_ev = fb.ev("pid_statistic", measured=True, assessment="abnormal" if ratio > 0.5 else "normal", weight=0.7,
                             signal="o2_b1s2_voltage", value=ratio, lo=None, hi=0.5,
                             en=f"Downstream/upstream O2 activity ratio {ratio:.2f} (a working catalyst keeps the rear sensor steady, ratio < 0.5)",
                             ar=f"نسبة نشاط الحساس الخلفي إلى الأمامي {ratio:.2f} (المحول السليم يبقي الحساس الخلفي ثابتا، النسبة أقل من 0.5)")
        else:
            fb.ev_missing("o2_b1s2_voltage", "Upstream/downstream O2 data insufficient for a catalyst activity comparison.",
                          "بيانات حساسي الأكسجين الأمامي والخلفي غير كافية لمقارنة نشاط المحول.")
        ids = [x for x in (ratio_ev,) if x]
        fb.cause("catalyst_worn", "Catalyst oxygen-storage capacity reduced", "انخفاض قدرة المحول على تخزين الأكسجين", 0.45, ids)
        fb.cause("downstream_sensor", "Downstream O2 sensor faulty", "حساس الأكسجين الخلفي تالف", 0.2)
        fb.cause("exhaust_leak", "Exhaust leak before/near the rear sensor", "تسريب عادم قبل الحساس الخلفي أو قربه", 0.15)
        fb.cause("upstream_cause", "Misfire or rich running damaging the catalyst", "احتراق غير مكتمل أو خليط غني يتلف المحول", 0.2)
        fb.test("exhaust_leak_check", "Inspect for exhaust leaks", "فحص تسريب العادم", "Listen/inspect joints and flex pipe.",
                "استمع وافحص الوصلات والخرطوم المرن.")
        fb.test("temp_delta", "Catalyst inlet/outlet temperature comparison", "مقارنة حرارة مدخل ومخرج المحول",
                "Warm engine at 2500 rpm: outlet normally hotter than inlet.", "والمحرك دافئ على 2500 دورة: المخرج عادة أسخن من المدخل.",
                tools=["IR thermometer"])
        fb.part("Catalytic converter", "محول حفاز (دبة)", "exhaust",
                "Only after misfires, fuel-trim problems, exhaust leaks and the rear O2 sensor are ruled out.",
                "فقط بعد استبعاد الاحتراق غير المكتمل ومشاكل الخليط وتسريب العادم والحساس الخلفي.")
        return fb.build(0.35)


class IdleSpeedRule(Rule):
    id = "idle_speed"
    dtc_triggers = ("P0505", "P0506", "P0507")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        idle = ctx.stats("engine_rpm", IDLE)
        out = bool(idle and idle.n >= 10 and (idle.mean < 550 or idle.mean > 1100))
        if not codes and not out:
            return None
        fb = FindingBuilder(fid, self, system="air_intake", severity="low", related_dtcs=codes,
                            title_en="Idle speed outside the normal range", title_ar="دورات الخمول خارج النطاق الطبيعي")
        _add_dtcs(fb, ctx, codes)
        ev = None
        if idle:
            ev, _ = fb.ev_stat("engine_rpm", idle, lo=550, hi=1100, unit="rpm", context=CTX_WARM_IDLE, weight=0.7,
                               en=f"Warm idle speed {idle.mean:.0f} rpm (typical 550–1000 rpm)",
                               ar=f"دورات الخمول والمحرك دافئ {idle.mean:.0f} (المعتاد 550–1000)")
        ids = [x for x in (ev,) if x]
        fb.cause("throttle_body_dirty", "Dirty throttle body / idle air passage", "بوابة هواء متسخة أو ممر هواء الخمول", 0.4, ids)
        fb.cause("vacuum_leak", "Vacuum leak (high idle)", "تسريب هواء (خمول مرتفع)", 0.35, ids)
        fb.cause("electrical_load", "Idle control / electrical load compensation", "تحكم الخمول أو تعويض الأحمال الكهربائية", 0.25, ids)
        fb.test("throttle_inspect", "Inspect and clean the throttle body", "فحص وتنظيف بوابة الهواء",
                "Inspect for carbon deposits; clean with throttle-body cleaner; a relearn may be required.",
                "افحص ترسبات الكربون ونظّف بمنظف البوابة؛ قد يلزم إجراء إعادة تعلم.")
        return fb.build(0.3 if codes else 0.25)


# =============================================================================
class AcPerformanceRule(Rule):
    """A/C assessment from user/technician gauge readings (standard OBD-II rarely exposes A/C data)."""

    id = "ac_performance"
    dtc_triggers = ("P0530", "P0531", "P0532", "P0533", "P0534", "P0645", "P0646", "P0647")

    def run(self, ctx: Context, fid: str) -> Finding | None:
        codes = self.matching_dtcs(ctx)
        lowp = ctx.measurement("ac_low_side_kpa")
        highp = ctx.measurement("ac_high_side_kpa")
        vent = ctx.measurement("ac_vent_temp_c")
        amb = ctx.measurement("ambient_temp_c")
        if amb is None and ctx.stats("ambient_temp"):
            amb = ctx.stats("ambient_temp").mean  # type: ignore[union-attr]
        if not codes and lowp is None and highp is None and vent is None:
            return None
        fb = FindingBuilder(fid, self, system="ac", severity="low", related_dtcs=codes,
                            title_en="Air-conditioning performance assessment", title_ar="تقييم أداء المكيف")
        _add_dtcs(fb, ctx, codes)
        need = []
        if lowp is None:
            need.append(("ac_low_side_kpa", "Low-side pressure (gauge, engine running, A/C max)", "ضغط الجهة المنخفضة (بالساعة، المحرك يعمل والمكيف على الأقصى)"))
        if highp is None:
            need.append(("ac_high_side_kpa", "High-side pressure (gauge)", "ضغط الجهة العالية (بالساعة)"))
        if vent is None:
            need.append(("ac_vent_temp_c", "Centre vent outlet temperature", "حرارة الهواء من الفتحة الوسطى"))
        if amb is None:
            need.append(("ambient_temp_c", "Ambient temperature", "حرارة الجو"))
        for key, en, ar in need:
            fb.ev_missing(key, f"Needed for an A/C diagnosis: {en}.", f"مطلوب لتشخيص المكيف: {ar}.")
        evs: dict[str, str] = {}
        if lowp is not None:
            evs["low"] = fb.ev("user_measurement", measured=True, signal="ac_low_side_kpa", value=lowp, unit="kPa", lo=170, hi=310,
                               assessment="normal" if 170 <= lowp <= 310 else "abnormal", weight=0.7,
                               en=f"Low side {lowp:.0f} kPa (typical 170–310 kPa gauge)", ar=f"الجهة المنخفضة {lowp:.0f} كيلوباسكال (المعتاد 170–310)")
        if highp is not None and amb is not None:
            lo, hi = 900 + 25 * (amb - 25), 1500 + 35 * (amb - 25)
            evs["high"] = fb.ev("user_measurement", measured=True, signal="ac_high_side_kpa", value=highp, unit="kPa",
                                lo=round(lo), hi=round(hi), assessment="normal" if lo <= highp <= hi else "abnormal", weight=0.7,
                                context=f"ambient {amb:.0f} °C", en=f"High side {highp:.0f} kPa (rough range {lo:.0f}–{hi:.0f} kPa at {amb:.0f} °C)",
                                ar=f"الجهة العالية {highp:.0f} كيلوباسكال (نطاق تقريبي {lo:.0f}–{hi:.0f} عند {amb:.0f}°م)")
        if vent is not None:
            evs["vent"] = fb.ev("user_measurement", measured=True, signal="ac_vent_temp_c", value=vent, unit="°C", lo=2, hi=12,
                                assessment="normal" if vent <= 12 else "abnormal", weight=0.6,
                                en=f"Vent outlet {vent:.0f} °C (typically 2–12 °C on max A/C)", ar=f"حرارة الفتحة {vent:.0f}°م (عادة 2–12 على أقصى تبريد)")
        low_low = lowp is not None and lowp < 170
        low_high = lowp is not None and lowp > 310
        hi_ab = evs.get("high") and highp is not None and amb is not None
        high_low = bool(hi_ab and highp < 900 + 25 * (amb - 25))  # type: ignore[operator]
        high_high = bool(hi_ab and highp > 1500 + 35 * (amb - 25))  # type: ignore[operator]
        g = lambda k: [evs[k]] if k in evs else []  # noqa: E731
        fb.cause("low_charge", "Low refrigerant charge (leak)", "نقص غاز التبريد (تسريب)", 0.3 + 0.3 * (low_low and high_low), g("low") + g("high"))
        fb.cause("overcharge_condenser", "Overcharge or poor condenser airflow (fan)", "زيادة الغاز أو ضعف تهوية المكثف (المروحة)",
                 0.2 + 0.3 * (low_high and high_high), g("low") + g("high"))
        fb.cause("compressor_weak", "Weak compressor", "ضعف الكمبروسر", 0.15 + 0.3 * (low_high and high_low), g("low") + g("high"))
        fb.cause("restriction", "Restriction (expansion valve/orifice)", "انسداد (صمام التمدد أو الفتحة)", 0.15 + 0.3 * (low_low and not high_low), g("low"))
        fb.cause("hvac_control", "Blend door / HVAC control", "باب خلط الهواء أو تحكم التكييف", 0.2 * (not (low_low or low_high)), g("vent"))
        fb.test("gauge_set", "Measure pressures with a manifold gauge set", "قياس الضغوط بساعات الفريون",
                "Engine at 1500 rpm, A/C max, doors open, 5 min stabilisation; record both sides + ambient + vent temperature.",
                "المحرك على 1500 دورة والمكيف على الأقصى والأبواب مفتوحة 5 دقائق؛ سجل الضغطين وحرارة الجو والفتحة.",
                tools=["A/C manifold gauges", "thermometer"])
        fb.test("leak_check", "Refrigerant leak check (UV dye / electronic detector)", "فحص تسريب الغاز (صبغة أو جهاز إلكتروني)",
                "Required before recharging — never just top up.", "مطلوب قبل التعبئة — لا تكتفِ بإضافة الغاز.")
        fb.action("Recover, repair leak, evacuate and recharge to the specified weight", "سحب الغاز وإصلاح التسريب وتفريغ النظام وتعبئته بالوزن المحدد", "leak_check")
        return fb.build(0.3)


# =============================================================================
class GenericDtcRule(Rule):
    """Fallback for codes no specialised rule handled: KB facts only, nothing invented."""

    id = "generic_dtc"

    def run_for(self, ctx: Context, fid: str, code: str) -> Finding:
        kb = get_kb()
        k = kb.lookup(code)
        st = kb.structure(code)
        sev = (k or {}).get("severity", "medium") if k else "low"
        if k:
            title_en, title_ar = f"{code}: {k['en']}", f"{code}: {k['ar']}"
        else:
            title_en = f"{code}: not in the AutoMind knowledge base ({'generic' if st['is_generic'] else 'manufacturer-specific'} {st['system']} code)"
            title_ar = f"{code}: غير موجود في قاعدة معرفة أوتومايند (كود {'عام' if st['is_generic'] else 'خاص بالشركة المصنعة'})"
        fb = FindingBuilder(fid, self, system=_system_for(k, st), severity=sev, related_dtcs=[code],
                            title_en=title_en, title_ar=title_ar)
        _add_dtcs(fb, ctx, [code])
        if not k:
            fb.ev_missing(None, "No verified description for this code; consult the manufacturer's service information for this vehicle.",
                          "لا يوجد وصف موثق لهذا الكود؛ راجع معلومات الصيانة الخاصة بالشركة المصنعة لهذه السيارة.")
        for sig in (k or {}).get("related_signals", [])[:4]:
            s = ctx.stats(sig)
            if s:
                fb.ev("pid_statistic", measured=True, assessment="inconclusive", weight=0.3, signal=sig, value=s.mean,
                      en=f"{sig}: mean {s.mean:.2f}, range {s.min:.2f}–{s.max:.2f} ({s.n} samples) — shown for context",
                      ar=f"{sig}: المتوسط {s.mean:.2f}، المدى {s.min:.2f}–{s.max:.2f} ({s.n} قراءة) — للاطلاع")
        causes = (k or {}).get("common_causes", [])
        kb_ev = fb.ev_kb("Possible causes listed are general knowledge for this code, not derived from this vehicle's data.",
                         "الأسباب المحتملة المذكورة معلومات عامة عن هذا الكود وليست مستنتجة من بيانات هذه السيارة.") if causes else None
        for i, c in enumerate(causes):
            fb.cause(f"kb_{i}", c["en"], c["ar"], 1.0 / len(causes), [kb_ev] if kb_ev else [])
        fb.test("service_procedure", "Follow the manufacturer's diagnostic procedure for this code",
                "اتباع إجراء التشخيص الخاص بالشركة المصنعة لهذا الكود",
                "Use the vehicle-specific service information (pin-out, specifications, test steps).",
                "استخدم معلومات الصيانة الخاصة بالسيارة (توزيع الأطراف والمواصفات وخطوات الاختبار).")
        fb.test("inspect_wiring", "Visual inspection of the related component and wiring", "فحص بصري للقطعة المرتبطة وأسلاكها",
                "Look for damaged wiring, corrosion, loose connectors.", "ابحث عن أسلاك تالفة أو صدأ أو فيش مرتخية.")
        fb.test("clear_and_verify", "Record freeze frame, clear, and check if the code returns",
                "تسجيل الإطار المجمد ثم المسح والتحقق من عودة الكود",
                "After recording data, clear codes (with consent) and drive under the freeze-frame conditions.",
                "بعد حفظ البيانات امسح الأكواد (بالموافقة) وقد السيارة في ظروف الإطار المجمد.")
        return fb.build(0.3 if k else 0.15)

    def run(self, ctx: Context, fid: str) -> Finding | None:  # pragma: no cover - use run_for
        return None


def _system_for(k: dict | None, st: dict) -> str:
    sub = (k or {}).get("subsystem", "")
    mapping = {
        "fuel": "fuel", "air_intake": "air_intake", "ignition": "ignition", "emissions": "emissions", "evap": "emissions",
        "exhaust": "emissions", "cooling": "cooling", "charging": "charging", "transmission": "transmission",
        "engine": "engine", "electrical": "electrical", "network": "network", "sensors": "engine", "idle_control": "air_intake",
        "ac": "ac",
    }
    if sub in mapping:
        return mapping[sub]
    return {"network": "network", "chassis": "other", "body": "electrical"}.get(st["system"], "engine")


SPECIALISED_RULES: list[Rule] = [
    OverheatRule(), MapSensorRule(), FuelTrimRule(), MisfireRule(), ChargingRule(), CoolantWarmupRule(),
    TempSensorCircuitRule(), O2SensorRule(), CatalystRule(), IdleSpeedRule(), AcPerformanceRule(),
]
