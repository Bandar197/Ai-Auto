"""Pure unit tests: AES-GCM blobs, blind index, password policy, prod config guard."""

from __future__ import annotations

import base64
import os

import pytest

from automind.core.config import DEV_JWT_SECRET, Settings
from automind.core.crypto import Cipher, CryptoError, blind_index, vin_blind_index
from automind.core.security import PasswordPolicyError, check_password_policy, hash_refresh_token, verify_totp

pytestmark = pytest.mark.nodb


def test_aes_gcm_roundtrip_versioned_and_tamper_evident():
    c = Cipher(os.urandom(32))
    b1, b2 = c.encrypt("2C3CDZAG7JH101234", aad=b"vin:1"), c.encrypt("2C3CDZAG7JH101234", aad=b"vin:1")
    assert b1 != b2  # random nonce
    assert b1[:1] == b"\x01" and len(b1) == 1 + 12 + 17 + 16
    assert c.decrypt_str(b1, aad=b"vin:1") == "2C3CDZAG7JH101234"
    with pytest.raises(CryptoError):
        c.decrypt(b1, aad=b"vin:2")  # bound to the row
    tampered = bytearray(b1)
    tampered[-1] ^= 1
    with pytest.raises(CryptoError):
        c.decrypt(bytes(tampered), aad=b"vin:1")
    with pytest.raises(CryptoError):
        Cipher(os.urandom(32)).decrypt(b1, aad=b"vin:1")  # wrong key
    with pytest.raises(CryptoError):
        c.decrypt(b"\x02" + b1[1:], aad=b"vin:1")  # unknown version


def test_blind_index_deterministic_and_normalised():
    k = os.urandom(32)
    assert vin_blind_index(k, "2c3cdzag7jh101234") == vin_blind_index(k, " 2C3CDZAG7JH101234 ")
    assert blind_index(k, "a") != blind_index(os.urandom(32), "a")


def test_password_policy_and_helpers():
    check_password_policy("a-very-unusual-passphrase", "x@example.com")
    for pw in ("short", "1234567890", "x@example.com", "XXXXXXXXXXXX"):
        with pytest.raises(PasswordPolicyError):
            check_password_policy(pw, "x@example.com")
    assert len(hash_refresh_token("abc")) == 32
    assert not verify_totp("JBSWY3DPEHPK3PXP", None) and not verify_totp("JBSWY3DPEHPK3PXP", "abc")


def test_prod_refuses_default_secrets():
    with pytest.raises(ValueError, match="refusing to start in prod"):
        Settings(environment="prod")
    key1 = base64.b64encode(os.urandom(32)).decode()
    key2 = base64.b64encode(os.urandom(32)).decode()
    s = Settings(
        environment="prod",
        jwt_secret="x" * 48,
        data_encryption_key=key1,
        blind_index_key=key2,
        database_url="postgresql+asyncpg://u:p@db:5432/automind",
    )
    assert s.jwt_secret.get_secret_value() != DEV_JWT_SECRET
    with pytest.raises(ValueError):
        Settings(data_encryption_key=base64.b64encode(b"short").decode())
    with pytest.raises(ValueError):
        Settings(db_app_role="automind_app; drop table x")
