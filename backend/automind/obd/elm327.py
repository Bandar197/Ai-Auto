"""ELM327 command layer: one command in flight, prompt handling, error mapping."""

from __future__ import annotations

import asyncio
import json
import logging
import re
from dataclasses import dataclass, field
from functools import lru_cache

from automind.obd.errors import AdapterError, EcuNoResponse
from automind.obd.frames import EcuMessage, parse_response
from automind.obd.transport.base import Transport
from automind.shared_paths import shared_dir

log = logging.getLogger("automind.obd.elm327")

# Adapter-side problems (link to the car is not the issue).
_ADAPTER_ERRORS = {
    "BUFFER FULL": "buffer_full",
    "STOPPED": "stopped",
    "LV RESET": "low_voltage_reset",
    "ACT ALERT": "activity_alert",
    "FB ERROR": "feedback_error",
    "DATA ERROR": "data_error",
    "<DATA ERROR": "data_error",
    "<RX ERROR": "rx_error",
}
# Vehicle-side problems (adapter ↔ ECU).
_ECU_ERRORS = {
    "NO DATA": "no_data",
    "UNABLE TO CONNECT": "unable_to_connect",
    "BUS INIT: ...ERROR": "bus_init_error",
    "BUS INIT:...ERROR": "bus_init_error",
    "BUS ERROR": "bus_error",
    "CAN ERROR": "can_error",
}
_NOISE = re.compile(r"^(SEARCHING\.\.\.|BUS INIT: ?\.\.\.(OK)?|BUS INIT: ?\.\.\.)$")


@lru_cache(maxsize=1)
def protocol_table() -> dict[str, dict]:
    data = json.loads((shared_dir() / "obd" / "protocols.json").read_text(encoding="utf-8"))
    return {p["code"]: p for p in data["protocols"]}


@dataclass
class AdapterInfo:
    firmware: str | None = None
    description: str | None = None
    voltage: float | None = None
    unsupported_at: list[str] = field(default_factory=list)

    @property
    def is_simulator(self) -> bool:
        return bool(self.description and "AUTOMIND SIMULATOR" in self.description.upper())


@dataclass
class ObdResponse:
    request: str
    raw: str
    messages: list[EcuMessage]


class Elm327:
    """Talks to an ELM327 (or clone / STN) over any `Transport`."""

    def __init__(self, transport: Transport, *, timeout: float = 2.5, search_timeout: float = 12.0):
        self.t = transport
        self.timeout = timeout
        self.search_timeout = search_timeout
        self._lock = asyncio.Lock()
        self.headers = True
        self.protocol_code: str | None = None
        self.protocol_name: str | None = None
        self.protocol_auto = False
        self.family = "can"
        self.id_bits = 11
        self._searched = False
        self.log: list[tuple[str, str]] = []  # (command, raw response) for audit/debug
        self.max_log = 500

    # ------------------------------------------------------------------ low level
    async def send(self, cmd: str, timeout: float | None = None) -> str:
        """Send one command and return the cleaned response text (no prompt, no echo)."""
        async with self._lock:
            self.t.discard_input()
            await self.t.write((cmd + "\r").encode("ascii"))
            raw = await self.t.read_until(b">", timeout or self.timeout)
        text = raw.decode("ascii", errors="replace").replace("\x00", "")
        text = text.rstrip(">").replace("\n", "\r")
        lines = [ln.strip() for ln in text.split("\r") if ln.strip()]
        norm_cmd = cmd.replace(" ", "").upper()
        if lines and lines[0].replace(" ", "").upper() == norm_cmd:
            lines = lines[1:]  # echo
        cleaned = "\r".join(lines)
        self.log.append((cmd, cleaned))
        if len(self.log) > self.max_log:
            del self.log[: len(self.log) - self.max_log]
        return cleaned

    async def at(self, cmd: str, timeout: float | None = None, *, tolerate_unknown: bool = False) -> str:
        resp = await self.send(cmd, timeout)
        if resp.strip() == "?":
            if tolerate_unknown:
                return "?"
            raise AdapterError("unknown_command", resp)
        return resp

    async def query(self, cmd: str, timeout: float | None = None) -> ObdResponse:
        """Send an OBD request (hex) and parse the per-ECU answers."""
        first = not self._searched
        resp = await self.send(cmd, timeout or (self.search_timeout if first else self.timeout))
        lines = [ln for ln in resp.split("\r") if ln and not _NOISE.match(ln.upper())]
        data_lines: list[str] = []
        ecu_err: tuple[str, str] | None = None
        adapter_err: tuple[str, str] | None = None
        for ln in lines:
            up = ln.upper()
            if up == "?":
                adapter_err = ("unknown_command", ln)
                continue
            matched = False
            for k, code in _ECU_ERRORS.items():
                if k in up:
                    ecu_err, matched = (code, ln), True
                    break
            if not matched:
                for k, code in _ADAPTER_ERRORS.items():
                    if k in up:
                        adapter_err, matched = (code, ln), True
                        break
            if not matched:
                data_lines.append(ln)
        msgs = parse_response(
            "\r".join(data_lines), headers=self.headers, protocol_family=self.family, can_id_bits=self.id_bits
        )
        if msgs:
            self._searched = True
            return ObdResponse(cmd, resp, msgs)
        if adapter_err:
            raise AdapterError(adapter_err[0], adapter_err[1])
        if ecu_err:
            raise EcuNoResponse(ecu_err[0], ecu_err[1])
        raise EcuNoResponse("no_data", resp)

    # ------------------------------------------------------------------ setup
    async def initialize(self, protocol: str = "0") -> AdapterInfo:
        info = AdapterInfo()
        reset = await self.send("ATZ", timeout=4.0)
        m = re.search(r"(ELM327[^\r]*|STN\d+[^\r]*|OBDLink[^\r]*)", reset, re.IGNORECASE)
        info.firmware = m.group(1).strip() if m else (reset.strip() or None)
        for cmd in ("ATE0", "ATL0", "ATS1", "ATH1"):
            await self.at(cmd)
        if (await self.at("ATAT1", tolerate_unknown=True)) == "?":
            info.unsupported_at.append("ATAT1")
        await self.at(f"ATSP{protocol}")
        self._searched = protocol != "0"
        ati = await self.at("ATI", tolerate_unknown=True)
        if ati != "?" and ati:
            info.firmware = ati.strip()
        desc = await self.at("AT@1", tolerate_unknown=True)
        info.description = None if desc == "?" else desc.strip() or None
        rv = await self.at("ATRV", tolerate_unknown=True)
        mv = re.search(r"(\d+(?:\.\d+)?)\s*V", rv.upper())
        info.voltage = float(mv.group(1)) if mv else None
        self.headers = True
        return info

    async def read_protocol(self) -> tuple[str | None, str | None]:
        dpn = (await self.at("ATDPN", tolerate_unknown=True)).strip().upper()
        if dpn and dpn != "?":
            self.protocol_auto = dpn.startswith("A")
            self.protocol_code = dpn[-1]
        dp = (await self.at("ATDP", tolerate_unknown=True)).strip()
        self.protocol_name = dp if dp and dp != "?" else None
        meta = protocol_table().get(self.protocol_code or "", {})
        fam = meta.get("family", "can")
        self.family = "can" if fam in ("can", "j1939") else "legacy"
        self.id_bits = int(meta.get("id_bits", 11))
        if not self.protocol_name and meta:
            self.protocol_name = meta["name"]
        return self.protocol_code, self.protocol_name
