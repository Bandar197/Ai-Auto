"""Test 1 — a REAL ELM327 Wi-Fi adapter plugged into a real vehicle.

Skipped unless AUTOMIND_HW_HOST is set, e.g. on Windows:
    set AUTOMIND_HW_HOST=192.168.0.10 && set AUTOMIND_HW_PORT=35000 && pytest -m hardware -s
Nothing here is mocked; a pass means the car really answered.
"""

import os

import pytest

from automind.obd.client import ObdClient
from automind.obd.transport.tcp import TcpTransport
from automind.recording.recorder import capture_session

pytestmark = [pytest.mark.hardware,
              pytest.mark.skipif(not os.environ.get("AUTOMIND_HW_HOST"), reason="no real adapter configured")]


async def test_real_adapter_end_to_end(tmp_path):
    host = os.environ["AUTOMIND_HW_HOST"]
    port = int(os.environ.get("AUTOMIND_HW_PORT", "35000"))
    c = ObdClient(TcpTransport(host, port), timeout=3.0)
    rep = await c.connect(retries=3)
    print("connection report:", rep.as_dict())
    assert rep.adapter_status == "connected", "phone/PC ↔ adapter link failed"
    assert rep.ecu_status == "connected", "adapter reachable but the vehicle did not answer (ignition on?)"
    assert not rep.is_simulator
    print("protocol:", rep.protocol_name, "| supported PIDs:", sorted(c.supported_pids()))
    print("VIN:", await c.read_vin())
    print("DTCs:", [(d.code, d.status) for d in await c.read_all_dtcs()])
    rec = await capture_session(c, duration_s=float(os.environ.get("AUTOMIND_HW_SECONDS", "20")))
    await c.close()
    rec.save(tmp_path / "hardware_session.json")
    assert rec.data_mode == "live" and rec.samples
    print("samples:", len(rec.samples), "saved to", tmp_path / "hardware_session.json")
