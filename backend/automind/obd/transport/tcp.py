"""Wi-Fi ELM327 adapters (TCP socket, typically 192.168.0.10:35000)."""

from __future__ import annotations

import asyncio
import contextlib

from automind.obd.errors import TransportError
from automind.obd.transport.base import Transport


class TcpTransport(Transport):
    kind = "wifi_tcp"

    def __init__(self, host: str = "192.168.0.10", port: int = 35000, connect_timeout: float = 5.0):
        super().__init__()
        self.host = host
        self.port = port
        self.connect_timeout = connect_timeout
        self._reader: asyncio.StreamReader | None = None
        self._writer: asyncio.StreamWriter | None = None
        self._task: asyncio.Task[None] | None = None

    @property
    def description(self) -> str:
        return f"tcp://{self.host}:{self.port}"

    @property
    def is_open(self) -> bool:
        return self._writer is not None and not self._writer.is_closing() and self._closed_reason is None

    async def open(self) -> None:
        self._closed_reason = None
        try:
            self._reader, self._writer = await asyncio.wait_for(
                asyncio.open_connection(self.host, self.port), self.connect_timeout
            )
        except (TimeoutError, OSError) as e:
            raise TransportError(f"cannot reach adapter at {self.host}:{self.port}: {e!s}") from e
        self._task = asyncio.create_task(self._pump())

    async def _pump(self) -> None:
        assert self._reader is not None
        try:
            while True:
                chunk = await self._reader.read(1024)
                if not chunk:
                    self._mark_closed("peer closed the connection")
                    return
                self._feed(chunk)
        except (OSError, asyncio.IncompleteReadError) as e:
            self._mark_closed(str(e))
        except asyncio.CancelledError:
            return

    async def write(self, data: bytes) -> None:
        if not self._writer or self._writer.is_closing():
            raise TransportError("not connected")
        try:
            self._writer.write(data)
            await self._writer.drain()
        except OSError as e:
            self._mark_closed(str(e))
            raise TransportError(f"write failed: {e!s}") from e

    async def close(self) -> None:
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError, Exception):
                await self._task
            self._task = None
        if self._writer:
            self._writer.close()
            with contextlib.suppress(Exception):
                await self._writer.wait_closed()
        self._writer = None
        self._reader = None
        self._closed_reason = self._closed_reason or "closed by client"
