#!/usr/bin/env bash
# Full build of one film:  render/build.sh <seeker|employer> <output-basename>
#   cue sheet → soundtrack → 4K60 master → 1080x1920 → 1080x1920 with burned-in captions (mute-friendly)
# Video passes are skipped when their .video.mp4 already exists (delete it to force a re-render).
set -euo pipefail
cd "$(dirname "$0")/.."
v=$1; name=$2
mkdir -p out/final out/tmp
node render/cues.mjs "$v"
python3 audio/mix.py "$v"
[ -f "out/$v-2160x3840.video.mp4" ]    || node render/render.mjs "$v" --scale 2 --crf 19
[ -f "out/$v-1080x1920-cc.video.mp4" ] || node render/render.mjs "$v" --scale 1 --cc --crf 18

# loudness: static gain to about -14 LUFS (social platforms' target) + true-peak safety limiter
I=$(ffmpeg -hide_banner -nostats -i "out/$v.wav" -af ebur128 -f null - 2>&1 | awk '/I:/{v=$2} END{print v}')
G=$(python3 -c "print(round(max(-6, min(9, -14 - ($I))), 2))")
AF="volume=${G}dB,alimiter=limit=0.84:attack=3:release=60:level=false"
A=(-c:a aac -b:a 256k -ar 48000 -af "$AF")
TAGS=(-colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv -movflags +faststart)
echo "integrated loudness $I LUFS → gain ${G} dB"

ffmpeg -v error -y -i "out/$v-2160x3840.video.mp4" -i "out/$v.wav" -map 0:v -map 1:a -c:v copy "${A[@]}" -shortest -movflags +faststart "out/final/$name-4K-2160x3840-60fps.mp4"
ffmpeg -v error -y -i "out/$v-2160x3840.video.mp4" -i "out/$v.wav" -map 0:v -map 1:a -vf "scale=1080:1920:flags=lanczos" \
  -c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p -g 60 "${TAGS[@]}" "${A[@]}" -shortest "out/final/$name-1080x1920-60fps.mp4"
ffmpeg -v error -y -i "out/$v-1080x1920-cc.video.mp4" -i "out/$v.wav" -map 0:v -map 1:a -c:v copy "${A[@]}" -shortest -movflags +faststart "out/final/$name-1080x1920-captions.mp4"
ls -la out/final/"$name"*
