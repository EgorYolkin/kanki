from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class Health(BaseModel):
    status: Literal["ok"] = "ok"
    version: str
    time: str


class Identity(BaseModel):
    label: str
    role: Literal["admin", "device"]


class SnapshotWrite(BaseModel):
    schema_version: Literal[1] = 1
    base_revision: int = Field(ge=0)
    data: dict[str, Any]


class SnapshotRead(BaseModel):
    revision: int
    schema_version: int
    data: dict[str, Any] | None
    updated_at: str | None


class TokenCreate(BaseModel):
    label: str = Field(min_length=1, max_length=64)


class TokenCreated(BaseModel):
    id: str
    label: str
    token: str


class TokenInfo(BaseModel):
    id: str
    label: str
    created_at: str
    revoked_at: str | None
