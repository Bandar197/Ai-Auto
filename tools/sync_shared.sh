#!/usr/bin/env bash
# Mirror the shared contracts (OBD tables, demo scenarios, KB, JSON schemas)
# into the Flutter app's bundled assets. Run after editing anything in shared/.
# mobile/test/shared_assets_sync_test.dart fails when the copies drift.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/shared"
DST="$ROOT/mobile/assets/shared"

for sub in obd scenarios kb schemas; do
  mkdir -p "$DST/$sub"
  # Remove stale JSON copies first so deleted shared files disappear too.
  find "$DST/$sub" -maxdepth 1 -type f -name '*.json' -delete
  shopt -s nullglob
  files=("$SRC/$sub"/*.json)
  shopt -u nullglob
  if [ ${#files[@]} -gt 0 ]; then
    cp "${files[@]}" "$DST/$sub/"
  fi
  # Keep empty folders registered as Flutter asset directories.
  touch "$DST/$sub/.gitkeep"
  echo "synced $sub: ${#files[@]} file(s)"
done
