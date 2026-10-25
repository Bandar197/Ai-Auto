#!/usr/bin/env python3
"""Import manufacturer-specific DTC descriptions into shared/kb/dtc_oem.json.

Use ONLY with a file the project is licensed to use (a purchased data licence, an
open dataset whose licence allows it, or your own verified notes). The source and
licence are recorded with every imported code. Nothing is downloaded or scraped.

Input: CSV (UTF-8, header row), JSON (list of objects), or TXT ("P1100 - Description"
per line, with --make) with fields
    code, make, description_en [, description_ar] [, severity] [, system]
(`make` may instead be given with --make for a single-make file).

Rules:
* only manufacturer-specific codes (P1xxx, P3000-P33FF, B1/B2, C1/C2, U1/U2) are
  accepted — generic codes belong in dtc_definitions.json;
* Arabic: the file's `description_ar` when present; otherwise a glossary translation
  is filled in ONLY when every part of the English text is covered by the curated
  automotive glossary below. Anything else is left empty (the app then shows the
  English text) — no machine guessing;
* existing entries are updated in place; other makes are untouched.

Usage:
    python3 tools/import_oem_dtcs.py FILE --source "Vendor X dataset v3" --license "Commercial licence #123" [--make hyundai] [--dry-run]
Then run tools/sync_shared.sh to copy the KB into the app.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "shared" / "kb" / "dtc_oem.json"
CODE_RE = re.compile(r"^[PCBU][0-9A-F]{4}$")

# Curated automotive Arabic (Saudi workshop wording). Arabic is produced ONLY when the
# whole English text matches a template exactly: a full phrase, or
# <component> [number | Bank n Sensor n] [fault suffix]. Anything else → left empty.
PHRASES: list[tuple[str, str]] = [
    (r"Random/Multiple Cylinder Misfire Detected", "خلل إشعال عشوائي أو في عدة سلندرات (تفتفة)"),
    (r"Cylinder (\d+) Misfire Detected", r"خلل إشعال (تفتفة) في السلندر رقم \1"),
    (r"System Too Lean(?: \(?Bank (\d)\)?)?", "خليط الوقود فقير (هواء زائد)"),
    (r"System Too Rich(?: \(?Bank (\d)\)?)?", "خليط الوقود غني (وقود زائد)"),
    (r"Catalyst System Efficiency Below Threshold(?: \(?Bank (\d)\)?)?", "ضعف كفاءة دبة التلوث (المحول الحفاز) عن الحد المسموح"),
]
COMPONENTS: list[tuple[str, str]] = [
    (r"Mass Air Flow(?: \(MAF\))? Sensor|MAF Sensor", "حساس تدفق الهواء (MAF)"),
    (r"Manifold Absolute Pressure(?: \(MAP\))? Sensor|MAP Sensor", "حساس ضغط ثلاجة المحرك (MAP)"),
    (r"Intake Air Temperature(?: \(IAT\))? Sensor|IAT Sensor", "حساس حرارة الهواء الداخل (IAT)"),
    (r"Engine Coolant Temperature(?: \(ECT\))? Sensor|ECT Sensor", "حساس حرارة ماء المحرك (ECT)"),
    (r"Throttle Position(?: \(TP\))? Sensor|TP Sensor|TPS", "حساس بوابة الهواء (TPS)"),
    (r"Accelerator Pedal Position Sensor", "حساس دعسة البنزين (APP)"),
    (r"Heated Oxygen Sensor|HO2S", "حساس الأكسجين المسخّن"),
    (r"Oxygen Sensor|O2 Sensor", "حساس الأكسجين"),
    (r"Crankshaft Position(?: \(CKP\))? Sensor|CKP Sensor|CKP", "حساس عمود الكرنك (CKP)"),
    (r"Camshaft Position(?: \(CMP\))? Sensor|CMP Sensor|CMP", "حساس عمود الكامات (CMP)"),
    (r"Knock Sensor", "حساس الطرق"),
    (r"Vehicle Speed Sensor|VSS", "حساس سرعة السيارة (VSS)"),
    (r"Wheel Speed Sensor", "حساس سرعة العجلة"),
    (r"Fuel Pump", "طرمبة الوقود"),
    (r"Ignition Coil", "كويل الإشعال"),
    (r"Fuel Injector|Injector", "بخاخ الوقود"),
    (r"Shift Solenoid", "بلف تبديل القير (سولونويد)"),
    (r"Torque Converter Clutch(?: Solenoid)?|TCC(?: Solenoid)?", "كلتش طنجرة القير"),
    (r"EGR Valve|EGR", "صمام إعادة تدوير العادم (EGR)"),
    (r"ECM|PCM", "كمبيوتر المحرك (ECM/PCM)"),
    (r"TCM", "كمبيوتر القير (TCM)"),
]
SUFFIXES: list[tuple[str, str]] = [
    (r"Circuit Low(?: Input| Voltage)?", "انخفاض الجهد في دائرة {c}"),
    (r"Circuit High(?: Input| Voltage)?", "ارتفاع الجهد في دائرة {c}"),
    (r"Circuit Open", "قطع في دائرة {c}"),
    (r"Circuit Short [Tt]o Ground", "التماس دائرة {c} مع الأرضي (السالب)"),
    (r"Circuit Short [Tt]o Battery", "التماس دائرة {c} مع موجب البطارية"),
    (r"Circuit Intermittent", "تقطّع في إشارة دائرة {c}"),
    (r"Circuit Malfunction", "خلل في دائرة {c}"),
    (r"Circuit Range/Performance(?: Problem)?", "قراءة خارج النطاق في دائرة {c}"),
    (r"Range/Performance(?: Problem)?", "قراءة خارج النطاق من {c}"),
    (r"Circuit", "دائرة {c}"),
    (r"Malfunction", "خلل في {c}"),
    (r"Intermittent", "تقطّع في {c}"),
    (r"No Signal", "لا توجد إشارة من {c}"),
    (r"", "{c}"),
]


def glossary_ar(text: str) -> str | None:
    """Arabic for [text] only when it matches a template EXACTLY; otherwise None."""
    t = re.sub(r"\s+", " ", text.strip())
    for pat, ar in PHRASES:
        m = re.fullmatch(pat, t, flags=re.IGNORECASE)
        if m:
            out = m.expand(ar) if "\\" in ar else ar
            bank = next((g for g in m.groups() if g), None) if m.groups() else None
            return f"{out} (الجهة {bank})" if bank and "Bank" in t else out
    for cpat, car in COMPONENTS:
        for spat, sar in SUFFIXES:
            full = rf"(?:{cpat})(?: (\d))?(?: Bank (\d),? Sensor (\d))?" + (rf" {spat}" if spat else "")
            m = re.fullmatch(full, t, flags=re.IGNORECASE)
            if not m:
                continue
            num, bank, sensor = m.groups()[:3]
            comp = car + (f" {num}" if num else "") + (f" (الجهة {bank} - الحساس {sensor})" if bank else "")
            return sar.format(c=comp)
    return None


def is_manufacturer_specific(code: str) -> bool:
    c = code.upper()
    if not CODE_RE.match(c):
        return False
    if c[0] == "P":
        return c[1] == "1" or (c[1] == "3" and c[2] in "0123")
    return c[1] in "12"


def read_rows(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8-sig")
    if path.suffix.lower() == ".txt":  # "P1100 - Description" per line
        rows = []
        for line in text.splitlines():
            m = re.match(r"^\s*([PCBU][0-9A-Fa-f]{4})\s*[-:]\s*(.+?)\s*$", line)
            if m:
                rows.append({"code": m.group(1).upper(), "description_en": m.group(2)})
        return rows
    if path.suffix.lower() == ".json":
        data = json.loads(text)
        return data if isinstance(data, list) else data.get("codes", [])
    return list(csv.DictReader(text.splitlines()))


def import_rows(rows: list[dict], kb: dict, *, source: str, license_: str, default_make: str | None, verified: bool = False) -> dict:
    """Merge rows into the overlay [kb]; returns counters. Pure (no file I/O)."""
    stats = {"imported": 0, "skipped_generic": 0, "skipped_invalid": 0, "ar_from_file": 0, "ar_glossary": 0, "ar_empty": 0}
    profiles = {p["make"]: p for p in kb.setdefault("profiles", [])}
    for r in rows:
        g = {k.strip().lower(): (v or "").strip() if isinstance(v, str) else v for k, v in r.items()}
        code = str(g.get("code") or g.get("dtc") or "").upper()
        make = str(g.get("make") or default_make or "").strip().lower()
        en = str(g.get("description_en") or g.get("description") or g.get("en") or "").strip()
        if not CODE_RE.match(code) or not make or not en:
            stats["skipped_invalid"] += 1
            continue
        if not is_manufacturer_specific(code):
            stats["skipped_generic"] += 1
            continue
        ar = str(g.get("description_ar") or g.get("ar") or "").strip()
        if ar:
            stats["ar_from_file"] += 1
        else:
            ar = glossary_ar(en) or ""
            stats["ar_glossary" if ar else "ar_empty"] += 1
        prof = profiles.get(make)
        if prof is None:
            prof = {"make": make, "aliases": [], "source": source, "license": license_, "verified": verified, "codes": {}}
            kb["profiles"].append(prof)
            profiles[make] = prof
        entry = {"en": en}
        if ar:
            entry["ar"] = ar
        # Provenance lives on the profile; only record it per code when it differs.
        for k, v in (("source", source), ("license", license_), ("verified", verified)):
            if prof.get(k) != v:
                entry[k] = v
        for k in ("severity", "system"):
            if g.get(k):
                entry[k] = g[k]
        prof["codes"][code] = entry
        stats["imported"] += 1
    return stats


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("file", type=Path)
    ap.add_argument("--source", required=True, help="where the data comes from (dataset/vendor + version)")
    ap.add_argument("--license", required=True, help="the licence that allows using it")
    ap.add_argument("--make", help="make for a single-make file (e.g. hyundai)")
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--verified", action="store_true",
                    help="only for data confirmed against the manufacturer's service information")
    a = ap.parse_args(argv)
    kb = json.loads(a.out.read_text(encoding="utf-8")) if a.out.is_file() else {"version": "", "profiles": []}
    stats = import_rows(read_rows(a.file), kb, source=a.source, license_=a.license, default_make=a.make, verified=a.verified)
    print(json.dumps(stats, ensure_ascii=False))
    if not a.dry_run:
        a.out.write_text(json.dumps(kb, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"wrote {a.out} — now run tools/sync_shared.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
