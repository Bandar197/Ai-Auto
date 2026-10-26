"""Application-layer encryption for sensitive identifiers.

* AES-256-GCM with a random 96-bit nonce; blob layout ``b"\\x01" + nonce + ciphertext||tag``
  (the leading byte is the format version so keys/algorithms can rotate).
* HMAC-SHA256 "blind index" for exact-match lookups (VIN) without storing
  the plaintext.
"""

from __future__ import annotations

import hashlib
import hmac
import os
import re

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

BLOB_VERSION = b"\x01"
_NONCE_LEN = 12

# 17 characters, digits and capital letters except I, O and Q (ISO 3779).
VIN_RE = re.compile(r"^[A-HJ-NPR-Z0-9]{17}$")


class CryptoError(ValueError):
    pass


class Cipher:
    def __init__(self, key: bytes) -> None:
        if len(key) != 32:
            raise CryptoError("AES-256 key must be 32 bytes")
        self._aead = AESGCM(key)

    def encrypt(self, plaintext: str | bytes, aad: bytes | None = None) -> bytes:
        data = plaintext.encode("utf-8") if isinstance(plaintext, str) else plaintext
        nonce = os.urandom(_NONCE_LEN)
        return BLOB_VERSION + nonce + self._aead.encrypt(nonce, data, aad)

    def decrypt(self, blob: bytes, aad: bytes | None = None) -> bytes:
        blob = bytes(blob)
        if len(blob) < 1 + _NONCE_LEN + 16 or blob[:1] != BLOB_VERSION:
            raise CryptoError("unsupported ciphertext format")
        nonce, ct = blob[1 : 1 + _NONCE_LEN], blob[1 + _NONCE_LEN :]
        try:
            return self._aead.decrypt(nonce, ct, aad)
        except Exception as exc:  # cryptography raises InvalidTag
            raise CryptoError("decryption failed") from exc

    def decrypt_str(self, blob: bytes, aad: bytes | None = None) -> str:
        return self.decrypt(blob, aad).decode("utf-8")


def blind_index(key: bytes, value: str) -> bytes:
    return hmac.new(key, value.encode("utf-8"), hashlib.sha256).digest()


def normalize_vin(vin: str) -> str:
    """Upper-case, strip whitespace/dashes and validate. Raises ValueError."""
    v = re.sub(r"[\s-]", "", vin or "").upper()
    if not VIN_RE.match(v):
        raise ValueError("VIN must be 17 characters (A-Z without I, O, Q, and digits)")
    return v


def mask_vin(vin: str | None) -> str | None:
    """``2C3CDZAG7JH101234`` → ``2C3CDZ*******1234`` (WMI+VDS prefix and last 4 visible)."""
    if not vin:
        return None
    if len(vin) < 10:
        return "*" * len(vin)
    return vin[:6] + "*" * (len(vin) - 10) + vin[-4:]


def vin_blind_index(key: bytes, vin: str) -> bytes:
    return blind_index(key, normalize_vin(vin))
