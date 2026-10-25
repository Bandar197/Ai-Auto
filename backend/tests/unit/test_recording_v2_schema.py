"""recording.v2 must stay backward-compatible with v1 and enforce the honest recorder states."""

import json
from pathlib import Path

import pytest

from automind.recording.format import Recording, RecSource

jsonschema = pytest.importorskip("jsonschema")
SCHEMA = json.loads(
    (Path(__file__).resolve().parents[3] / "shared" / "schemas" / "recording.v2.schema.json").read_text(encoding="utf-8")
)


def _v1() -> dict:
    return json.loads(Recording(data_mode="live", source=RecSource(kind="elm327_ble")).to_json())


def test_a_v1_recording_is_valid_v2():
    jsonschema.validate(_v1(), SCHEMA)  # readers of v2 accept v1 files unchanged


def test_full_v2_evidence_validates():
    doc = _v1() | {
        "format": "automind.recording.v2",
        "adapter_capabilities": {
            "name": "LONAUTO", "connection": "ble", "firmware": "ELM327 v1.5", "voltage": 12.4,
            "protocol": "ISO 15765-4 (CAN 11/500)",
            "capabilities": {"headers": True, "iso_tp": True, "flow_control": None},
            "probe": [{"cmd": "ATI", "response": "ELM327 v1.5", "ok": True}, {"cmd": "AT@1", "response": "?", "ok": False}],
        },
        "ecu_coverage": [
            {"key": "ecm", "state": "faults_present", "request_id": "7E0", "response_id": "7E8", "id_bits": 11, "dtc_count": 1},
            {"key": "srs", "state": "timed_out", "request_id": "7D4", "response_id": "7DC", "id_bits": 11,
             "reason": "no response", "source": "modules.json verified=false"},
        ],
        "tx_rx_frames": [{"t_ms": 0, "dir": "tx", "data": "19 02 FF", "can_id": "7D4"}],
        "clear_operations": [{"id": "c1", "requested_at": "2026-10-25T10:00:00Z", "service": "04",
                              "result": "cleared", "context": "allowed", "target_modules": ["ecm"]}],
        "verification": {"status": "cleared", "per_code": [{"code": "P0106", "outcome": "cleared"}],
                         "lamp_off_confirmed_by": "user"},
        "warnings": [{"code": "srs_unverified", "en": "Couldn't verify SRS", "ar": "تعذّر التحقق"}],
        "file_hashes": {"dtcs.csv": "a" * 64},
        "audit_events": [{"t": "2026-10-25T10:00:00Z", "type": "clear_requested", "actor": "user"}],
        "session_state": "interrupted",
    }
    jsonschema.validate(doc, SCHEMA)


@pytest.mark.parametrize(
    "patch",
    [
        {"ecu_coverage": [{"key": "srs", "state": "healthy"}]},  # no vague "healthy" state
        {"tx_rx_frames": [{"t_ms": 0, "dir": "sideways", "data": "x"}]},
        {"file_hashes": {"dtcs.csv": "not-a-sha"}},
        {"clear_operations": [{"id": "c", "requested_at": "t", "service": "04", "result": "magic"}]},
        {"data_mode": "replay"},  # a recording is never relabelled
    ],
)
def test_invalid_v2_is_rejected(patch):
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(_v1() | patch, SCHEMA)
