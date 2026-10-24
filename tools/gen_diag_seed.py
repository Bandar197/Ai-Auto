#!/usr/bin/env python3
"""Generate the idempotent seed migration for ``automind.diag_controller_catalog``.

``shared/diag/controller_identifiers.json`` is the single source of truth: it holds
the UNVERIFIED STATIC IDENTIFIERS (module-group names per manufacturer) extracted by
static string analysis. These are NOT CAN addresses and NOT proof that an ECU is
readable — every row is seeded with ``verification_status = 'unverified'``.

Run from the repository root::

    python3 tools/gen_diag_seed.py

It (re)writes ``supabase/migrations/20261024120100_automind_seed_diag_controllers.sql``
with one idempotent ``insert ... on conflict (id) do nothing`` statement.
"""

from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE = REPO_ROOT / "shared" / "diag" / "controller_identifiers.json"
OUTPUT = REPO_ROOT / "supabase" / "migrations" / "20261024120100_automind_seed_diag_controllers.sql"

ID_PREFIX = "diag"  # not used for ids, kept for clarity


def _sql_str(value: str) -> str:
    """A single-quoted SQL string literal with quotes doubled."""
    return "'" + value.replace("'", "''") + "'"


def _label(identifier: str, make: str) -> str:
    """A human-readable label derived from the identifier (deterministic)."""
    stem = identifier
    if stem.startswith(make + "_"):
        stem = stem[len(make) + 1 :]
    return stem.replace("_", " ").strip().title() or identifier.replace("_", " ").title()


def build_sql() -> tuple[str, int]:
    doc = json.loads(SOURCE.read_text(encoding="utf-8"))
    identifiers = doc["identifiers"]
    source = doc.get("source", {})
    source_type = source.get("source_type", "static_identifier")
    source_reference = source.get("source_reference", "")

    seen: set[str] = set()
    rows: list[str] = []
    for entry in identifiers:
        ident = entry["id"]
        make = entry["make"]
        category = entry["category"]
        status = entry.get("verification_status", "unverified")
        if status != "unverified":
            raise SystemExit(f"identifier {ident!r} is not 'unverified' (got {status!r}); refusing to seed")
        if ident in seen:
            raise SystemExit(f"duplicate identifier id in source JSON: {ident!r}")
        seen.add(ident)
        rows.append(
            "  ("
            + ", ".join(
                (
                    _sql_str(ident),
                    _sql_str(make),
                    _sql_str(category),
                    _sql_str(_label(ident, make)),
                    _sql_str(source_type),
                    _sql_str(source_reference),
                )
            )
            + ")"
        )

    header = f"""-- =============================================================================
-- AutoMind AI — seed: controller identifier catalogue (diag_controller_catalog)
--
-- GENERATED FILE — do not edit by hand.
-- Source of truth: shared/diag/controller_identifiers.json
-- Regenerate with:  python3 tools/gen_diag_seed.py
--
-- {len(rows)} UNVERIFIED STATIC IDENTIFIERS (module-group names per manufacturer).
-- These are NOT CAN addresses and NOT proof that an ECU is readable — every row is
-- verification_status = 'unverified'. Idempotent: safe to re-run.
-- =============================================================================

insert into automind.diag_controller_catalog
  (id, make, category, label, source_type, source_reference)
values
"""
    body = ",\n".join(rows)
    return header + body + "\non conflict (id) do nothing;\n", len(rows)


def main() -> None:
    sql, count = build_sql()
    OUTPUT.write_text(sql, encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(REPO_ROOT)} with {count} controller rows")


if __name__ == "__main__":
    main()
