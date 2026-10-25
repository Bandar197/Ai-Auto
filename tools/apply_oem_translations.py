#!/usr/bin/env python3
"""Apply reviewed English→Arabic translations to shared/kb/dtc_oem.json.

Input: one or more JSON objects {english_description: arabic}. Only entries that have
no Arabic yet are filled; each filled entry is marked "ar_by": "ai" so the app labels
it as an AI translation (Arabic that came from the source file or the exact glossary
templates is left untouched). Run tools/sync_shared.sh afterwards.

Usage: python3 tools/apply_oem_translations.py out_0.json out_1.json ... [--dry-run]
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "shared" / "kb" / "dtc_oem.json"
ARABIC = re.compile(r"[؀-ۿ]")


def apply(kb: dict, mapping: dict[str, str]) -> dict:
    stats = {"filled": 0, "missing": 0, "rejected": 0}
    for prof in kb.get("profiles", []):
        for e in prof.get("codes", {}).values():
            if e.get("ar"):
                continue
            ar = (mapping.get(e["en"].strip()) or "").strip()
            if not ar:
                stats["missing"] += 1
            elif not ARABIC.search(ar):
                stats["rejected"] += 1  # not Arabic text → leave English
            else:
                e["ar"] = ar
                e["ar_by"] = "ai"
                stats["filled"] += 1
    return stats


def main(argv: list[str]) -> int:
    dry = "--dry-run" in argv
    mapping: dict[str, str] = {}
    for f in [a for a in argv if not a.startswith("--")]:
        mapping.update(json.loads(Path(f).read_text(encoding="utf-8")))
    kb = json.loads(OUT.read_text(encoding="utf-8"))
    stats = apply(kb, mapping)
    print(json.dumps(stats))
    if not dry:
        OUT.write_text(json.dumps(kb, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
