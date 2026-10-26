"""UDS (ISO 14229) extended-diagnostics request builders and response parsers.

Byte sequences follow ISO 14229-1 service 0x19 0x02 (ReadDTCByStatusMask) and
0x14 (ClearDiagnosticInformation). No hardware involved — pure codec tests.
"""

import pytest

from automind.obd.uds import (
    UdsError,
    UdsModule,
    build_clear_request,
    build_read_dtc_request,
    parse_clear_response,
    parse_read_dtc_response,
)


def test_request_builders():
    assert build_read_dtc_request() == "1902FF"
    assert build_read_dtc_request(0x08) == "190208"
    assert build_clear_request() == "14FFFFFF"
    assert build_clear_request(0xFFFF33) == "14FFFF33"
    with pytest.raises(ValueError):
        build_read_dtc_request(0x100)
    with pytest.raises(ValueError):
        build_clear_request(0x1000000)


def test_parse_read_dtc_response_airbag_codes():
    # 59 02 <avail=FF> then records of {DTC hi, mid, ftb, status}.
    # B0051 (hi=0x80,mid=0x51) ftb=00 status 0x09 (confirmed+testFailed);
    # B1013 (hi=0x90,mid=0x13) ftb=11 status 0x08 (confirmed only).
    data = bytes.fromhex("5902FF" + "80510009" + "90131108")
    dtcs = parse_read_dtc_response(data)
    assert [d.code for d in dtcs] == ["B0051", "B1013"]
    assert dtcs[0].display == "B0051" and dtcs[0].ftb == 0
    assert dtcs[0].active is True and dtcs[0].confirmed is True
    assert dtcs[1].display == "B1013-11" and dtcs[1].ftb == 0x11
    assert dtcs[1].confirmed is True and dtcs[1].active is False


def test_parse_read_dtc_skips_filler_and_empty():
    assert parse_read_dtc_response(bytes.fromhex("5902FF")) == []
    assert parse_read_dtc_response(bytes.fromhex("5902FF00000000")) == []


def test_parse_read_dtc_rejects_wrong_service():
    with pytest.raises(UdsError):
        parse_read_dtc_response(bytes.fromhex("6202FF"))


def test_negative_response_surfaces_nrc():
    # 7F 19 22 → conditions not correct (e.g. engine running when the module refuses).
    with pytest.raises(UdsError) as ei:
        parse_read_dtc_response(bytes.fromhex("7F1922"))
    assert ei.value.code == "conditions_not_correct"
    assert ei.value.nrc == 0x22


def test_parse_clear_response():
    assert parse_clear_response(bytes.fromhex("54")) is True
    assert parse_clear_response(b"") is False
    with pytest.raises(UdsError):
        parse_clear_response(bytes.fromhex("7F1431"))  # request out of range


def test_module_address_validation():
    m = UdsModule("srs", "Airbag (SRS)", "الوسائد الهوائية", request_id=0x7E0, response_id=0x7E8, safety_category="airbag")
    assert m.id_bits == 11
    with pytest.raises(ValueError):
        UdsModule("x", "x", "x", request_id=0x800, response_id=0x7E8)  # out of 11-bit range
    with pytest.raises(ValueError):
        UdsModule("x", "x", "x", request_id=1, response_id=2, id_bits=16)
