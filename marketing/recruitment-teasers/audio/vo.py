#!/usr/bin/env python3
"""Generate the Saudi voice-over lines (guide track) with word timings.

Each line is synthesised as one sentence so the prosody stays natural, then
`mix.py` cuts it at phrase boundaries and places the phrases on the timeline.
Output: vo/<video>/<id>.wav (48 kHz mono) + vo/<video>/<id>.json (word timings).

To use a human voice actor instead, drop WAV files with the same names into
vo/<video>/ (see README) and re-run mix.py -- the visuals do not change.
"""
import asyncio
import json
import os
import subprocess
import sys
from pathlib import Path

import edge_tts

ROOT = Path(__file__).resolve().parent.parent
VOICE = "ar-SA-HamedNeural"
RATE = "+6%"
PITCH = "-3Hz"

# Diacritics are only hints for the synthesiser; on-screen text carries none.
LINES = {
    "seeker": {
        "a1": "كم مرّة قدَّمت على وظيفة؟ عَشِر؟ خمسين؟ مِيَّة؟",
        "a2": "طيِّب.. تِدري أصلاً سيرتك مناسبة للوظيفة؟",
        "b1": "تتنقَّل بين مواقع الشركات.. تقدِّم وتنتظر.. ولا تِدري وِين فرصتك الحقيقية!",
        "c1": "تخيَّل مكان واحد يجمع لك الوظائف.. ويحلِّل سيرتك.. ويوضِّح لك مدى توافقك مع كل فرصة!",
        "d1": "مو بس تبحث عن وظيفة.. تعرف وِين تناسبك.. وكيف تطوِّر سيرتك.. وتتابع طلباتك.. وحتى الذكاء الاصطناعي يساعدك في رحلة التقديم!",
        "e1": "رحلتك الوظيفية.. تستحق تكون أذكى.",
    },
    "employer": {
        "a1": "عندك وظيفة شاغرة.. وجاك مئات المتقدمين.. بس كيف تعرف مِين الأنسب؟",
        "b1": "فرز سِيَر ذاتية.. ومقابلات.. ومتابعة متقدمين.. ووقت كبير يضيع على مهام متكررة!",
        "c1": "طيِّب.. وِش لو صارت رحلة التوظيف كلها في نظام واحد؟",
        "d1": "من إعلان الوظيفة.. إلى فرز المتقدمين وتحليل السِيَر الذاتية.. والمقابلات الذكية.. وإدارة كل مرحلة.. وحتى مؤشرات تقيس لك أداء التوظيف بالكامل!",
        "e1": "لأن التوظيف الذكي.. مو مجرد نظام.. هو طريقة مختلفة لإدارة المواهب.",
    },
}


async def synth(text: str, mp3: Path):
    kwargs = dict(voice=VOICE, rate=RATE, pitch=PITCH, boundary="WordBoundary")
    proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy")
    if proxy:
        kwargs["proxy"] = proxy
    com = edge_tts.Communicate(text, **kwargs)
    words = []
    with open(mp3, "wb") as f:
        async for chunk in com.stream():
            if chunk["type"] == "audio":
                f.write(chunk["data"])
            elif chunk["type"] == "WordBoundary":
                words.append({
                    "t": round(chunk["offset"] / 1e7, 3),
                    "d": round(chunk["duration"] / 1e7, 3),
                    "w": chunk["text"],
                })
    return words


async def main():
    only = sys.argv[1:] or list(LINES)
    for video in only:
        out = ROOT / "vo" / video
        out.mkdir(parents=True, exist_ok=True)
        for lid, text in LINES[video].items():
            mp3 = out / f"{lid}.mp3"
            words = await synth(text, mp3)
            wav = out / f"{lid}.wav"
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(mp3), "-ar", "48000", "-ac", "1", str(wav)], check=True)
            mp3.unlink()
            dur = float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(wav)]))
            (out / f"{lid}.json").write_text(json.dumps({"text": text, "duration": round(dur, 3), "words": words}, ensure_ascii=False, indent=1))
            print(video, lid, f"{dur:.2f}s", " | ".join(f"{w['t']:.2f} {w['w']}" for w in words))


if __name__ == "__main__":
    asyncio.run(main())
