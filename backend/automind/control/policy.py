"""AutoMind Control policy — a pure function, no I/O.

The phone holds the OBD connection, so the server *authorises* and the
device *executes*. Rules, in order:

1. Prohibited procedures (odometer change, emissions delete, immobilizer
   bypass, crash-data reset) are always rejected, in every data mode.
2. The user must confirm and give consent text.
3. Engine-state requirements of the procedure are checked; ``clear_dtcs``
   additionally requires engine off and vehicle speed 0.
4. ``demo`` / ``replay``: approved as **simulated** — no command ever reaches a
   real vehicle (the simulator or nothing executes it).
5. ``live`` + not ``enabled_by_default``: needs an active allow-list entry
   matching make / model / year range / ECU / adapter type and, when the entry
   requires it, a certified device.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

DataMode = Literal["live", "demo", "replay"]

SIMULATED_NOTICE_EN = "Simulation only: this operation runs against demo/replay data. No command is sent to a real vehicle."
SIMULATED_NOTICE_AR = "محاكاة فقط: تُنفَّذ هذه العملية على بيانات تجريبية أو معادة. لا يُرسل أي أمر إلى سيارة حقيقية."


@dataclass(frozen=True)
class Procedure:
    key: str
    risk_level: str
    safety_category: str
    enabled_by_default: bool
    is_prohibited: bool
    required_engine_state: str = "any"  # off | ignition_on | running | any
    obd_service: str | None = None
    level: int = 1


@dataclass(frozen=True)
class AllowlistEntry:
    active: bool
    make: str | None = None
    model: str | None = None
    year_from: int | None = None
    year_to: int | None = None
    ecu_address: str | None = None
    adapter_type: str | None = None
    requires_certified_device: bool = True


@dataclass(frozen=True)
class VehicleCtx:
    make: str | None = None
    model: str | None = None
    model_year: int | None = None


@dataclass(frozen=True)
class DeviceCtx:
    adapter_type: str | None = None
    is_certified: bool = False


@dataclass(frozen=True)
class Conditions:
    engine_running: bool | None = None
    vehicle_speed_kmh: float | None = None


@dataclass(frozen=True)
class ControlRequest:
    data_mode: DataMode
    confirmed: bool
    consent_text: str
    conditions: Conditions = field(default_factory=Conditions)
    ecu_address: str | None = None


@dataclass(frozen=True)
class Decision:
    approved: bool
    simulated: bool = False
    code: str | None = None
    reason_en: str | None = None
    reason_ar: str | None = None
    commands: tuple[str, ...] = ()
    notice_en: str | None = None
    notice_ar: str | None = None


def _reject(code: str, en: str, ar: str) -> Decision:
    return Decision(approved=False, code=code, reason_en=en, reason_ar=ar)


def _eq(a: str | None, b: str | None) -> bool:
    return (a or "").strip().casefold() == (b or "").strip().casefold()


def allowlist_matches(
    entry: AllowlistEntry, vehicle: VehicleCtx | None, device: DeviceCtx | None, ecu_address: str | None
) -> bool:
    """An entry matches when every constraint it sets is satisfied (None = wildcard)."""
    if not entry.active:
        return False
    v = vehicle or VehicleCtx()
    if entry.make is not None and not _eq(entry.make, v.make):
        return False
    if entry.model is not None and not _eq(entry.model, v.model):
        return False
    if entry.year_from is not None and (v.model_year is None or v.model_year < entry.year_from):
        return False
    if entry.year_to is not None and (v.model_year is None or v.model_year > entry.year_to):
        return False
    if entry.ecu_address is not None and not _eq(entry.ecu_address, ecu_address):
        return False
    if entry.adapter_type is not None and not _eq(entry.adapter_type, device.adapter_type if device else None):
        return False
    return True


def evaluate(
    procedure: Procedure,
    request: ControlRequest,
    *,
    vehicle: VehicleCtx | None = None,
    device: DeviceCtx | None = None,
    allowlist: list[AllowlistEntry] | tuple = (),
) -> Decision:
    # 1. prohibited — always, in every mode
    if procedure.is_prohibited or procedure.risk_level == "prohibited":
        return _reject(
            "prohibited",
            "This operation is prohibited and can never be performed.",
            "هذه العملية محظورة ولا يمكن تنفيذها إطلاقاً.",
        )

    # 2. explicit confirmation + consent
    if not request.confirmed:
        return _reject("not_confirmed", "You must confirm the operation.", "يجب تأكيد العملية.")
    if not (request.consent_text or "").strip():
        return _reject("consent_missing", "Consent text is required.", "نص الموافقة مطلوب.")

    # 3. vehicle state
    cond = request.conditions
    if procedure.key == "clear_dtcs":
        if cond.engine_running is not False:
            return _reject(
                "engine_running",
                "Turn the engine off (ignition on) before clearing codes.",
                "أطفئ المحرك (مع تشغيل الإشعال) قبل مسح الأكواد.",
            )
        if cond.vehicle_speed_kmh is None or cond.vehicle_speed_kmh != 0:
            return _reject(
                "vehicle_moving",
                "The vehicle must be stationary (speed 0).",
                "يجب أن تكون السيارة متوقفة تماماً (السرعة 0).",
            )
    elif procedure.required_engine_state == "off" and cond.engine_running is not False:
        return _reject(
            "engine_running",
            "This operation requires the engine to be off.",
            "تتطلب هذه العملية إطفاء المحرك.",
        )
    elif procedure.required_engine_state == "running" and cond.engine_running is not True:
        return _reject(
            "engine_not_running",
            "This operation requires the engine to be running.",
            "تتطلب هذه العملية تشغيل المحرك.",
        )

    commands = (procedure.obd_service,) if procedure.obd_service else ()

    # 4. simulated modes never touch a real vehicle
    if request.data_mode in ("demo", "replay"):
        return Decision(
            approved=True,
            simulated=True,
            commands=commands,
            notice_en=SIMULATED_NOTICE_EN,
            notice_ar=SIMULATED_NOTICE_AR,
        )

    # 5. live: allow-list for anything not enabled by default
    if not procedure.enabled_by_default:
        matching = [e for e in allowlist if allowlist_matches(e, vehicle, device, request.ecu_address)]
        if not matching:
            return _reject(
                "not_allowlisted",
                "Not validated for this vehicle/ECU/adapter combination.",
                "هذه العملية غير معتمدة لهذه السيارة أو وحدة التحكم أو المحوّل.",
            )
        certified = bool(device and device.is_certified)
        if not any((not e.requires_certified_device) or certified for e in matching):
            return _reject(
                "device_not_certified",
                "A certified OBD device is required for this operation.",
                "تتطلب هذه العملية جهاز OBD معتمداً.",
            )
    return Decision(approved=True, commands=commands)
