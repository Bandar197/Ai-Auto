"""ELM327 command interpreter emulating an adapter plugged into a simulated car.

Used by the TCP simulator server and by tests. It deliberately reproduces the
real adapter's text formats (echo, headers, spaces, CAN ISO-TP framing,
legacy K-line framing with checksum, 'SEARCHING...', 'NO DATA', '?').

The adapter identifies itself as `AUTOMIND SIMULATOR` in AT@1 so that clients
always label its data as demo, never as a real vehicle.
"""

from __future__ import annotations

import re
import time
from collections.abc import Callable
from typing import Any

from automind.obd.dtc import encode_dtc
from automind.obd.pids import pid_defs
from automind.simulator.vehicle import VehicleModel

SIM_DESCRIPTION = "AUTOMIND SIMULATOR"
_PROTO_NAMES = {
    "1": "SAE J1850 PWM", "2": "SAE J1850 VPW", "3": "ISO 9141-2", "4": "ISO 14230-4 (KWP 5BAUD)",
    "5": "ISO 14230-4 (KWP FAST)", "6": "ISO 15765-4 (CAN 11/500)", "7": "ISO 15765-4 (CAN 29/500)",
    "8": "ISO 15765-4 (CAN 11/250)", "9": "ISO 15765-4 (CAN 29/250)",
}
_CAN_29_IDS = {"7E8": "18DAF110", "7E9": "18DAF118"}
_LEGACY_SRC = {"7E8": 0x10, "7E9": 0x18}


def encode_pid_value(pid: str, values: dict[str, float]) -> bytes | None:
    """Inverse of automind.obd.pids.decode_pid for the simulator."""
    d = pid_defs().get(pid)
    if d is None or not d.outputs:
        return None
    buf = bytearray(d.bytes)
    for o in d.outputs:
        if o.key not in values:
            if o.key.startswith("o2_") and o.key.endswith("_stft"):
                buf[o.start] = 0xFF
                continue
            return None
        raw = round((float(values[o.key]) - o.offset) / o.scale)
        bits = 8 * o.length
        lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if o.signed else (0, (1 << bits) - 1)
        raw = max(lo, min(hi, raw))
        buf[o.start:o.start + o.length] = raw.to_bytes(o.length, "big", signed=o.signed)
    return bytes(buf)


