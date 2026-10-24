#!/usr/bin/env python3
"""Validate the controller-identifier catalogue (shared/diag/controller_identifiers.json).

These are UNVERIFIED static identifiers (module-group names per manufacturer), not CAN
addresses or readable ECUs. Checks structure, id format, uniqueness, and that every entry
stays verification_status="unverified" (field data is never asserted from this source).

    python3 tools/validate_controllers.py shared/diag/controller_identifiers.json
"""
import json
import re
import sys

ID_RE = re.compile(r"^[a-z0-9_]+$")
CATEGORIES = {
    "airbag", "abs", "engine", "transmission", "steering", "body",
    "network", "hybrid_ev", "tpms", "adas", "other",
}
# Expected per-manufacturer counts from the source analysis (total 459).
EXPECTED = {
    "bmw": 32, "chevrolet": 20, "daihatsu": 19, "ford": 58, "generic_or_unspecified": 16,
    "honda": 9, "hyundai": 55, "lada": 3, "mazda": 17, "mitsubishi": 39, "nissan": 37,
    "renault": 40, "subaru": 14, "suzuki": 22, "toyota": 78,
}


def validate(doc: dict) -> list[str]:
    errors: list[str] = []
    ids = doc.get("identifiers")
    if not isinstance(ids, list) or not ids:
        return ["'identifiers' must be a non-empty array"]
    seen: set[str] = set()
    counts: dict[str, int] = {}
    for i, e in enumerate(ids):
        where = f"identifiers[{i}]"
        if not isinstance(e, dict):
            errors.append(f"{where}: must be an object")
            continue
        cid = e.get("id")
        if not isinstance(cid, str) or not ID_RE.match(cid or ""):
            errors.append(f"{where}: invalid id {cid!r}")
        elif cid in seen:
            errors.append(f"{where}: duplicate id {cid!r}")
        else:
            seen.add(cid)
        make = e.get("make")
        if not isinstance(make, str) or not make:
            errors.append(f"{where}: missing make")
        else:
            counts[make] = counts.get(make, 0) + 1
        if e.get("category") not in CATEGORIES:
            errors.append(f"{where}: invalid category {e.get('category')!r}")
        if e.get("verification_status") != "unverified":
            errors.append(f"{where}: verification_status must be 'unverified' (this source is never field-verified)")
    if len(seen) != 459:
        errors.append(f"expected 459 unique identifiers, got {len(seen)}")
    for make, n in EXPECTED.items():
        if counts.get(make, 0) != n:
            errors.append(f"manufacturer '{make}': expected {n}, got {counts.get(make, 0)}")
    return errors


def main(argv: list[str]) -> int:
    path = argv[1] if len(argv) > 1 else "shared/diag/controller_identifiers.json"
    try:
        doc = json.loads(open(path, encoding="utf-8").read())
    except (OSError, json.JSONDecodeError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    errors = validate(doc)
    ids = doc.get("identifiers", [])
    makes = len({e.get("make") for e in ids if isinstance(e, dict)})
    print(f"identifiers: {len(ids)}   manufacturers: {makes}")
    for e in errors:
        print(f"ERROR: {e}")
    if errors:
        print(f"FAILED: {len(errors)} error(s)")
        return 1
    print("OK: controller catalogue valid (459 unverified identifiers)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
