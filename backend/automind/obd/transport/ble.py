"""BLE ELM327 adapters via `bleak` (Windows, macOS, Linux).

Known GATT layouts of ELM327-compatible BLE dongles (notify, write):
  FFF0: FFF1 / FFF2      FFE0: FFE1 / FFE1      18F0: 2AF0 / 2AF1
The layout is auto-detected unless UUIDs are given explicitly.
"""

from __future__ import annotations

from automind.obd.errors import TransportError
from automind.obd.transport.base import Transport

_KNOWN = [
    ("0000fff0-0000-1000-8000-00805f9b34fb", "0000fff1-0000-1000-8000-00805f9b34fb", "0000fff2-0000-1000-8000-00805f9b34fb"),
    ("0000ffe0-0000-1000-8000-00805f9b34fb", "0000ffe1-0000-1000-8000-00805f9b34fb", "0000ffe1-0000-1000-8000-00805f9b34fb"),
    ("000018f0-0000-1000-8000-00805f9b34fb", "00002af0-0000-1000-8000-00805f9b34fb", "00002af1-0000-1000-8000-00805f9b34fb"),
]


class BleTransport(Transport):
    kind = "ble"

    def __init__(
        self,
        address: str,
        notify_uuid: str | None = None,
        write_uuid: str | None = None,
        connect_timeout: float = 10.0,
        chunk_size: int = 20,
    ):
        super().__init__()
        self.address = address
        self.notify_uuid = notify_uuid
        self.write_uuid = write_uuid
        self.connect_timeout = connect_timeout
        self.chunk_size = chunk_size
        self._client = None

    @property
    def description(self) -> str:
        return f"ble://{self.address}"

    @property
    def is_open(self) -> bool:
        return bool(self._client and self._client.is_connected and self._closed_reason is None)

    async def open(self) -> None:
        try:
            from bleak import BleakClient
        except ImportError as e:  # pragma: no cover
            raise TransportError("BLE support requires `pip install automind[ble]`") from e
        self._closed_reason = None
        self._client = BleakClient(
            self.address, timeout=self.connect_timeout,
            disconnected_callback=lambda _c: self._mark_closed("BLE disconnected"),
        )
        try:
            await self._client.connect()
        except Exception as e:
            raise TransportError(f"BLE connect failed: {e!s}") from e
        if not (self.notify_uuid and self.write_uuid):
            self._detect_layout()
        await self._client.start_notify(self.notify_uuid, lambda _h, data: self._feed(bytes(data)))

    def _detect_layout(self) -> None:
        services = {s.uuid.lower(): s for s in self._client.services}
        for svc, notify, write in _KNOWN:
            if svc in services:
                self.notify_uuid, self.write_uuid = notify, write
                return
        raise TransportError("no known ELM327 BLE service found; pass notify/write UUIDs explicitly")

    async def write(self, data: bytes) -> None:
        if not self.is_open:
            raise TransportError("not connected")
        for i in range(0, len(data), self.chunk_size):
            await self._client.write_gatt_char(self.write_uuid, data[i:i + self.chunk_size], response=False)

    async def close(self) -> None:
        if self._client:
            try:
                await self._client.disconnect()
            except Exception:  # noqa: S110 - best effort on shutdown
                pass
        self._client = None
        self._closed_reason = self._closed_reason or "closed by client"


async def scan(timeout: float = 6.0) -> list[dict[str, str | int | None]]:
    """List nearby BLE devices that look like OBD adapters (name heuristics)."""
    from bleak import BleakScanner

    found = await BleakScanner.discover(timeout=timeout, return_adv=True)
    out = []
    for dev, adv in found.values():
        name = (dev.name or adv.local_name or "").strip()
        uuids = [u.lower() for u in (adv.service_uuids or [])]
        looks_obd = any(k in name.upper() for k in ("OBD", "ELM", "VLINK", "VEEPEAK", "KONNWEI", "IOS-VLINK")) or any(
            u in uuids for u, _, _ in _KNOWN
        )
        out.append({"address": dev.address, "name": name or None, "rssi": adv.rssi, "likely_obd": int(looks_obd)})
    return sorted(out, key=lambda d: (-int(d["likely_obd"] or 0), -(d["rssi"] or -999)))
