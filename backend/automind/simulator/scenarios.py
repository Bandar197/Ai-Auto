"""Demo/test scenarios (shared/scenarios/*.json)."""

from __future__ import annotations

import json
from functools import cache
from typing import Any

from automind.shared_paths import shared_dir


@cache
def load_scenario(key: str) -> dict[str, Any]:
    if not key.replace("_", "").isalnum():
        raise ValueError("invalid scenario key")
    path = shared_dir() / "scenarios" / f"{key}.json"
    if not path.is_file():
        raise KeyError(f"unknown scenario {key!r}")
    return json.loads(path.read_text(encoding="utf-8"))


def scenario_keys() -> list[str]:
    idx = json.loads((shared_dir() / "scenarios" / "index.json").read_text(encoding="utf-8"))
    return list(idx["scenarios"])


def list_scenarios() -> list[dict[str, Any]]:
    out = []
    for k in scenario_keys():
        s = load_scenario(k)
        out.append({
            "key": k,
            "name_en": s["name_en"], "name_ar": s["name_ar"],
            "description_en": s["description_en"], "description_ar": s["description_ar"],
            "dtcs": s.get("dtcs", []),
        })
    return out
