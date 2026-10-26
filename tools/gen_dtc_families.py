#!/usr/bin/env python3
"""Generate systematic, SAE-pattern DTC families and merge them into the KB.

Only families whose meaning is unambiguously defined by the SAE J2012 numbering
pattern (one code per cylinder/bank/sensor) are generated here, so every added
code has an accurate, standard meaning. Existing curated codes are never
overwritten. Bilingual text and causes are original (general automotive
knowledge), matching the house style of the existing KB.

Usage:
    python3 tools/gen_dtc_families.py            # dry run: prints what would be added
    python3 tools/gen_dtc_families.py --write    # merge into shared/kb/dtc_definitions.json
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

KB = Path(__file__).resolve().parent.parent / "shared" / "kb" / "dtc_definitions.json"

# Arabic cylinder phrase keeps the Gulf-friendly term used across the KB.
def _cyl_ar(n: int) -> str:
    return f"الأسطوانة (السلندر) {n}"


def _hex2(n: int) -> str:
    return f"{n:02X}"


def injector_open() -> dict:
    """P0201–P0212: Injector Circuit/Open, cylinders 1–12 (decimal)."""
    out = {}
    for n in range(1, 13):
        out[f"P02{n:02d}"] = {
            "system": "powertrain",
            "subsystem": "fuel",
            "en": f"Injector Circuit/Open - Cylinder {n}",
            "ar": f"دائرة البخاخ مفتوحة أو بها عطل - {_cyl_ar(n)}",
            "severity": "high",
            "drivable": True,
            "related_signals": ["engine_rpm", "stft_b1", "ltft_b1", "stft_b2", "ltft_b2", "engine_load"],
            "common_causes": [
                {"en": f"Faulty cylinder {n} fuel injector", "ar": f"عطل في بخاخ {_cyl_ar(n)}"},
                {"en": f"Open, shorted or corroded wiring/connector to the cylinder {n} injector",
                 "ar": f"سلك أو وصلة البخاخ مقطوعة أو مقصورة أو متآكلة - {_cyl_ar(n)}"},
                {"en": "Injector driver fault inside the ECM/PCM",
                 "ar": "عطل في دائرة قيادة البخاخ داخل كمبيوتر المحرك ECM/PCM"},
            ],
        }
    return out


def injector_low_high_balance() -> dict:
    """P0261–P0284: per-cylinder injector Low / High / Contribution-Balance (hex, 3 per cylinder)."""
    out = {}
    base = 0x261
    for n in range(1, 13):
        low = base + 3 * (n - 1)
        variants = [
            (low, "Injector Circuit Low", "جهد منخفض في دائرة البخاخ",
             [{"en": "Short to ground in the injector circuit / wiring",
               "ar": "قصر أرضي في دائرة البخاخ أو أسلاكها"},
              {"en": f"Faulty cylinder {n} injector (low internal resistance)",
               "ar": f"عطل في بخاخ {_cyl_ar(n)} (مقاومة داخلية منخفضة)"},
              {"en": "ECM/PCM injector driver fault",
               "ar": "عطل في دائرة قيادة البخاخ داخل كمبيوتر المحرك"}]),
            (low + 1, "Injector Circuit High", "جهد مرتفع في دائرة البخاخ",
             [{"en": "Open circuit or short to voltage in the injector wiring",
               "ar": "دائرة مفتوحة أو قصر بالموجب في أسلاك البخاخ"},
              {"en": f"Faulty cylinder {n} injector or its connector",
               "ar": f"عطل في بخاخ {_cyl_ar(n)} أو وصلته"},
              {"en": "ECM/PCM injector driver fault",
               "ar": "عطل في دائرة قيادة البخاخ داخل كمبيوتر المحرك"}]),
            (low + 2, "Contribution/Balance Fault", "عطل مساهمة/اتزان",
             [{"en": f"Weak, clogged or leaking cylinder {n} injector",
               "ar": f"بخاخ {_cyl_ar(n)} ضعيف أو مسدود أو يسرّب"},
              {"en": f"Low compression or mechanical fault in cylinder {n}",
               "ar": f"ضغط انضغاط منخفض أو خلل ميكانيكي في {_cyl_ar(n)}"},
              {"en": "Fuel delivery problem (pressure/volume) affecting this cylinder",
               "ar": "مشكلة في تغذية الوقود (ضغط/كمية) تؤثر على هذه الأسطوانة"}]),
        ]
        for val, en_suffix, ar_suffix, causes in variants:
            out[f"P0{val:03X}"] = {
                "system": "powertrain",
                "subsystem": "fuel",
                "en": f"Cylinder {n} {en_suffix}",
                "ar": f"{ar_suffix} - {_cyl_ar(n)}",
                "severity": "high" if "Contribution" not in en_suffix else "medium",
                "drivable": True,
                "related_signals": ["engine_rpm", "engine_load", "stft_b1", "ltft_b1", "stft_b2", "ltft_b2"],
                "common_causes": causes,
            }
    return out


def glow_plugs() -> dict:
    """P0671–P0678: diesel glow plug circuit, cylinders 1–8."""
    out = {}
    for n in range(1, 9):
        out[f"P06{0x71 + (n - 1):02X}"] = {
            "system": "powertrain",
            "subsystem": "ignition",
            "en": f"Glow Plug Circuit - Cylinder {n}",
            "ar": f"دائرة شمعة التسخين (الديزل) - {_cyl_ar(n)}",
            "severity": "medium",
            "drivable": True,
            "related_signals": ["engine_rpm", "coolant_temp", "module_voltage"],
            "common_causes": [
                {"en": f"Faulty cylinder {n} glow plug (open or shorted)",
                 "ar": f"عطل في شمعة تسخين {_cyl_ar(n)} (مقطوعة أو مقصورة)"},
                {"en": "Damaged glow plug wiring/connector",
                 "ar": "تلف في أسلاك أو وصلة شمعة التسخين"},
                {"en": "Faulty glow plug control module",
                 "ar": "عطل في وحدة التحكم بشمعات التسخين"},
            ],
        }
    return out


def build() -> dict:
    merged = {}
    for fam in (injector_open(), injector_low_high_balance(), glow_plugs()):
        merged.update(fam)
    return merged


def main(argv: list[str]) -> int:
    write = "--write" in argv
    kb = json.loads(KB.read_text(encoding="utf-8"))
    codes = kb["codes"]
    generated = build()
    new = {k: v for k, v in generated.items() if k not in codes}
    print(f"generated {len(generated)} family codes; {len(new)} are new (not already curated)")
    print("new codes:", ", ".join(sorted(new)))
    if not write:
        print("\n(dry run — pass --write to merge)")
        return 0
    codes.update(new)
    kb["codes"] = {k: codes[k] for k in sorted(codes)}
    kb["kb_version"] = "2026.10.1"
    KB.write_text(json.dumps(kb, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"\nwrote {KB} — total codes now {len(kb['codes'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