class Elm327Emulator:
    def __init__(
        self,
        scenario: dict[str, Any],
        *,
        clock: Callable[[], float] | None = None,
        time_scale: float = 1.0,
        seed: int = 7,
        protocol: str | None = None,
        ignition_on: bool = True,
        engine_running: bool = True,
        start_engine_after_clear_s: float | None = None,
    ):
        self.scenario = scenario
        self.vehicle = VehicleModel(scenario, seed=seed)
        self.vehicle.engine_running = engine_running
        self._clock = clock or time.monotonic
        self._t0 = self._clock()
        self.time_scale = time_scale
        self.car_protocol = protocol or scenario.get("protocol", "6")
        self.ignition_on = ignition_on
        self.firmware = scenario.get("adapter_firmware", "ELM327 v1.5")
        self.engine_pids = {p.upper() for p in scenario["supported_pids"]["01"]}
        self.svc09 = {p.upper() for p in scenario["supported_pids"].get("09", [])}
        self.ecus = scenario.get("ecus", ["7E8"])
        dtcs = scenario.get("dtcs", [])
        self.stored = [d["code"] for d in dtcs if d["status"] == "stored"]
        self.pending = [d["code"] for d in dtcs if d["status"] == "pending"]
        self.permanent = [d["code"] for d in dtcs if d["status"] == "permanent"] or list(self.stored)
        self.freeze = scenario.get("freeze_frame")
        self.monitors_complete = True
        # After a clear (service 04) a fault that is still physically present is
        # detected again: pending first, then stored. A repaired fault stays away.
        self.fault_active = bool(scenario.get("fault_active", bool(scenario.get("faults"))))
        self._fault_codes = [d["code"] for d in dtcs if d["status"] in ("stored", "pending")]
        self.cleared_at: float | None = None
        self.redetect_pending_s = float(scenario.get("redetect_pending_s", 20))
        self.redetect_stored_s = float(scenario.get("redetect_stored_s", 45))
        self.monitor_complete_s = float(scenario.get("monitor_complete_s", 90))
        self.start_engine_after_clear_s = start_engine_after_clear_s
        self.reset()

    # ------------------------------------------------------------------ state
    def reset(self) -> None:
        self.echo = True
        self.linefeeds = False
        self.spaces = True
        self.headers = False
        self.selected_protocol = "0"
        self.active_protocol: str | None = None

    def elapsed(self) -> float:
        return (self._clock() - self._t0) * self.time_scale

    @property
    def nl(self) -> str:
        return "\r\n" if self.linefeeds else "\r"

    # ------------------------------------------------------------------ entry
    def handle(self, line: str) -> str:
        """Process one command line (without '\\r'); return full adapter output incl. prompt."""
        cmd = line.strip().upper().replace(" ", "")
        out = ""
        if self.echo:
            out += line.strip() + self.nl
        if not cmd:
            body = ""  # real ELM repeats the last command; we answer with an empty prompt
        elif cmd.startswith("AT"):
            body = self._at(cmd[2:])
        elif re.fullmatch(r"[0-9A-F]+", cmd) and len(cmd) % 2 == 0 or re.fullmatch(r"[0-9A-F]{3,}", cmd):
            body = self._obd(cmd)
        else:
            body = "?"
        if body:
            out += body.replace("\r", self.nl) + self.nl
        return out + self.nl + ">"

    # ------------------------------------------------------------------ AT
    def _at(self, a: str) -> str:
        if a == "Z":
            self.reset()
            return self.nl + self.firmware
        if a == "WS":
            self.reset()
            return self.firmware
        if a == "I":
            return self.firmware
        if a == "@1":
            return SIM_DESCRIPTION
        if a == "RV":
            v = self.vehicle.values(self.elapsed())["module_voltage"] if self.ignition_on else 12.6
            return f"{v:.1f}V"
        if a in ("E0", "E1"):
            self.echo = a == "E1"
            return "OK"
        if a in ("L0", "L1"):
            self.linefeeds = a == "L1"
            return "OK"
        if a in ("S0", "S1"):
            self.spaces = a == "S1"
            return "OK"
        if a in ("H0", "H1"):
            self.headers = a == "H1"
            return "OK"
        if re.fullmatch(r"SP[0-9A-C]", a) or re.fullmatch(r"TP[0-9A-C]", a):
            self.selected_protocol = a[2]
            self.active_protocol = None if a[2] == "0" else a[2]
            return "OK"
        if a == "DPN":
            if self.active_protocol is None:
                return "0" if self.selected_protocol == "0" else self.selected_protocol
            return ("A" if self.selected_protocol == "0" else "") + self.active_protocol
        if a == "DP":
            if self.active_protocol is None:
                return "AUTO"
            name = _PROTO_NAMES.get(self.active_protocol, "?")
            return ("AUTO, " if self.selected_protocol == "0" else "") + name
        if re.fullmatch(r"AT[0-2]", a) or re.fullmatch(r"ST[0-9A-F]{2}", a) or a in ("D", "PC", "CAF0", "CAF1", "M0"):
            return "OK"
        return "?"

    # ------------------------------------------------------------------ OBD
    def _obd(self, cmd: str) -> str:
        prefix = ""
        if self.active_protocol is None:
            if self.selected_protocol not in ("0", self.car_protocol) or not self.ignition_on:
                return "SEARCHING..." + "\r" + "UNABLE TO CONNECT" if self.selected_protocol == "0" else "NO DATA"
            self.active_protocol = self.car_protocol
            prefix = "SEARCHING...\r" if self.selected_protocol == "0" else ""
        if not self.ignition_on:
            return "NO DATA"
        if len(cmd) % 2 == 1:  # e.g. '010C1' (response-count suffix)
            cmd = cmd[:-1]
        sid = int(cmd[:2], 16)
        rest = bytes.fromhex(cmd[2:]) if len(cmd) > 2 else b""
        answers = self._answers(sid, rest)
        if not answers:
            return prefix + "NO DATA"
        return prefix + "\r".join(self._format(ecu, payload) for ecu, payload in answers)

    def _answers(self, sid: int, rest: bytes) -> list[tuple[str, bytes]]:
        t = self.elapsed()
        out: list[tuple[str, bytes]] = []
        if sid == 0x01 and len(rest) >= 1:
            pid = f"{rest[0]:02X}"
            for ecu in self.ecus:
                data = self._service01(ecu, pid, t)
                if data is not None:
                    out.append((ecu, bytes([0x41, rest[0]]) + data))
        elif sid == 0x02 and len(rest) >= 1:
            data = self._service02(f"{rest[0]:02X}")
            if data is not None:
                out.append(("7E8", bytes([0x42, rest[0], 0x00]) + data))
        elif sid in (0x03, 0x07, 0x0A):
            self._advance_after_clear(t)
            codes = {0x03: self.stored, 0x07: self.pending, 0x0A: self.permanent}[sid]
            body = b"".join(bytes(encode_dtc(c)) for c in codes)
            if self._is_can:
                out.append(("7E8", bytes([sid + 0x40, len(codes)]) + body))
            else:
                out.append(("7E8", bytes([sid + 0x40]) + body))
        elif sid == 0x04:
            self.stored, self.pending = [], []
            self.freeze = None
            self.monitors_complete = False
            self.cleared_at = t
            out.append(("7E8", b"\x44"))
        elif sid == 0x09 and len(rest) >= 1:
            pid = rest[0]
            if pid == 0x00:
                mask = 0
                for p in self.svc09:
                    mask |= 1 << (32 - int(p, 16))
                out.append(("7E8", bytes([0x49, 0x00]) + mask.to_bytes(4, "big")))
            elif pid == 0x02 and "02" in self.svc09:
                vin = self.scenario["vehicle"]["vin"].encode("ascii")
                out.append(("7E8", bytes([0x49, 0x02, 0x01]) + vin))
            elif pid == 0x04 and "04" in self.svc09:
                cal = b"AMSIM-CAL-0001\x00\x00"
                out.append(("7E8", bytes([0x49, 0x04, 0x01]) + cal))
        return out

    def _since_clear(self, t: float) -> float | None:
        if (self.cleared_at is not None and not self.vehicle.engine_running
                and self.start_engine_after_clear_s is not None and t - self.cleared_at >= self.start_engine_after_clear_s):
            self.vehicle.engine_running = True  # driver starts the engine after clearing
        if self.cleared_at is None or not self.vehicle.engine_running:
            return None
        return max(0.0, t - self.cleared_at)

    def _advance_after_clear(self, t: float) -> None:
        dt = self._since_clear(t)
        if dt is None:
            return
        if self.fault_active:
            for code in self._fault_codes:
                if dt >= self.redetect_stored_s and code not in self.stored:
                    self.stored.append(code)
                    if code in self.pending:
                        self.pending.remove(code)
                elif self.redetect_pending_s <= dt < self.redetect_stored_s and code not in self.pending:
                    self.pending.append(code)
            if dt >= self.redetect_stored_s and self.stored:
                self.permanent = sorted(set(self.permanent) | set(self.stored))
        if dt >= self.monitor_complete_s:
            self.monitors_complete = True
            if not self.fault_active:
                self.permanent = []  # self-test passed → permanent codes erase themselves

    @property
    def _is_can(self) -> bool:
        return (self.active_protocol or self.car_protocol) in ("6", "7", "8", "9")

    def _supported_mask(self, base: int, pids: set[str]) -> bytes:
        mask = 0
        for i in range(32):
            p = base + i + 1
            if f"{p:02X}" in pids:
                mask |= 1 << (31 - i)
        # bit for next range when anything above is supported
        if any(int(x, 16) > base + 0x20 for x in pids):
            mask |= 1
        return mask.to_bytes(4, "big")

    def _service01(self, ecu: str, pid: str, t: float) -> bytes | None:
        if ecu != "7E8":
            # Transmission ECU: answers only the supported-PID request, nothing else.
            if pid == "00":
                return bytes([0x80, 0x00, 0x00, 0x00])
            return None
        pidn = int(pid, 16)
        if pidn % 0x20 == 0:
            if pidn == 0 or any(int(x, 16) > pidn for x in self.engine_pids):
                return self._supported_mask(pidn, self.engine_pids)
            return None
        if pid not in self.engine_pids:
            return None
        self._advance_after_clear(t)
        dt = self._since_clear(t)
        if dt is not None and pid in ("30", "31", "4E"):
            if pid == "30":
                return bytes([1 if dt >= self.monitor_complete_s else 0])
            if pid == "31":
                return int(dt * 0.012).to_bytes(2, "big")  # ≈ 43 km/h average while driving
            return int(dt // 60).to_bytes(2, "big")
        if pid == "01":
            mil = bool(self.stored)
            a = (0x80 if mil else 0) | min(len(self.stored), 0x7F)
            c = 0x65
            d = 0x00 if self.monitors_complete else c
            return bytes([a, 0x07, c, d])
        v = self.vehicle.values(t)
        if pid == "03":
            return bytes([int(v["fuel_system_1_status"]), int(v["fuel_system_2_status"])])
        if pid in ("13", "1C"):
            return bytes([int(v["o2_sensors_present"] if pid == "13" else v["obd_standard"])])
        if pid == "21":
            return (42 if self.stored else 0).to_bytes(2, "big")
        return encode_pid_value(pid, v)

    def _service02(self, pid: str) -> bytes | None:
        if not self.freeze:
            if pid == "00":
                return bytes([0x40, 0x00, 0x00, 0x00])  # only PID 02 supported, value 0000
            if pid == "02":
                return b"\x00\x00"
            return None
        vals = self.freeze["values"]
        fpids = {"02"}
        for key in vals:
            for d in pid_defs().values():
                if any(o.key == key for o in d.outputs):
                    fpids.add(d.pid)
        if pid == "00":
            return self._supported_mask(0, fpids)
        if pid == "02":
            return bytes(encode_dtc(self.freeze["dtc"]))
        if pid not in fpids:
            return None
        return encode_pid_value(pid, vals)

    # ------------------------------------------------------------------ framing
    def _hex(self, bs: bytes | list[int]) -> str:
        sep = " " if self.spaces else ""
        return sep.join(f"{b:02X}" for b in bs)

    def _format(self, ecu: str, payload: bytes) -> str:
        if self._is_can:
            return self._format_can(ecu, payload)
        return self._format_legacy(ecu, payload)

    def _format_can(self, ecu: str, p: bytes) -> str:
        sep = " " if self.spaces else ""
        hid = _CAN_29_IDS.get(ecu, ecu) if self.active_protocol in ("7", "9") else ecu
        if self.active_protocol in ("7", "9"):
            hid = sep.join(hid[i:i + 2] for i in range(0, 8, 2))
        lines: list[str] = []
        if len(p) <= 7:
            frames = [bytes([len(p)]) + p]
        else:
            frames = [bytes([0x10 | (len(p) >> 8), len(p) & 0xFF]) + p[:6]]
            rest, seq = p[6:], 1
            while rest:
                frames.append(bytes([0x20 | (seq & 0x0F)]) + rest[:7])
                rest, seq = rest[7:], seq + 1
        if self.headers:
            for f in frames:
                f = f + b"\x00" * (8 - len(f))
                lines.append(hid + sep + self._hex(f))
            return "\r".join(lines)
        # headers off: ELM strips PCI; multi-frame shows length + 'n:' lines
        if len(frames) == 1:
            return self._hex(p)
        lines.append(f"{len(p):03X}")
        lines.append("0:" + sep + self._hex(p[:6]))
        rest, n = p[6:], 1
        while rest:
            lines.append(f"{n & 0xF:X}:" + sep + self._hex(rest[:7]))
            rest, n = rest[7:], n + 1
        return "\r".join(lines)

    def _format_legacy(self, ecu: str, p: bytes) -> str:
        src = _LEGACY_SRC.get(ecu, 0x10)
        header = bytes([0x48, 0x6B, src])
        sid = p[0]
        if sid in (0x43, 0x47, 0x4A):
            body = p[1:]
            chunks = [body[i:i + 6] for i in range(0, max(len(body), 1), 6)] or [b""]
            msgs = [bytes([sid]) + c + b"\x00" * (6 - len(c)) for c in chunks]
        elif sid == 0x49 and len(p) > 3:
            data = p[3:]  # skip count byte (CAN-style) — legacy uses message counter
            pad = (-len(data)) % 4
            data = b"\x00" * pad + data
            msgs = [bytes([0x49, p[1], i + 1]) + data[i * 4:(i + 1) * 4] for i in range(len(data) // 4)]
        else:
            msgs = [p]
        out = []
        for m in msgs:
            frame = header + m
            cs = sum(frame) & 0xFF
            out.append(self._hex(frame + bytes([cs])) if self.headers else self._hex(m))
        return "\r".join(out)
