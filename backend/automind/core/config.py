"""Runtime configuration (environment variables prefixed with ``AUTOMIND_``).

Every variable is documented in ``backend/.env.example``. In ``prod`` the
application refuses to start while any secret still has its development
default, so a mis-deployed container fails loudly instead of running with
publicly known keys.
"""

from __future__ import annotations

import base64
import binascii
import re
from functools import lru_cache
from typing import Literal

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Development defaults. They are public (they live in the repository) and are
# therefore rejected when AUTOMIND_ENVIRONMENT=prod.
DEV_JWT_SECRET = "dev-only-insecure-jwt-secret-change-me-0123456789"  # noqa: S105
DEV_DATA_ENCRYPTION_KEY = base64.b64encode(b"automind-dev-data-key-32-bytes!!").decode()
DEV_BLIND_INDEX_KEY = base64.b64encode(b"automind-dev-blind-idx-32-bytes!").decode()
DEV_DATABASE_URL = "postgresql+asyncpg://automind_owner:automind_owner_pw@localhost:5432/automind"

_ROLE_RE = re.compile(r"^[a-z_][a-z0-9_]{0,62}$")


def _decode_key(value: str, name: str) -> bytes:
    try:
        raw = base64.b64decode(value, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ValueError(f"{name} must be base64") from exc
    if len(raw) != 32:
        raise ValueError(f"{name} must decode to exactly 32 bytes (got {len(raw)})")
    return raw


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="AUTOMIND_", env_file=".env", env_file_encoding="utf-8", extra="ignore")

    environment: Literal["dev", "test", "prod"] = "dev"
    version: str = "0.1.0"
    api_prefix: str = "/api/v1"

    # Database ------------------------------------------------------------------
    database_url: str = DEV_DATABASE_URL
    db_app_role: str = "automind_app"
    db_pool_size: int = Field(10, ge=1, le=200)
    db_max_overflow: int = Field(10, ge=0, le=200)
    db_null_pool: bool = False  # tests / serverless: no connection pooling
    db_ensure_partitions_on_startup: bool = True

    # Redis (optional: rate limiting) ----------------------------------------------
    redis_url: str | None = None

    # Tokens ---------------------------------------------------------------------
    jwt_secret: SecretStr = SecretStr(DEV_JWT_SECRET)
    jwt_algorithm: Literal["HS256", "HS384", "HS512", "RS256", "ES256"] = "HS256"
    jwt_private_key: SecretStr | None = None  # PEM, for RS256/ES256
    jwt_public_key: str | None = None  # PEM, for RS256/ES256
    access_token_ttl_s: int = Field(900, ge=60, le=86400)
    refresh_token_ttl_s: int = Field(30 * 86400, ge=3600, le=365 * 86400)

    # Application-layer encryption ------------------------------------------------
    data_encryption_key: SecretStr = SecretStr(DEV_DATA_ENCRYPTION_KEY)
    blind_index_key: SecretStr = SecretStr(DEV_BLIND_INDEX_KEY)

    # Password hashing (Argon2id) ---------------------------------------------------
    argon2_time_cost: int = Field(3, ge=1, le=20)
    argon2_memory_kib: int = Field(65536, ge=8192, le=1048576)
    argon2_parallelism: int = Field(4, ge=1, le=16)

    # Account lockout ---------------------------------------------------------------
    lockout_threshold: int = Field(5, ge=1, le=100)
    lockout_minutes: int = Field(15, ge=1, le=1440)

    # HTTP --------------------------------------------------------------------------
    cors_origins: str = ""  # comma separated, e.g. "https://admin.automind.sa,http://localhost:3000"
    trust_proxy_headers: bool = False  # honour X-Forwarded-For (only behind a trusted proxy)

    # Rate limiting -----------------------------------------------------------------
    rate_limit_enabled: bool = True
    rate_limit_auth_per_min: int = Field(10, ge=1)
    rate_limit_user_per_min: int = Field(120, ge=1)

    # Recordings ----------------------------------------------------------------------
    max_inline_recording_bytes: int = Field(1_000_000, ge=1024)

    # Demo (ECU simulator) ------------------------------------------------------------
    demo_time_scale: float | None = Field(None, gt=0, le=1000)  # None = simulator picks (≤ ~12 s wall clock)

    # LLM (optional) ----------------------------------------------------------------
    anthropic_api_key: SecretStr | None = None
    llm_model: str = "claude-opus-5-5"

    # Logging -----------------------------------------------------------------------
    log_level: str = "INFO"
    log_json: bool = True

    @field_validator("db_app_role")
    @classmethod
    def _role_name(cls, v: str) -> str:
        if not _ROLE_RE.match(v):
            raise ValueError("db_app_role must be a plain lower-case identifier")
        return v

    @field_validator("data_encryption_key", "blind_index_key")
    @classmethod
    def _key_len(cls, v: SecretStr, info) -> SecretStr:
        _decode_key(v.get_secret_value(), info.field_name)
        return v

    @model_validator(mode="after")
    def _prod_guard(self) -> Settings:
        if self.environment == "prod":
            problems = []
            if self.jwt_algorithm.startswith("HS"):
                secret = self.jwt_secret.get_secret_value()
                if secret == DEV_JWT_SECRET or len(secret) < 32:
                    problems.append("AUTOMIND_JWT_SECRET")
            elif not (self.jwt_private_key and self.jwt_public_key):
                problems.append("AUTOMIND_JWT_PRIVATE_KEY/AUTOMIND_JWT_PUBLIC_KEY")
            if self.data_encryption_key.get_secret_value() == DEV_DATA_ENCRYPTION_KEY:
                problems.append("AUTOMIND_DATA_ENCRYPTION_KEY")
            if self.blind_index_key.get_secret_value() == DEV_BLIND_INDEX_KEY:
                problems.append("AUTOMIND_BLIND_INDEX_KEY")
            if self.data_encryption_key.get_secret_value() == self.blind_index_key.get_secret_value():
                problems.append("AUTOMIND_BLIND_INDEX_KEY (must differ from the encryption key)")
            if self.database_url == DEV_DATABASE_URL:
                problems.append("AUTOMIND_DATABASE_URL")
            if problems:
                raise ValueError("refusing to start in prod with default/weak secrets: " + ", ".join(problems))
        return self

    # Convenience ---------------------------------------------------------------------
    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def data_key_bytes(self) -> bytes:
        return _decode_key(self.data_encryption_key.get_secret_value(), "data_encryption_key")

    @property
    def blind_key_bytes(self) -> bytes:
        return _decode_key(self.blind_index_key.get_secret_value(), "blind_index_key")


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
