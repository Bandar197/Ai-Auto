"""Typed errors for the OBD stack."""

from __future__ import annotations


class ObdError(Exception):
    """Base class."""

    code = "obd_error"


class TransportError(ObdError):
    """The phone/PC ↔ adapter link failed (socket, BLE, serial)."""

    code = "transport_error"


class AdapterTimeout(ObdError):
    """The adapter did not answer with a '>' prompt in time."""

    code = "adapter_timeout"


class AdapterError(ObdError):
    """The adapter answered with an error string (e.g. '?', 'BUFFER FULL')."""

    def __init__(self, code: str, raw: str):
        super().__init__(f"{code}: {raw!r}")
        self.code = code
        self.raw = raw


class EcuNoResponse(ObdError):
    """Adapter ↔ vehicle link: no ECU answered (UNABLE TO CONNECT, NO DATA...)."""

    def __init__(self, code: str, raw: str = ""):
        super().__init__(code)
        self.code = code
        self.raw = raw


class NotSupported(ObdError):
    """The vehicle did not report support for the requested PID/service."""

    code = "not_supported"


class PolicyViolation(ObdError):
    """A write operation was attempted without the required authorisation."""

    code = "policy_violation"
