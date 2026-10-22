"""Deterministic, physically plausible vehicle signal model for the ECU simulator.

`VehicleModel.values(t)` is a pure function of elapsed time `t` (seconds) and
the scenario seed, so a simulated session is reproducible.
"""

from __future__ import annotations

import math
import random
from typing import Any

from automind.obd.pids import signal_index


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


class VehicleModel:
    def __init__(self, scenario: dict[str, Any], seed: int = 7):
        self.s = scenario
        self.seed = seed
        self.phases = scenario["drive_cycle"]
        self.cycle_len = sum(p["duration_s"] for p in self.phases)
        self.faults = scenario.get("faults", [])
        self.baro = float(scenario.get("baro_kpa", 100))
        self.ambient = float(scenario.get("ambient_c", 35))
        self.engine_running = True
        self._ranges = {k: (o.min, o.max) for k, (_, o) in signal_index().items()}

    # -------------------------------------------------------------- helpers
    def _noise(self, t: float, key: str, amp: float) -> float:
        # Seeded per 0.1 s tick and signal so values are repeatable.
        r = random.Random(f"{self.seed}:{key}:{int(t * 10)}")
        return (r.random() * 2 - 1) * amp

    def _targets(self, t: float) -> dict[str, float]:
        tc = t % self.cycle_len if self.cycle_len else 0.0
        acc = 0.0
        prev = self.phases[-1]
        for p in self.phases:
            if tc < acc + p["duration_s"]:
                frac = _clamp((tc - acc) / 3.0, 0.0, 1.0)  # 3 s transition
                ease = 0.5 - 0.5 * math.cos(math.pi * frac)
                return {k: prev[k] + (p[k] - prev[k]) * ease for k in ("rpm", "speed", "throttle")} | {
                    "phase": p["phase"]  # type: ignore[dict-item]
                }
            acc += p["duration_s"]
            prev = p
        last = self.phases[-1]
        return {"rpm": last["rpm"], "speed": last["speed"], "throttle": last["throttle"], "phase": last["phase"]}

    # -------------------------------------------------------------- model
    def values(self, t: float) -> dict[str, float]:
        if not self.engine_running:
            return self._engine_off(t)
        tg = self._targets(t)
        rpm = tg["rpm"] + self._noise(t, "rpm", 8)
        speed = max(0.0, tg["speed"] + (self._noise(t, "spd", 0.6) if tg["speed"] > 0 else 0))
        thr = max(0.0, tg["throttle"] + (self._noise(t, "thr", 0.4) if tg["throttle"] > 0 else 0))
        load = _clamp(19 + 0.7 * thr + 0.1 * speed + self._noise(t, "load", 0.8), 0, 100)
        map_kpa = self.baro * (0.12 + 0.0095 * load) + self._noise(t, "map", 0.6)
        ve = 0.5 + 0.008 * load
        maf = (rpm / 120.0) * 3.6 * (map_kpa / self.baro) * 1.18 * ve
        coolant0 = float(self.s.get("initial_coolant_c", 88))
        coolant = coolant0 + 3.5 * (1 - math.exp(-t / 120)) + 1.2 * math.sin(t / 37.0)
        iat = self.ambient + (7 if speed < 5 else 2) + self._noise(t, "iat", 0.4)
        closed_loop = coolant > 55
        o2 = 0.45 + 0.40 * math.tanh(3 * math.sin(2 * math.pi * 1.1 * t)) if closed_loop else 0.1
        stft = 2.2 * math.sin(2 * math.pi * 1.1 * t + 1.2) + self._noise(t, "stft", 0.6)
        v: dict[str, float] = {
            "engine_rpm": rpm,
            "vehicle_speed": speed,
            "engine_load": load,
            "map_kpa": map_kpa,
            "maf_gs": maf,
            "coolant_temp": coolant,
            "intake_air_temp": iat,
            "ambient_temp": self.ambient,
            "throttle_pos": 14.5 + 0.85 * thr,
            "accel_pedal_d": 15.3 + 0.8 * thr,
            "commanded_throttle": 3.1 + 0.9 * thr,
            "timing_advance": 12 + 0.006 * (rpm - 750) + 0.1 * speed + self._noise(t, "ta", 1.0),
            "stft_b1": stft,
            "ltft_b1": 1.6 + self._noise(t, "ltft", 0.2),
            "stft_b2": stft * 0.8 + self._noise(t, "stft2", 0.6),
            "ltft_b2": 0.8 + self._noise(t, "ltft2", 0.2),
            "o2_b1s1_voltage": o2 + self._noise(t, "o2", 0.02),
            "o2_b1s1_stft": stft,
            "o2_b1s2_voltage": 0.66 + self._noise(t, "o2b", 0.02),
            "fuel_system_1_status": 2.0 if closed_loop else 1.0,
            "fuel_system_2_status": 0.0,
            "fuel_level": 63.1,
            "run_time": 600 + t,
            "module_voltage": float(self.s.get("charging_voltage", 14.2)) + self._noise(t, "volt", 0.05),
            "baro_kpa": self.baro,
            "warmups_since_clear": 12,
            "distance_since_clear": 380,
            "o2_sensors_present": 0x33,
            "obd_standard": 1,
        }
        self._apply_faults(t, v)
        # keep encodable
        for k, val in list(v.items()):
            if k in self._ranges:
                lo, hi = self._ranges[k]
                v[k] = _clamp(val, lo, hi)
        return v

    def _engine_off(self, t: float) -> dict[str, float]:
        return {
            "engine_rpm": 0, "vehicle_speed": 0, "engine_load": 0, "map_kpa": self.baro, "maf_gs": 0,
            "coolant_temp": float(self.s.get("initial_coolant_c", 88)), "intake_air_temp": self.ambient + 5,
            "ambient_temp": self.ambient, "throttle_pos": 14.5, "accel_pedal_d": 15.3, "commanded_throttle": 0,
            "timing_advance": 0, "stft_b1": 0, "ltft_b1": 1.6, "stft_b2": 0, "ltft_b2": 0.8,
            "o2_b1s1_voltage": 0.45, "o2_b1s2_voltage": 0.45, "fuel_system_1_status": 0, "fuel_system_2_status": 0,
            "fuel_level": 63.1, "run_time": 0, "module_voltage": float(self.s.get("battery_voltage_off", 12.6)),
            "baro_kpa": self.baro, "warmups_since_clear": 12, "distance_since_clear": 380,
            "o2_sensors_present": 0x33, "obd_standard": 1,
        }

    def _apply_faults(self, t: float, v: dict[str, float]) -> None:
        rpm = v["engine_rpm"]
        for f in self.faults:
            key = f["signal"]
            if key not in v:
                continue
            when = f.get("when")
            if when == "rpm_below" and not rpm < f["threshold"]:
                continue
            kind = f["type"]
            if kind == "offset":
                v[key] += f["value"]
            elif kind == "noise":
                v[key] += self._noise(t, f"fault:{key}", f["amplitude"])
            elif kind == "rpm_dependent":
                frac = _clamp((rpm - 800) / (2500 - 800), 0, 1)
                v[key] = f["idle_value"] + (f["high_rpm_value"] - f["idle_value"]) * frac + self._noise(t, f"rd:{key}", 0.4)
            elif kind == "cap":
                cap = f["value"]
                v[key] = min(v[key], cap - 4 + 4 * math.sin(t / 60.0) ** 2) + self._noise(t, f"cap:{key}", 0.3)
            elif kind == "override":
                v[key] = f["value"] + self._noise(t, f"ov:{key}", f.get("noise", 0))
        # A lean condition also shows in STFT oscillation centre & O2 voltage bias
        if any(f["type"] == "rpm_dependent" and f["signal"] == "ltft_b1" for f in self.faults):
            v["o2_b1s1_voltage"] = max(0.05, v["o2_b1s1_voltage"] - 0.05)
