"""USB / Bluetooth-Classic (virtual COM port) ELM327 adapters via pyserial."""

from __future__ import annotations

import asyncio
import contextlib
import threading

from automind.obd.errors import TransportError
from automind.obd.transport.base import Transport


class SerialTransport(Transport):
    kind = "usb_serial"

    def __init__(self, port: str, baudrate: int = 38400):
        super().__init__()
        self.port = port
        self.baudrate = baudrate
        self._ser = None
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._stop = threading.Event()

    @property
    def description(self) -> str:
        return f"serial://{self.port}@{self.baudrate}"

    @property
    def is_open(self) -> bool:
        return bool(self._ser and self._ser.is_open and self._closed_reason is None)

    async def open(self) -> None:
        try:
            import serial
        except ImportError as e:  # pragma: no cover
            raise TransportError("serial support requires `pip install automind[serial]`") from e
        self._closed_reason = None
        try:
            self._ser = serial.Serial(self.port, self.baudrate, timeout=0.05)
        except Exception as e:
            raise TransportError(f"cannot open {self.port}: {e!s}") from e
        self._loop = asyncio.get_running_loop()
        self._stop.clear()
        self._thread = threading.Thread(target=self._reader, daemon=True)
        self._thread.start()

    def _reader(self) -> None:
        assert self._loop is not None
        while not self._stop.is_set():
            try:
                chunk = self._ser.read(256)
            except Exception as e:
                self._loop.call_soon_threadsafe(self._mark_closed, str(e))
                return
            if chunk:
                self._loop.call_soon_threadsafe(self._feed, chunk)

    async def write(self, data: bytes) -> None:
        if not self.is_open:
            raise TransportError("not connected")
        await asyncio.to_thread(self._ser.write, data)

    async def close(self) -> None:
        self._stop.set()
        if self._thread:
            await asyncio.to_thread(self._thread.join, 1.0)
        if self._ser:
            with contextlib.suppress(Exception):
                self._ser.close()
        self._ser = None
        self._closed_reason = self._closed_reason or "closed by client"
