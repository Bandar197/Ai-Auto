#!/usr/bin/env bash
# Contact sheet for QA: render/sheet.sh <video> <t1,t2,...> [cols] [cc]
set -e
cd "$(dirname "$0")/.."
v=$1; times=$2; cols=${3:-4}; cc=${4:-0}
d=out/shots/$v; rm -rf "$d"; mkdir -p "$d"
node render/shot.mjs "$v" "$times" "$d" 0.5 "$cc" | grep -v "^/" || true
n=$(ls "$d" | wc -l); rows=$(( (n + cols - 1) / cols ))
ffmpeg -v error -y -pattern_type glob -i "$d/*.jpg" -vf "tile=${cols}x${rows}:padding=6" -q:v 3 "out/shots/$v-sheet.jpg"
echo "out/shots/$v-sheet.jpg"
