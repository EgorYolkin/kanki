import hashlib
import hmac
import json
import os
import secrets
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated, Any

from fastapi import Depends, FastAPI, Header, HTTPException, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from . import __version__
from .db import Database, RevisionConflict, SnapshotRow, TokenRow
from .models import (
    Health,
    Identity,
    SnapshotRead,
    SnapshotWrite,
    TokenCreate,
    TokenCreated,
    TokenInfo,
)


@dataclass(frozen=True)
class Settings:
    database_path: Path
    admin_token: str | None
    max_snapshot_bytes: int


@dataclass(frozen=True)
class Principal:
    label: str
    role: str
    token_id: str | None = None


def if_none_match_matches(header_value: str, etag: str) -> bool:
    candidates = {candidate.strip() for candidate in header_value.split(",")}
    return "*" in candidates or etag in candidates or f"W/{etag}" in candidates


_UNSET: Any = object()
bearer = HTTPBearer(auto_error=False)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_app(
    *,
    database_path: Path | None = None,
    admin_token: str | None | Any = _UNSET,
    max_snapshot_bytes: int | None = None,
) -> FastAPI:
    resolved_admin_token = (
        os.getenv("KANKI_ADMIN_TOKEN") if admin_token is _UNSET else admin_token
    )
    settings = Settings(
        database_path=database_path
        or Path(os.getenv("KANKI_DATABASE", "data/kanki.sqlite3")),
        admin_token=resolved_admin_token,
        max_snapshot_bytes=max_snapshot_bytes
        or int(os.getenv("KANKI_MAX_SNAPSHOT_BYTES", str(10 * 1024 * 1024))),
    )

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        database = Database(settings.database_path)
        database.initialize()
        app.state.database = database
        app.state.settings = settings
        yield

    app = FastAPI(
        title="Kanki Server",
        version=__version__,
        lifespan=lifespan,
    )

    def get_db() -> Database:
        return app.state.database

    def get_settings() -> Settings:
        return app.state.settings

    DatabaseDep = Annotated[Database, Depends(get_db)]
    SettingsDep = Annotated[Settings, Depends(get_settings)]

    def authenticate(
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
        database: DatabaseDep,
        current_settings: SettingsDep,
    ) -> Principal:
        if credentials is None or not credentials.credentials:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail={"code": "missing_token"},
                headers={"WWW-Authenticate": "Bearer"},
            )
        token = credentials.credentials
        admin_token = current_settings.admin_token
        if admin_token and hmac.compare_digest(token, admin_token):
            return Principal(label="admin", role="admin")
        row = database.find_active_token(hash_token(token))
        if row is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail={"code": "invalid_token"},
                headers={"WWW-Authenticate": "Bearer"},
            )
        return Principal(label=row.label, role="device", token_id=row.id)

    def require_admin(
        principal: Annotated[Principal, Depends(authenticate)],
        current_settings: SettingsDep,
    ) -> Principal:
        if current_settings.admin_token is None:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"code": "admin_disabled"},
            )
        if principal.role != "admin":
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={"code": "admin_required"},
            )
        return principal

    PrincipalDep = Annotated[Principal, Depends(authenticate)]
    AdminDep = Annotated[Principal, Depends(require_admin)]

    def snapshot_response(row: SnapshotRow | None) -> SnapshotRead:
        if row is None:
            return SnapshotRead(
                revision=0,
                schema_version=1,
                data=None,
                updated_at=None,
            )
        return SnapshotRead(
            revision=row.revision,
            schema_version=row.schema_version,
            data=row.data,
            updated_at=row.updated_at,
        )

    def token_info(row: TokenRow) -> TokenInfo:
        return TokenInfo(
            id=row.id,
            label=row.label,
            created_at=row.created_at,
            revoked_at=row.revoked_at,
        )

    @app.get("/v1/health", response_model=Health)
    def health(database: DatabaseDep) -> Health:
        try:
            database.ping()
        except Exception as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail={"code": "database_unavailable"},
            ) from error
        return Health(
            version=__version__,
            time=datetime.now(timezone.utc).isoformat(),
        )

    @app.get("/v1/me", response_model=Identity)
    def me(principal: PrincipalDep) -> Identity:
        return Identity(label=principal.label, role=principal.role)

    @app.get("/v1/snapshot", response_model=SnapshotRead)
    def get_snapshot(
        principal: PrincipalDep,
        database: DatabaseDep,
        response: Response,
        if_none_match: Annotated[str | None, Header()] = None,
    ) -> SnapshotRead | Response:
        del principal
        row = database.read_snapshot()
        revision = row.revision if row is not None else 0
        etag = f'"{revision}"'
        response.headers["ETag"] = etag
        if if_none_match is not None and if_none_match_matches(if_none_match, etag):
            return Response(
                status_code=status.HTTP_304_NOT_MODIFIED,
                headers={"ETag": etag},
            )
        return snapshot_response(row)

    @app.put("/v1/snapshot", response_model=SnapshotRead)
    def put_snapshot(
        body: SnapshotWrite,
        principal: PrincipalDep,
        database: DatabaseDep,
        current_settings: SettingsDep,
    ) -> SnapshotRead:
        del principal
        encoded = json.dumps(body.data, ensure_ascii=False, separators=(",", ":"))
        if len(encoded.encode("utf-8")) > current_settings.max_snapshot_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                detail={"code": "snapshot_too_large"},
            )
        try:
            row = database.write_snapshot(
                schema_version=body.schema_version,
                data=body.data,
                base_revision=body.base_revision,
            )
        except RevisionConflict as conflict:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={
                    "code": "revision_conflict",
                    "current_revision": conflict.current_revision,
                },
            ) from conflict
        return snapshot_response(row)

    @app.post(
        "/v1/tokens",
        response_model=TokenCreated,
        status_code=status.HTTP_201_CREATED,
    )
    def create_token(
        body: TokenCreate,
        admin: AdminDep,
        database: DatabaseDep,
    ) -> TokenCreated:
        del admin
        token = secrets.token_hex(24)
        row = database.create_token(
            token_id=secrets.token_hex(8),
            label=body.label,
            token_hash=hash_token(token),
            created_at=datetime.now(timezone.utc).isoformat(),
        )
        return TokenCreated(id=row.id, label=row.label, token=token)

    @app.get("/v1/tokens", response_model=list[TokenInfo])
    def list_tokens(admin: AdminDep, database: DatabaseDep) -> list[TokenInfo]:
        del admin
        return [token_info(row) for row in database.list_tokens()]

    @app.delete("/v1/tokens/{token_id}", status_code=status.HTTP_204_NO_CONTENT)
    def revoke_token(
        token_id: str,
        admin: AdminDep,
        database: DatabaseDep,
    ) -> Response:
        del admin
        if not database.revoke_token(token_id):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail={"code": "token_not_found"},
            )
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    return app


app = create_app()
