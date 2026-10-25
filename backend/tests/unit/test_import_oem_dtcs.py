"""tools/import_oem_dtcs.py: only manufacturer codes, provenance recorded, no guessed Arabic."""

import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "import_oem_dtcs", Path(__file__).resolve().parents[3] / "tools" / "import_oem_dtcs.py"
)
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)


def test_glossary_only_when_fully_covered():
    assert mod.glossary_ar("Cylinder 3 Misfire Detected") == "خلل إشعال (تفتفة) في السلندر رقم 3"
    assert mod.glossary_ar("Knock Sensor 3 Circuit") == "دائرة حساس الطرق 3"
    assert mod.glossary_ar("Oxygen Sensor Bank 1 Sensor 2 Circuit Malfunction") == "خلل في دائرة حساس الأكسجين (الجهة 1 - الحساس 2)"
    assert mod.glossary_ar("HO2S11 Heater Circuit High Voltage") is None
    assert mod.glossary_ar("Glow Relay Stuck On") is None  # not fully covered → left empty


def test_import_rows():
    kb = {"profiles": []}
    rows = [
        {"code": "P1326", "make": "Hyundai", "description_en": "Knock Sensor Circuit Malfunction"},
        {"code": "P1100", "make": "ford", "description_en": "Something proprietary", "description_ar": "وصف من الملف"},
        {"code": "P0300", "make": "ford", "description_en": "generic"},  # generic → rejected
        {"code": "X123", "make": "ford", "description_en": "bad"},
        {"code": "B1620", "make": "", "description_en": "no make"},
    ]
    s = mod.import_rows(rows, kb, source="test set", license_="CC-BY-4.0", default_make=None)
    assert s == {"imported": 2, "skipped_generic": 1, "skipped_invalid": 2, "ar_from_file": 1, "ar_glossary": 1, "ar_empty": 0}
    hy = next(p for p in kb["profiles"] if p["make"] == "hyundai")
    assert hy["codes"]["P1326"]["ar"] == "خلل في دائرة حساس الطرق"
    assert hy["license"] == "CC-BY-4.0" and hy["verified"] is False  # provenance on the profile
    assert next(p for p in kb["profiles"] if p["make"] == "ford")["codes"]["P1100"]["ar"] == "وصف من الملف"


def test_unknown_words_leave_arabic_empty():
    kb = {"profiles": []}
    s = mod.import_rows([{"code": "P1999", "make": "kia", "description_en": "Proprietary widget fault"}], kb,
                        source="s", license_="l", default_make=None)
    assert s["ar_empty"] == 1
    assert "ar" not in kb["profiles"][0]["codes"]["P1999"]
