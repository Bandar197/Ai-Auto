"""Run a demo session end-to-end: simulator ⇄ real OBD client ⇄ recorder."""

from __future__ import annotations

from automind.obd.client import ObdClient
from automind.obd.transport.tcp import TcpTransport
from automind.recording.format import Recording, RecVehicle
from automind.recording.recorder import capture_session
from automind.simulator.scenarios import load_scenario
from automind.simulator.server import SimulatorConfig, SimulatorServer


async def run_demo(
    scenario_key: str,
    duration_s: float = 60,
    *,
    time_scale: float | None = None,
    seed: int = 7,
    protocol: str | None = None,
) -> Recording:
    """Start the ECU simulator on a free local port, scan it with the real
    client, and return the recording (data_mode = 'demo').

    time_scale > 1 compresses simulated time (e.g. 120 s of drive cycle in 30 s).
    By default it is chosen so a run takes at most ~12 s of wall-clock time.
    """
    if time_scale is None:
        time_scale = max(1.0, duration_s / 12.0)
    scenario = load_scenario(scenario_key)
    cfg = SimulatorConfig(scenario=scenario_key, host="127.0.0.1", port=0, time_scale=time_scale, seed=seed,
                          protocol=protocol)
    async with SimulatorServer(cfg) as srv:
        client = ObdClient(TcpTransport("127.0.0.1", srv.port, connect_timeout=3))
        rep = await client.connect(retries=2, backoff=0.2)
        if not rep.ok:
            raise RuntimeError(f"simulator connection failed: {rep.error_code} {rep.error_message}")
        try:
            rec = await capture_session(
                client, duration_s=duration_s / max(time_scale, 1e-6), app="automind-demo",
                min_request_period_s=0.04 / max(time_scale, 1e-6),
            )
        finally:
            await client.close()
    assert rec.data_mode == "demo", "simulator data must be recorded as demo"
    rec.source.demo_scenario = scenario_key
    if time_scale != 1.0:  # express timestamps in simulated (vehicle) time
        for smp in rec.samples:
            smp.t_ms = int(smp.t_ms * time_scale)
        for ev in rec.events:
            ev.t_ms = int(ev.t_ms * time_scale)
        rec.duration_ms = int(rec.duration_ms * time_scale)
    v = scenario["vehicle"]
    rec.vehicle = RecVehicle(vin=rec.vehicle.vin, make=v.get("make"), model=v.get("model"),
                             model_year=v.get("model_year"))
    return rec
