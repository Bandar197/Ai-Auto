"""In-process transport backed by the ELM327 emulator (tests, offline demo)."""

from __future__ import annotations

import asyncio

from automind.obd.errors import TransportError
from automind.obd.transport.base import Transport


class LoopbackTransport(Transport):
    kind = "in_process"

    def __init__(self, emulator, *, fail_after: int | None = None):  # noqa: ANN001
        super().__init__()
        self.emu = emulator
        self.fail_after = fail_after
        self._open = False
        self._pending = b""
        self.commands = 0

    @property
    def description(self) -> str:
        return "loopback://emulator"

    @property
    def is_open(self) -> bool:
        return self._open

    async def open(self) -> None:
        self._open = True
        self._closed_reason = None

    async def close(self) -> None:
        self._open = False
        self._closed_reason = "closed by client"

    async def write(self, data: bytes) -> None:
        if not self._open:
            raise TransportError("not connected")
        self._pending += data
        while b"\r" in self._pending:
            line, self._pending = self._pending.split(b"\r", 1)
            self.commands += 1
            if self.fail_after is not None and self.commands > self.fail_after:
                self._open = False
                self._mark_closed("simulated link loss")
                return
            resp = self.emu.handle(line.decode("ascii"))
            await asyncio.sleep(0)
            self._feed(resp.encode("ascii"))
