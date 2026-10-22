"""TCP server exposing the ELM327 emulator like a Wi-Fi OBD adapter.

    automind simulate --host 127.0.0.1 --port 35000 --scenario p0106_map_sensor

Fault injection for network-failure tests:
  * drop_after: close the socket after N commands (connection loss)
  * latency_ms: delay every response
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from dataclasses import dataclass

from automind.simulator.elm_emulator import Elm327Emulator
from automind.simulator.scenarios import load_scenario

log = logging.getLogger("automind.simulator")


@dataclass
class SimulatorConfig:
    scenario: str = "healthy"
    host: str = "127.0.0.1"
    port: int = 35000
    time_scale: float = 1.0
    seed: int = 7
    protocol: str | None = None
    ignition_on: bool = True
    engine_running: bool = True
    drop_after: int | None = None
    latency_ms: int = 0
    start_engine_after_clear_s: float | None = None


class SimulatorServer:
    def __init__(self, cfg: SimulatorConfig):
        self.cfg = cfg
        self.scenario = load_scenario(cfg.scenario)
        self._server: asyncio.base_events.Server | None = None
        self.connections = 0
        self.commands = 0
        # One simulated car for the server's lifetime: codes cleared on one
        # connection stay cleared on the next (like a real vehicle).
        self.emulator = Elm327Emulator(
            self.scenario, time_scale=cfg.time_scale, seed=cfg.seed, protocol=cfg.protocol,
            ignition_on=cfg.ignition_on, engine_running=cfg.engine_running,
            start_engine_after_clear_s=cfg.start_engine_after_clear_s,
        )

    @property
    def port(self) -> int:
        assert self._server is not None
        return self._server.sockets[0].getsockname()[1]

    async def start(self) -> None:
        self._server = await asyncio.start_server(self._handle, self.cfg.host, self.cfg.port)
        log.info("ECU simulator (%s) listening on %s:%s", self.cfg.scenario, self.cfg.host, self.port)

    async def stop(self) -> None:
        if self._server:
            self._server.close()
            with contextlib.suppress(Exception):
                await self._server.wait_closed()
            self._server = None

    async def __aenter__(self) -> SimulatorServer:
        await self.start()
        return self

    async def __aexit__(self, *exc: object) -> None:
        await self.stop()

    async def _handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self.connections += 1
        emu = self.emulator
        emu.reset()  # adapter settings reset per connection; vehicle state persists
        n = 0
        buf = b""
        try:
            while True:
                chunk = await reader.read(256)
                if not chunk:
                    return
                buf += chunk
                while b"\r" in buf:
                    line, buf = buf.split(b"\r", 1)
                    n += 1
                    self.commands += 1
                    if self.cfg.drop_after is not None and n > self.cfg.drop_after:
                        log.info("simulated connection drop after %s commands", self.cfg.drop_after)
                        return
                    resp = emu.handle(line.decode("ascii", errors="replace").strip("\n"))
                    if self.cfg.latency_ms:
                        await asyncio.sleep(self.cfg.latency_ms / 1000)
                    writer.write(resp.encode("ascii"))
                    await writer.drain()
        except (ConnectionResetError, BrokenPipeError):
            return
        finally:
            writer.close()
            with contextlib.suppress(Exception):
                await writer.wait_closed()


async def serve_forever(cfg: SimulatorConfig) -> None:
    srv = SimulatorServer(cfg)
    await srv.start()
    print(f"AutoMind ECU simulator — scenario '{cfg.scenario}' on {cfg.host}:{srv.port} (Ctrl+C to stop)")
    print("Data from this simulator is DEMO data; clients detect it via AT@1 = 'AUTOMIND SIMULATOR'.")
    try:
        await asyncio.Event().wait()
    finally:
        await srv.stop()
