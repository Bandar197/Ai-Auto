#!/usr/bin/env python3
"""Validate the module-address registry (shared/obd/modules.json), stdlib only.

Checks structure, CAN id format vs id_bits, category/verified types, unique make/alias
keys and unique module keys per profile. Exits non-zero on any error.

    python3 tools/validate_modules.py shared/obd/modules.json
"""
import json
import re
import sys

CATEGORIES = {"airbag", "abs", "other"}
ARABIC_RE = re.compile(r"[؀-ۿ]")
PROTOCOLS = set("0123456789ABC")


def _valid_can_id(value: str, id_bits: int) -> bool:
    if not isinstance(value, str) or not re.fullmatch(r"[0-9A-Fa-f]+", value):
        return False
    n = int(value, 16)
    return 0 <= n <= (0x1FFFFFFF if id_bits == 29 else 0x7FF)


def validate(doc: dict) -> list[str]:
    errors: list[str] = []
    if not isinstance(doc.get("profiles"), list) or not doc["profiles"]:
        return ["top-level: 'profiles' must be a non-empty array"]
    seen_keys: set[str] = set()
    makes = 0
    for pi, prof in enumerate(doc["profiles"]):
        where = f"profiles[{pi}]"
        make = prof.get("make")
        if not isinstance(make, str) or not make:
            errors.append(f"{where}: missing 'make'")
            continue
        keys = [make.lower(), *[a.lower() for a in prof.get("aliases", []) if isinstance(a, str)]]
        for k in keys:
            if k in seen_keys:
                errors.append(f"{where}: make/alias '{k}' already used by another profile")
            seen_keys.add(k)
        if make != "generic":
            makes += 1
        proto = prof.get("protocol")
        if proto is not None and (not isinstance(proto, str) or proto.upper() not in PROTOCOLS):
            errors.append(f"{where}: invalid protocol {proto!r}")
        mods = prof.get("modules")
        if not isinstance(mods, list) or not mods:
            errors.append(f"{where}: 'modules' must be a non-empty array")
            continue
        mod_keys: set[str] = set()
        for mi, m in enumerate(mods):
            mw = f"{where}.modules[{mi}]"
            if not isinstance(m, dict):
                errors.append(f"{mw}: must be an object")
                continue
            key = m.get("key")
            if not isinstance(key, str) or not key:
                errors.append(f"{mw}: missing 'key'")
            elif key in mod_keys:
                errors.append(f"{mw}: duplicate module key '{key}' in this profile")
            else:
                mod_keys.add(key)
            bits = m.get("id_bits")
            if bits not in (11, 29):
                errors.append(f"{mw}: id_bits must be 11 or 29")
                bits = 11
            for fld in ("request", "response"):
                if not _valid_can_id(m.get(fld, ""), bits):
                    errors.append(f"{mw}: '{fld}' is not a valid {bits}-bit CAN id: {m.get(fld)!r}")
            if m.get("category") not in CATEGORIES:
                errors.append(f"{mw}: category must be one of {sorted(CATEGORIES)}")
            if not isinstance(m.get("verified"), bool):
                errors.append(f"{mw}: 'verified' must be a boolean")
            for fld in ("name_en", "name_ar"):
                if not isinstance(m.get(fld), str) or not m[fld].strip():
                    errors.append(f"{mw}: missing '{fld}'")
            if isinstance(m.get("name_ar"), str) and not ARABIC_RE.search(m["name_ar"]):
                errors.append(f"{mw}: 'name_ar' has no Arabic letters")
    if "generic" not in seen_keys:
        errors.append("a 'generic' profile is required (tried for every vehicle)")
    return errors


def main(argv: list[str]) -> int:
    path = argv[1] if len(argv) > 1 else "shared/obd/modules.json"
    try:
        doc = json.loads(open(path, encoding="utf-8").read())
    except (OSError, json.JSONDecodeError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    errors = validate(doc)
    n_profiles = len(doc.get("profiles", []))
    n_modules = sum(len(p.get("modules", [])) for p in doc.get("profiles", []))
    n_verified = sum(1 for p in doc.get("profiles", []) for m in p.get("modules", []) if m.get("verified"))
    print(f"profiles: {n_profiles}   modules: {n_modules}   verified: {n_verified}")
    for e in errors:
        print(f"ERROR: {e}")
    if errors:
        print(f"FAILED: {len(errors)} error(s)")
        return 1
    print("OK: module registry valid")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
