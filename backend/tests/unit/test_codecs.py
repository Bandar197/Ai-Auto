"""PID / DTC / frame decoding with byte inputs from the SAE J1979 examples."""

import pytest

from automind.obd.dtc import decode_dtc, decode_dtc_list, encode_dtc
from automind.obd.frames import first_per_ecu, parse_response
from automind.obd.pids import decode_monitor_status, decode_pid, decode_supported_bitmask, pid_defs
from automind.simulator.elm_emulator import encode_pid_value


@pytest.mark.parametrize(
    ("pid", "data", "key", "expected"),
    [
        ("0C", "1A F8", "engine_rpm", 1726.0),
        ("05", "7B", "coolant_temp", 83),
        ("06", "80", "stft_b1", 0.0),
        ("06", "00", "stft_b1", -100.0),
        ("10", "01 F4", "maf_gs", 5.0),
        ("42", "37 0E", "module_voltage", 14.094),
        ("0B", "21", "map_kpa", 33),
        ("0D", "50", "vehicle_speed", 80),
        ("0E", "94", "timing_advance", 10.0),
        ("11", "FF", "throttle_pos", 100.0),
        ("2F", "80", "fuel_level", 50.1961),
        ("A6", "00 01 E2 40", "odometer_km", 12345.6),
    ],
)
def test_decode_pid(pid, data, key, expected):
    v = decode_pid(pid, bytes.fromhex(data))
    assert v[key] == pytest.approx(expected, abs=1e-3)


def test_o2_trim_not_used():
    v = decode_pid("14", bytes.fromhex("5A FF"))
    assert v["o2_b1s1_voltage"] == pytest.approx(0.45)
    assert v["o2_b1s1_stft"] is None


def test_signed_evap_pressure():
    assert decode_pid("32", bytes.fromhex("FF 9C"))["evap_vapor_pressure"] == pytest.approx(-25.0)


def test_supported_bitmask():
    pids = decode_supported_bitmask(0, bytes.fromhex("BE 1F A8 13"))
    assert pids[:5] == ["01", "03", "04", "05", "06"]
    assert "20" in pids  # next range available


def test_monitor_status():
    ms = decode_monitor_status(bytes.fromhex("82 07 65 04"))
    assert ms["mil_on"] is True and ms["dtc_count"] == 2
    assert ms["monitors"]["evap_system"] == {"available": True, "complete": False}


@pytest.mark.parametrize(("b", "code"), [("0106", "P0106"), ("0171", "P0171"), ("C123", "U0123"),
                                          ("4171", "C0171"), ("8210", "B0210"), ("1234", "P1234")])
def test_dtc_roundtrip(b, code):
    raw = bytes.fromhex(b)
    assert decode_dtc(raw[0], raw[1]) == code
    assert encode_dtc(code) == (raw[0], raw[1])


def test_dtc_list_skips_filler():
    assert decode_dtc_list(bytes.fromhex("0106 0000 0171")) == ["P0106", "P0171"]


def test_encode_decode_roundtrip_all_linear_pids():
    for pid, d in pid_defs().items():
        if d.kind != "linear" or not d.outputs:
            continue
        vals = {o.key: (o.min + o.max) / 2 for o in d.outputs}
        enc = encode_pid_value(pid, vals)
        dec = decode_pid(pid, enc)
        for o in d.outputs:
            assert dec[o.key] == pytest.approx(vals[o.key], abs=max(abs(o.scale), 1e-6)), (pid, o.key)


def test_can11_single_and_multi_ecu():
    text = "7E8 06 41 00 BE 3F A8 13 00\r7E9 06 41 00 80 00 00 00 00"
    msgs = parse_response(text)
    by = first_per_ecu(msgs)
    assert by["7E8"].data == bytes.fromhex("41 00 BE 3F A8 13")
    assert by["7E9"].data == bytes.fromhex("41 00 80 00 00 00")


def test_can11_isotp_vin():
    text = ("7E8 10 14 49 02 01 31 47 31\r7E8 21 4A 43 35 34 34 34 52\r7E8 22 37 32 35 32 33 36 37")
    m = parse_response(text)[0]
    assert m.data[:3] == bytes.fromhex("49 02 01") and m.data[3:].decode() == "1G1JC5444R7252367"
    assert m.frames == 3


def test_can_out_of_order_frame_dropped():
    text = "7E8 10 14 49 02 01 31 47 31\r7E8 22 37 32 35 32 33 36 37"
    assert parse_response(text) == []


def test_can29():
    m = parse_response("18 DA F1 10 04 41 0C 1A F8 00 00 00")[0]
    assert m.ecu == "18DAF110" and m.data == bytes.fromhex("41 0C 1A F8")


def test_spaces_off():
    m = parse_response("7E804410C1AF8000000")[0]
    assert m.ecu == "7E8" and m.data == bytes.fromhex("41 0C 1A F8")


def test_legacy_with_checksum_and_merge():
    msgs = parse_response("48 6B 10 43 01 06 01 71 00 00 20\r48 6B 10 43 03 00 00 00 00 00 FF",
                          protocol_family="legacy")
    assert len(msgs) == 1 and msgs[0].ecu == "10"
    assert decode_dtc_list(msgs[0].data[1:]) == ["P0106", "P0171", "P0300"]


def test_headers_off_multiframe():
    text = "014\r0: 49 02 01 31 47 31\r1: 4A 43 35 34 34 34 52\r2: 37 32 35 32 33 36 37"
    m = parse_response(text, headers=False)[0]
    assert m.data[3:].decode() == "1G1JC5444R7252367"
