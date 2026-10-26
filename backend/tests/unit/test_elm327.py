"""ELM327 command layer and client against the in-process emulator."""

import pytest

from automind.obd.client import ClearAuthorization, ObdClient
from automind.obd.elm327 import Elm327
from automind.obd.errors import EcuNoResponse, NotSupported, PolicyViolation
from automind.obd.transport.loopback import LoopbackTransport
from automind.simulator.elm_emulator import Elm327Emulator
from automind.simulator.scenarios import load_scenario


def _client(scenario="p0106_map_sensor", **kw):
    emu = Elm327Emulator(load_scenario(scenario), clock=lambda: 100.0, **kw)
    return ObdClient(LoopbackTransport(emu)), emu


async def test_echo_and_searching_are_stripped():
    emu = Elm327Emulator(load_scenario("healthy"), clock=lambda: 10.0)
    t = LoopbackTransport(emu)
    await t.open()
    elm = Elm327(t)
    assert "ELM327" in await elm.send("ATZ")  # echo on at this point
    await elm.at("ATH1")
    resp = await elm.query("0100")
    assert resp.messages and resp.messages[0].data[0] == 0x41
    assert "SEARCHING" in resp.raw


async def test_unknown_at_command_is_tolerated():
    emu = Elm327Emulator(load_scenario("healthy"), clock=lambda: 10.0)
    t = LoopbackTransport(emu)
    await t.open()
    elm = Elm327(t)
    assert await elm.at("ATXYZ", tolerate_unknown=True) == "?"


@pytest.mark.parametrize("protocol", ["6", "7", "8", "3", "4", "2"])
async def test_full_connect_all_protocols(protocol):
    c, _ = _client(protocol=protocol)
    rep = await c.connect(retries=1)
    assert rep.ok, rep
    assert rep.protocol_code == protocol
    assert rep.is_simulator is True
    assert await c.read_vin() == "AMDDEMX1234567890"
    codes = {(d.code, d.status) for d in await c.read_all_dtcs()}
    assert ("P0106", "stored") in codes
    rpm = (await c.read_pid("0C")).values["engine_rpm"]
    assert 600 < rpm < 900


async def test_ignition_off_reports_ecu_not_adapter():
    c, _ = _client(ignition_on=False)
    rep = await c.connect(retries=1)
    assert rep.adapter_status == "connected"
    assert rep.ecu_status == "no_response"
    assert not rep.ok


async def test_unsupported_pid_is_never_requested():
    c, _ = _client()
    await c.connect(retries=1)
    with pytest.raises(NotSupported):
        await c.read_pid("5C")  # oil temp not supported by the scenario


async def test_freeze_frame():
    c, _ = _client()
    await c.connect(retries=1)
    ff = await c.read_freeze_frame()
    assert ff["dtc"] == "P0106"
    assert ff["values"]["map_kpa"] == 61


async def test_clear_dtcs_requires_authorization_and_engine_off():
    c, emu = _client()
    await c.connect(retries=1)
    with pytest.raises(PolicyViolation):
        await c.clear_dtcs(ClearAuthorization(operation_id="", approved=False, consent_text=""))
    auth = ClearAuthorization(operation_id="op1", approved=True, consent_text="I understand")
    with pytest.raises(PolicyViolation, match="engine must be off"):
        await c.clear_dtcs(auth)
    emu.vehicle.engine_running = False
    res = await c.clear_dtcs(auth)
    assert res["ok"]
    assert [d.code for d in await c.read_dtcs("03")] == []
    assert [d.code for d in await c.read_dtcs("0A")] == ["P0106"]  # permanent codes survive


async def test_no_data_on_unknown_service_pid():
    c, _ = _client()
    await c.connect(retries=1)
    with pytest.raises(EcuNoResponse):
        await c.elm.query("0901")  # not supported
