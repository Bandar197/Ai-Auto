"""Locate the repository-level `shared/` directory (PID table, KB, scenarios)."""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=1)
def shared_dir() -> Path:
    env = os.environ.get("AUTOMIND_SHARED_DIR")
    if env:
        p = Path(env)
        if (p / "obd" / "pids.json").is_file():
            return p
        raise FileNotFoundError(f"AUTOMIND_SHARED_DIR={env} does not contain obd/pids.json")
    here = Path(__file__).resolve()
    for parent in here.parents:
        cand = parent / "shared"
        if (cand / "obd" / "pids.json").is_file():
            return cand
    raise FileNotFoundError("Could not find shared/ directory; set AUTOMIND_SHARED_DIR")
