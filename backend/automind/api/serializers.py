"""Row → response dict helpers (shapes from docs/API.md)."""

from __future__ import annotations

from collections.abc import Mapping
from decimal import Decimal
from typing import Any

from automind.core.crypto import Cipher, CryptoError, mask_vin


def num(v: Any) -> float | None:
    if v is None:
        return None
    return float(v) if isinstance(v, Decimal) else v


def user_out(r: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": str(r["id"]),
        "email": r["email"],
        "full_name": r["full_name"],
        "phone": r["phone"],
        "locale": r["locale"],
        "platform_role": r["platform_role"],
        "mfa_enabled": r["mfa_enabled"],
        "created_at": r["created_at"],
    }


def vin_aad(vehicle_id: Any) -> bytes:
    return b"vin:" + str(vehicle_id).encode()


def decrypt_vin(cipher: Cipher, r: Mapping[str, Any]) -> str | None:
    blob = r.get("vin_ciphertext")
    if not blob:
        return None
    try:
        return cipher.decrypt_str(bytes(blob), aad=vin_aad(r["id"]))
    except CryptoError:
        return None


def vehicle_out(r: Mapping[str, Any], cipher: Cipher, *, reveal: bool = False) -> dict[str, Any]:
    vin = decrypt_vin(cipher, r)
    out = {
        "id": str(r["id"]),
        "make": r["make"],
        "model": r["model"],
        "model_year": r["model_year"],
        "engine": r["engine"],
        "fuel_type": r["fuel_type"],
        "transmission": r["transmission"],
        "nickname": r["nickname"],
        "odometer_km": r["odometer_km"],
        "vin_masked": mask_vin(vin),
        "vin_wmi": r["vin_wmi"],
        "created_at": r["created_at"],
    }
    if reveal:
        out["vin"] = vin
    return out


def device_out(r: Mapping[str, Any]) -> dict[str, Any]:
    keys = (
        "name",
        "adapter_type",
        "transport",
        "host",
        "port",
        "ble_device_id",
        "ble_service_uuid",
        "ble_notify_uuid",
        "ble_write_uuid",
        "firmware_version",
        "is_certified",
        "last_seen_at",
        "created_at",
    )
    return {"id": str(r["id"]), **{k: r[k] for k in keys}}


def session_out(r: Mapping[str, Any]) -> dict[str, Any]:
    def s(v: Any) -> str | None:
        return str(v) if v is not None else None

    return {
        "id": str(r["id"]),
        "data_mode": r["data_mode"],
        "status": r["status"],
        "vehicle_id": s(r["vehicle_id"]),
        "device_id": s(r["device_id"]),
        "demo_scenario_key": r["demo_scenario_key"],
        "source_recording_id": s(r["source_recording_id"]),
        "protocol_name": r["protocol_name"],
        "mil_on": r["mil_on"],
        "dtc_count": r["dtc_count"],
        "health_score": r["health_score"],
        "started_at": r["started_at"],
        "completed_at": r["completed_at"],
        "engine_version": r["engine_version"],
        "kb_version": r["kb_version"],
    }


def recording_meta_out(r: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": str(r["id"]),
        "data_mode": r["data_mode"],
        "duration_ms": r["duration_ms"],
        "sample_count": r["sample_count"],
        "signals": list(r["signals"] or []),
        "session_id": str(r["session_id"]) if r["session_id"] else None,
        "created_at": r["created_at"],
    }


def plan_out(r: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "key": r["key"],
        "name_en": r["name_en"],
        "name_ar": r["name_ar"],
        "audience": r["audience"],
        "price_monthly": num(r["price_monthly"]),
        "price_yearly": num(r["price_yearly"]),
        "currency": r["currency"],
        "features": r["features"],
        "limits": r["limits"],
        "active": r["active"],
        "sort_order": r["sort_order"],
    }


def share_out(r: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "id": str(r["id"]),
        "session_id": str(r["session_id"]),
        "organization_id": str(r["shared_with_org_id"]),
        "include_vin": r["include_vin"],
        "include_live_data": r["include_live_data"],
        "consent_version": r["consent_version"],
        "granted_at": r["granted_at"],
        "expires_at": r["expires_at"],
        "revoked_at": r["revoked_at"],
    }


def plain(r: Mapping[str, Any], exclude: tuple[str, ...] = ()) -> dict[str, Any]:
    """Generic JSON-friendly copy of a row (UUIDs/Decimals/bytes handled)."""
    import uuid as _uuid

    out: dict[str, Any] = {}
    for k, v in r.items():
        if k in exclude:
            continue
        if isinstance(v, _uuid.UUID):
            v = str(v)
        elif isinstance(v, Decimal):
            v = float(v)
        elif isinstance(v, (bytes, memoryview)):
            continue  # ciphertexts / hashes are never exported raw
        out[k] = v
    return out
