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


def is_manufacturer_specific(code: str) -> bool:
    """SAE J2012: P1xxx, P3000-P33FF, B1/B2, C1/C2, U1/U2 mean different things per make."""
    c = code.strip().upper()
    if len(c) != 5 or c[0] not in "PCBU":
        return False
    if c[0] == "P":
        return c[1] == "1" or (c[1] == "3" and c[2] in "0123")
    return c[1] in "12"


class KnowledgeBase:
    def __init__(self, data: dict[str, Any] | None, oem: dict[str, Any] | None = None):
        data = data or {}
        self.version: str = data.get("kb_version", "none")
        self.source: str = data.get("source", "")
        self._codes: dict[str, dict[str, Any]] = data.get("codes", {})
        # make -> code -> entry, plus alias -> make (shared/kb/dtc_oem.json; licensed imports only)
        self._oem: dict[str, dict[str, dict[str, Any]]] = {}
        self._aliases: dict[str, str] = {}
        for p in (oem or {}).get("profiles", []):
            make = str(p.get("make", "")).lower()
            if not make:
                continue
            self._oem.setdefault(make, {}).update(
                {
                    k.upper(): {
                        **v,
                        "oem_make": make,
                        "oem_source": v.get("source", p.get("source")),
                        "oem_verified": bool(v.get("verified", p.get("verified", False))),
                    }
                    for k, v in p.get("codes", {}).items()
                }
            )
            for a in p.get("aliases", []):
                self._aliases[str(a).lower()] = make

    def __len__(self) -> int:
        return len(self._codes)

    def lookup(self, code: str, make: str | None = None) -> dict[str, Any] | None:
        """The make's own entry first; a generic entry only for a generic code."""
        code = code.strip().upper()
        if make:
            m = make.lower()
            hit = self._oem.get(m, {}).get(code) or self._oem.get(self._aliases.get(m, ""), {}).get(code)
            if hit is not None:
                return {"code": code, **hit}
        if is_manufacturer_specific(code):
            return None
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
        return {"system": system, "is_generic": system != "unknown" and not is_manufacturer_specific(code)}


@lru_cache(maxsize=1)
def get_kb() -> KnowledgeBase:
    path = shared_dir() / "kb" / "dtc_definitions.json"
    oem_path = shared_dir() / "kb" / "dtc_oem.json"
    oem = json.loads(oem_path.read_text(encoding="utf-8")) if oem_path.is_file() else None
    if not path.is_file():
        return KnowledgeBase(None, oem)
    return KnowledgeBase(json.loads(path.read_text(encoding="utf-8")), oem)


@lru_cache(maxsize=1)
def _wmi() -> dict[str, str]:
    p = shared_dir() / "obd" / "wmi.json"
    if not p.is_file():
        return {}
    return {k.upper(): v.lower() for k, v in json.loads(p.read_text(encoding="utf-8")).get("prefixes", {}).items()}


def make_from_vin(vin: str | None) -> str | None:
    """Brand from the VIN's WMI (longest prefix); None when unknown — never guessed."""
    import re

    v = (vin or "").strip().upper()
    if not re.fullmatch(r"[A-HJ-NPR-Z0-9]{17}", v):
        return None
    table = _wmi()
    return table.get(v[:3]) or table.get(v[:2])
