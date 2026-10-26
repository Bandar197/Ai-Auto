"""Transport abstraction: the byte link between this device and the adapter."""

from __future__ import annotations

import asyncio
from abc import ABC, abstractmethod

from automind.obd.errors import AdapterTimeout, TransportError


class Transport(ABC):
    """Byte stream to an ELM327-compatible adapter.

    Subclasses push received bytes with `_feed()`; `read_until()` waits for a
    terminator (the ELM327 '>' prompt) with a timeout.
    """

    kind: str = "unknown"

    def __init__(self) -> None:
        self._buf = bytearray()
        self._event = asyncio.Event()
        self._closed_reason: str | None = None

    # -- to implement -------------------------------------------------------
    @abstractmethod
    async def open(self) -> None: ...

    @abstractmethod
    async def close(self) -> None: ...

    @abstractmethod
    async def write(self, data: bytes) -> None: ...

    @property
    @abstractmethod
    def is_open(self) -> bool: ...

    @property
    def description(self) -> str:
        return self.kind

    # -- shared -------------------------------------------------------------
    def _feed(self, data: bytes) -> None:
        if data:
            self._buf.extend(data)
            self._event.set()

    def _mark_closed(self, reason: str) -> None:
        self._closed_reason = reason
        self._event.set()

    def discard_input(self) -> None:
        self._buf.clear()
        self._event.clear()

    async def read_until(self, terminator: bytes = b">", timeout: float = 2.5) -> bytes:
        loop = asyncio.get_running_loop()
        deadline = loop.time() + timeout
        while True:
            idx = self._buf.find(terminator)
            if idx >= 0:
                out = bytes(self._buf[: idx + len(terminator)])
                del self._buf[: idx + len(terminator)]
                return out
            if self._closed_reason is not None and not self.is_open:
                raise TransportError(f"connection closed: {self._closed_reason}")
            remaining = deadline - loop.time()
            if remaining <= 0:
                partial = bytes(self._buf)
                raise AdapterTimeout(f"no prompt within {timeout:.1f}s (partial={partial[-80:]!r})")
            self._event.clear()
            try:
                await asyncio.wait_for(self._event.wait(), remaining)
            except TimeoutError:
                continue
