#!/usr/bin/env python3
"""Validate the AutoMind AI DTC knowledge base (stdlib only).

Usage:
    python3 tools/validate_kb.py shared/kb/dtc_definitions.json shared/obd/pids.json

Checks code format, required fields, enum values, related_signals against the
signal keys declared in pids.json (pids[].outputs[].key), presence of Arabic
text, absence of manufacturer-specific P1xxx codes, and at least one common
cause per code. Prints statistics and exits non-zero if any error is found.
"""
import json
import re
import sys
from collections import Counter

CODE_RE = re.compile(r"^[PCBU][0-9A-F]{4}$")
ARABIC_RE = re.compile(r"[؀-ۿ]")
SYSTEMS = {"powertrain", "chassis", "body", "network"}
SUBSYSTEMS = {
    "fuel", "air_intake", "ignition", "emissions", "cooling", "charging", "transmission",
    "engine", "electrical", "network", "evap", "exhaust", "sensors", "idle_control",
    "ac", "body", "chassis",
}
SEVERITIES = ["info", "low", "medium", "high", "critical"]
SYSTEM_BY_LETTER = {"P": "powertrain", "C": "chassis", "B": "body", "U": "network"}
REQUIRED = {
    "system": str, "subsystem": str, "en": str, "ar": str, "severity": str,
    "drivable": bool, "related_signals": list, "common_causes": list,
}
TOP_REQUIRED = ("kb_version", "source", "codes")


def load_signal_keys(pids_path):
    with open(pids_path, encoding="utf-8") as f:
        pids = json.load(f)
    keys = set()
    for pid in pids.get("pids", []):
        for out in pid.get("outputs", []):
            if "key" in out:
                keys.add(out["key"])
    return keys


def validate(kb, signal_keys):
    errors, warnings = [], []
    for k in TOP_REQUIRED:
        if k not in kb:
            errors.append(f"top-level: missing '{k}'")
    codes = kb.get("codes")
    if not isinstance(codes, dict) or not codes:
        errors.append("top-level: 'codes' must be a non-empty object")
        return errors, warnings

    keys = list(codes)
    if keys != sorted(keys):
        warnings.append("codes are not sorted")

    for code, d in codes.items():
        where = f"{code}:"
        if not CODE_RE.match(code):
            errors.append(f"{where} invalid code format")
            continue
        if code[0] == "P" and code[1] == "1":
            errors.append(f"{where} manufacturer-specific P1xxx code not allowed")
        if code[0] == "P" and code[1] == "3" and code[2] in "0123":
            errors.append(f"{where} manufacturer-specific P30xx-P33xx code not allowed")
        if not isinstance(d, dict):
            errors.append(f"{where} entry must be an object")
            continue
        for field, typ in REQUIRED.items():
            if field not in d:
                errors.append(f"{where} missing field '{field}'")
            elif not isinstance(d[field], typ):
                errors.append(f"{where} field '{field}' must be {typ.__name__}")
        extra = set(d) - set(REQUIRED)
        if extra:
            warnings.append(f"{where} unknown fields {sorted(extra)}")

        if d.get("system") not in SYSTEMS:
            errors.append(f"{where} invalid system {d.get('system')!r}")
        elif d["system"] != SYSTEM_BY_LETTER[code[0]]:
            errors.append(f"{where} system {d['system']!r} does not match code letter {code[0]}")
        if d.get("subsystem") not in SUBSYSTEMS:
            errors.append(f"{where} invalid subsystem {d.get('subsystem')!r}")
        if d.get("severity") not in SEVERITIES:
            errors.append(f"{where} invalid severity {d.get('severity')!r}")
        if d.get("severity") == "critical" and d.get("drivable") is True:
            warnings.append(f"{where} critical severity but drivable=true")

        en, ar = d.get("en"), d.get("ar")
        if isinstance(en, str):
            if not en.strip():
                errors.append(f"{where} empty 'en'")
            elif ARABIC_RE.search(en):
                errors.append(f"{where} 'en' contains Arabic text")
        if isinstance(ar, str) and not ARABIC_RE.search(ar):
            errors.append(f"{where} 'ar' contains no Arabic letters")

        sigs = d.get("related_signals")
        if isinstance(sigs, list):
            if not sigs:
                warnings.append(f"{where} no related_signals")
            if len(sigs) != len(set(sigs)):
                errors.append(f"{where} duplicate related_signals")
            for s in sigs:
                if s not in signal_keys:
                    errors.append(f"{where} unknown related_signal {s!r} (not in pids.json outputs)")

        causes = d.get("common_causes")
        if isinstance(causes, list):
            if not causes:
                errors.append(f"{where} needs at least one common cause")
            for i, c in enumerate(causes):
                if not isinstance(c, dict) or not isinstance(c.get("en"), str) or not isinstance(c.get("ar"), str):
                    errors.append(f"{where} common_causes[{i}] must have string 'en' and 'ar'")
                    continue
                if not c["en"].strip():
                    errors.append(f"{where} common_causes[{i}] empty 'en'")
                if not ARABIC_RE.search(c["ar"]):
                    errors.append(f"{where} common_causes[{i}] 'ar' contains no Arabic letters")
    return errors, warnings


def print_stats(kb):
    codes = kb["codes"]
    print(f"kb_version: {kb.get('kb_version')}   total codes: {len(codes)}")
    by_range = Counter()
    for c in codes:
        by_range[c[:3] + "xx"] += 1
    print("by range:  " + ", ".join(f"{r}={n}" for r, n in sorted(by_range.items())))
    for field in ("system", "subsystem", "severity"):
        cnt = Counter(d.get(field) for d in codes.values())
        print(f"by {field}: " + ", ".join(f"{k}={v}" for k, v in sorted(cnt.items(), key=lambda x: (-x[1], str(x[0])))))
    nd = sum(1 for d in codes.values() if d.get("drivable") is False)
    nc = sum(len(d.get("common_causes", [])) for d in codes.values())
    print(f"not drivable: {nd}   total causes: {nc}   avg causes/code: {nc / max(len(codes), 1):.1f}")


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    kb_path, pids_path = argv[1], argv[2]
    try:
        with open(kb_path, encoding="utf-8") as f:
            kb = json.load(f)
        signal_keys = load_signal_keys(pids_path)
    except (OSError, json.JSONDecodeError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    errors, warnings = validate(kb, signal_keys)
    if isinstance(kb.get("codes"), dict) and kb["codes"]:
        print_stats(kb)
    for w in warnings:
        print(f"WARNING: {w}")
    for e in errors:
        print(f"ERROR: {e}")
    if errors:
        print(f"FAILED: {len(errors)} error(s), {len(warnings)} warning(s)")
        return 1
    print(f"OK: {len(kb['codes'])} codes valid ({len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
