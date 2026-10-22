"""Time-series features and operating-condition segmentation."""

from __future__ import annotations

import math
import statistics
from bisect import bisect_left
from dataclasses import dataclass

from automind.diagnosis.models import DiagnosticInput


@dataclass(frozen=True)
class Stats:
    n: int
    mean: float
    min: float
    max: float
    std: float
    p05: float
    p50: float
    p95: float

    @staticmethod
    def of(values: list[float]) -> Stats | None:
        if not values:
            return None
        s = sorted(values)

        def q(p: float) -> float:
            k = (len(s) - 1) * p
            lo, hi = math.floor(k), math.ceil(k)
            return s[lo] + (s[hi] - s[lo]) * (k - lo)

        return Stats(
            n=len(s), mean=statistics.fmean(s), min=s[0], max=s[-1],
            std=statistics.pstdev(s) if len(s) > 1 else 0.0, p05=q(0.05), p50=q(0.5), p95=q(0.95),
        )


class Series:
    """Sorted (t_ms, value) series with nearest-sample lookup."""

    def __init__(self, points: list[tuple[int, float]]):
        pts = sorted(points)
        self.t = [p[0] for p in pts]
        self.v = [p[1] for p in pts]

    def __len__(self) -> int:
        return len(self.t)

    def at(self, t_ms: int, max_gap_ms: int = 1500) -> float | None:
        if not self.t:
            return None
        i = bisect_left(self.t, t_ms)
        best = None
        for j in (i - 1, i):
            if 0 <= j < len(self.t):
                gap = abs(self.t[j] - t_ms)
                if gap <= max_gap_ms and (best is None or gap < best[0]):
                    best = (gap, self.v[j])
        return best[1] if best else None


CONDITIONS = ("engine_off", "cold_idle", "warm_idle", "free_rev", "cruise", "accel", "decel", "other")


class Context:
    """Per-sample operating condition, derived from RPM, speed, throttle, coolant."""

    def __init__(self, inp: DiagnosticInput):
        self.inp = inp
        self.series: dict[str, Series] = {k: Series([(s.t_ms, s.value) for s in v]) for k, v in inp.series.items()}
        rpm = self.series.get("engine_rpm")
        self._cond: dict[int, str] = {}
        if rpm:
            spd = self.series.get("vehicle_speed")
            ect = self.series.get("coolant_temp")
            prev_speed: tuple[int, float] | None = None
            for t, r in zip(rpm.t, rpm.v, strict=True):
                v = spd.at(t) if spd else None
                c = ect.at(t, 5000) if ect else None
                cond = "other"
                if r < 300:
                    cond = "engine_off"
                elif (v is None or v < 3) and 450 <= r <= 1150:
                    cond = "warm_idle" if (c is None or c >= 70) else "cold_idle"
                elif (v is None or v < 3) and r > 1400:
                    cond = "free_rev"
                elif v is not None and v >= 25:
                    if prev_speed and t > prev_speed[0]:
                        dv = (v - prev_speed[1]) / ((t - prev_speed[0]) / 1000)
                        cond = "accel" if dv > 1.5 else "decel" if dv < -1.5 else "cruise"
                    else:
                        cond = "cruise"
                if v is not None:
                    prev_speed = (t, v)
                self._cond[t] = cond
        self._rpm = rpm

    @property
    def has_rpm(self) -> bool:
        return bool(self._rpm and len(self._rpm))

    def condition_at(self, t_ms: int) -> str:
        if not self._rpm:
            return "other"
        i = bisect_left(self._rpm.t, t_ms)
        cands = [j for j in (i - 1, i) if 0 <= j < len(self._rpm.t)]
        if not cands:
            return "other"
        j = min(cands, key=lambda k: abs(self._rpm.t[k] - t_ms))
        if abs(self._rpm.t[j] - t_ms) > 2000:
            return "other"
        return self._cond.get(self._rpm.t[j], "other")

    def conditions_seen(self, min_samples: int = 5) -> list[str]:
        counts: dict[str, int] = {}
        for c in self._cond.values():
            counts[c] = counts.get(c, 0) + 1
        return [c for c in CONDITIONS if counts.get(c, 0) >= min_samples]

    def has(self, signal: str, min_samples: int = 3) -> bool:
        s = self.series.get(signal)
        return bool(s and len(s) >= min_samples)

    def values(self, signal: str, conditions: tuple[str, ...] | None = None) -> list[float]:
        s = self.series.get(signal)
        if not s:
            return []
        if conditions is None:
            return list(s.v)
        return [v for t, v in zip(s.t, s.v, strict=True) if self.condition_at(t) in conditions]

    def stats(self, signal: str, conditions: tuple[str, ...] | None = None) -> Stats | None:
        return Stats.of(self.values(signal, conditions))

    def paired(self, a: str, b: str, conditions: tuple[str, ...] | None = None) -> list[tuple[float, float]]:
        sa, sb = self.series.get(a), self.series.get(b)
        if not sa or not sb:
            return []
        out = []
        for t, va in zip(sa.t, sa.v, strict=True):
            if conditions is not None and self.condition_at(t) not in conditions:
                continue
            vb = sb.at(t, 800)
            if vb is not None:
                out.append((va, vb))
        return out

    def correlation(self, a: str, b: str, conditions: tuple[str, ...] | None = None) -> float | None:
        pairs = self.paired(a, b, conditions)
        if len(pairs) < 10:
            return None
        xs, ys = zip(*pairs, strict=True)
        if statistics.pstdev(xs) < 1e-9 or statistics.pstdev(ys) < 1e-9:
            return None
        return statistics.correlation(xs, ys)

    def max_run_time(self) -> float | None:
        s = self.series.get("run_time")
        return max(s.v) if s and len(s) else None

    def dtc_codes(self, statuses: tuple[str, ...] = ("stored", "pending", "permanent")) -> set[str]:
        return {d.code for d in self.inp.dtcs if d.status in statuses}

    def measurement(self, key: str) -> float | None:
        for m in self.inp.measurements:
            if m.key == key:
                return m.value
        return None
