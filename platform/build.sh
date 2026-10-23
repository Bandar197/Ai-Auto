#!/bin/sh
# Copies the shared game engine into the site and the server function.
set -e
cd "$(dirname "$0")"
cp shared/engine.js site/engine.js
cp shared/engine.js supabase/functions/game/engine.js
echo "engine copied"
