"""Capture a full scan + live data into a Recording (format v1)."""

from __future__ import annotations

import asyncio
import logging
import time
from collections.abc import Callable, Iterable

from automind.obd.client import ObdClient
from automind.obd.errors import AdapterError, AdapterTimeout, EcuNoResponse, NotSupported, TransportError
from automind.obd.pids import pid_defs
from automind.recording.format import (
    RecDTC,
    RecEvent,
    RecFreezeFrame,
    Recording,
    RecSample,
    RecSignal,
    RecSource,
    RecVehicle,
)

log = logging.getLogger("automind.recording")

# Signals that matter most for diagnosis, polled first when supported.
DEFAULT_LIVE_PIDS = [
    "0C", "0D", "05", "0F", "0B", "10", "11", "04", "06", "07", "08", "09", "0E",
    "14", "15", "42", "33", "46", "03", "2F", "1F", "49", "4C", "5C",
]
STATIC_PIDS = {"03", "13", "1C", "1F", "21", "2F", "30", "31", "33", "46", "51"}  # slow-changing: poll rarely


def _source_kind(transport_kind: str) -> str:
    return {"wifi_tcp": "elm327_wifi", "ble": "elm327_ble", "usb_serial": "elm327_serial"}.get(
        transport_kind, "elm327_wifi")


async def capture_session(
    client: ObdClient,
    *,
    duration_s: float = 60.0,
    pids: Iterable[str] | None = None,
    include_vin: bool = True,
    app: str | None = "automind-cli",
    on_progress: Callable[[str, dict], None] | None = None,
    reconnect: bool = True,
    min_request_period_s: float = 0.04,
) -> Recording:
    """Run the standard scan (VIN, DTCs, freeze frame) then poll live data.

    `client` must already be connected. The data_mode is derived from the
    adapter: the AutoMind simulator is always recorded as `demo`.
    """

    def progress(step: str, **kw: object) -> None:
        if on_progress:
            on_progress(step, kw)

    rep = client.last_report
    data_mode = "demo" if client.is_simulator else "live"
    rec = Recording(
        data_mode=data_mode,
        source=RecSource(
            kind="simulator" if client.is_simulator else _source_kind(client.transport.kind),
            adapter_firmware=client.info.firmware,
            protocol_code=client.elm.protocol_code,
            protocol_name=client.elm.protocol_name,
            app=app,
        ),
        supported_pids={svc: sorted(client.supported_pids(svc)) for svc in client.supported},
        ecus=[e for e in client.ecus if e],
    )
    if rep and rep.is_simulator:
        rec.source.demo_scenario = None  # unknown to the client; filled by run_demo
    t_start = time.monotonic()

    def t_ms() -> int:
        return int((time.monotonic() - t_start) * 1000)

    progress("vin")
    if include_vin:
        vin = await client.read_vin()
        rec.vehicle = RecVehicle(vin=vin)
    progress("dtcs")
    for d in await client.read_all_dtcs():
        rec.dtcs.append(RecDTC(code=d.code, status=d.status, ecu=d.ecu))  # type: ignore[arg-type]
    progress("freeze_frame")
    ff = await client.read_freeze_frame()
    if ff.get("dtc"):
        rec.freeze_frames.append(RecFreezeFrame(dtc=ff["dtc"], frame=ff["frame"], values=ff["values"]))

    wanted = [p.upper() for p in (pids or DEFAULT_LIVE_PIDS)]
    live = [p for p in wanted if client.is_supported(p)]
    defs = pid_defs()
    seen_signals: dict[str, RecSignal] = {}
    progress("live", pids=live)
    deadline = time.monotonic() + duration_s
    loop_n = 0
    consecutive_fail = 0
    while time.monotonic() < deadline and live:
        for p in live:
            if p in STATIC_PIDS and loop_n % 10 != 0:
                continue
            if time.monotonic() >= deadline:
                break
            t_req = time.monotonic()
            try:
                r = await client.read_pid(p)
                consecutive_fail = 0
            except NotSupported:
                continue
            except EcuNoResponse:
                consecutive_fail += 1
                if consecutive_fail == 5:
                    rec.events.append(RecEvent(t_ms=t_ms(), type="ecu_no_response", detail="5 consecutive NO DATA"))
                continue
            except (TransportError, AdapterTimeout, AdapterError) as e:
                rec.events.append(RecEvent(t_ms=t_ms(), type="connection_lost", detail=str(e)))
                progress("connection_lost", error=str(e))
                if not reconnect:
                    raise
                await client.close()
                rep2 = await client.connect(retries=3)
                if not rep2.ok:
                    rec.events.append(RecEvent(t_ms=t_ms(), type="note", detail="reconnect failed; capture stopped"))
                    deadline = 0
                    break
                rec.events.append(RecEvent(t_ms=t_ms(), type="reconnected"))
                progress("reconnected")
                continue
            vals = {k: v for k, v in r.values.items()}
            rec.samples.append(RecSample(t_ms=t_ms(), pid=r.pid, ecu=r.ecu, raw=r.raw, values=vals))
            d = defs.get(p)
            if d:
                for o in d.outputs:
                    if o.key in vals and o.key not in seen_signals:
                        seen_signals[o.key] = RecSignal(key=o.key, pid=r.pid, unit=o.unit)
            # Pace like a real adapter (ELM327 ≈ 10–25 requests/s) so recordings stay realistic in size.
            spare = min_request_period_s - (time.monotonic() - t_req)
            if spare > 0:
                await asyncio.sleep(spare)
        loop_n += 1
        await asyncio.sleep(0)
    rec.signals = list(seen_signals.values())
    rec.duration_ms = t_ms()
    progress("done", samples=len(rec.samples))
    return rec


class ReplaySource:
    """Iterate a recording's samples with their original timing (or faster)."""

    def __init__(self, rec: Recording, speed: float = 1.0):
        self.rec = rec
        self.speed = speed

    async def __aiter__(self):  # type: ignore[override]
        t0 = time.monotonic()
        for s in self.rec.samples:
            if self.speed > 0:
                wait = s.t_ms / 1000 / self.speed - (time.monotonic() - t0)
                if wait > 0:
                    await asyncio.sleep(wait)
            yield s
