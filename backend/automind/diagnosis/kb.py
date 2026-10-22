"""DTC knowledge base (shared/kb/dtc_definitions.json).

Never invents a description: unknown codes return None and are reported as
unknown, with only their structural meaning (system letter, generic vs
manufacturer-specific range).
"""

from __future__ import annotations

import json
from functools import lru_cache
from typing import Any

from automind.shared_paths import shared_dir

_SYSTEMS = {"P": "powertrain", "C": "chassis", "B": "body", "U": "network"}


class KnowledgeBase:
    def __init__(self, data: dict[str, Any] | None):
        data = data or {}
        self.version: str = data.get("kb_version", "none")
        self.source: str = data.get("source", "")
        self._codes: dict[str, dict[str, Any]] = data.get("codes", {})

    def __len__(self) -> int:
        return len(self._codes)

    def lookup(self, code: str) -> dict[str, Any] | None:
        code = code.strip().upper()
        d = self._codes.get(code)
        if d is None:
            return None
        return {"code": code, **d}

    def search(self, q: str, limit: int = 20) -> list[dict[str, Any]]:
        q = q.strip().lower()
        if not q:
            return []
        out = []
        for code, d in self._codes.items():
            if q in code.lower() or q in d.get("en", "").lower() or q in d.get("ar", ""):
                out.append({"code": code, **d})
                if len(out) >= limit:
                    break
        return out

    @staticmethod
    def structure(code: str) -> dict[str, Any]:
        """What the code's format alone tells us (SAE J2012 structure)."""
        code = code.upper()
        system = _SYSTEMS.get(code[:1], "unknown")
        generic = code[1] in "02" or (code[0] == "P" and code[1] == "3" and code[2] in "4567")
        return {"system": system, "is_generic": generic}


@lru_cache(maxsize=1)
def get_kb() -> KnowledgeBase:
    path = shared_dir() / "kb" / "dtc_definitions.json"
    if not path.is_file():
        return KnowledgeBase(None)
    return KnowledgeBase(json.loads(path.read_text(encoding="utf-8")))
