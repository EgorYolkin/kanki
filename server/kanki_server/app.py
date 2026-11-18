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

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, Response, status
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from . import __version__
from .apkg import build_apkg
from .changes import (
    MAX_CHANGES_BYTES,
    MAX_INT64,
    UUID_PATTERN,
    ChangePage,
    ChangeReceipt,
    ChangeWrite,
)
from .db import (
    ChangesConflict,
    Database,
    PublicationIdentityConflict,
    RevisionConflict,
    SnapshotRow,
    TokenRow,
)
from .models import (
    Health,
    Identity,
    SnapshotRead,
    SnapshotWrite,
    TokenCreate,
    TokenCreated,
    TokenInfo,
)
from .publication import (
    MAX_PUBLISH_BYTES,
    InvalidDocument,
    PublishRequest,
    PublishResponse,
    parse_documents,
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

# Запас на конверт {"schema_version","base_revision","data"}: ранний reject по
# Content-Length не должен отвергать тело, которое пройдёт проверку данных.
CONTENT_LENGTH_SLACK_BYTES = 64 * 1024
PUBLISH_PATH = "/v1/publish"
CHANGES_PATH = "/v1/changes"
APKG_MEDIA_TYPE = "application/zip"


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _unique_json_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    fields = dict(pairs)
    if len(fields) != len(pairs):
        raise ValueError("JSON keys must be unique")
    return fields


async def _read_bounded_json_body(
    request: Request, *, limit: int, too_large_code: str
) -> bytearray:
    media_type = request.headers.get("content-type", "").split(";", 1)[0]
    if media_type.strip().lower() != "application/json":
        raise HTTPException(status_code=415, detail={"code": "expected_json"})

    body = bytearray()
    async for chunk in request.stream():
        if len(body) + len(chunk) > limit:
            raise HTTPException(status_code=413, detail={"code": too_large_code})
        body.extend(chunk)
    return body


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

    @app.middleware("http")
    async def reject_oversized_body(request: Request, call_next):
        """Отклоняет заведомо большое тело до чтения, а не после буферизации."""
        if request.url.path in (PUBLISH_PATH, CHANGES_PATH):
            return await call_next(request)
        content_length = request.headers.get("content-length")
        if content_length is not None:
            try:
                declared = int(content_length)
            except ValueError:
                declared = 0
            limit = settings.max_snapshot_bytes + CONTENT_LENGTH_SLACK_BYTES
            if declared > limit:
                return JSONResponse(
                    status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                    content={"detail": {"code": "snapshot_too_large"}},
                )
        return await call_next(request)

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
        # Сравнение в байтах: str-вариант бросает TypeError на не-ASCII
        # (header bytes 0x80–0xFF декодируются Starlette как latin-1).
        if admin_token and hmac.compare_digest(
            token.encode("utf-8"), admin_token.encode("utf-8")
        ):
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

    @app.get(CHANGES_PATH, response_model=ChangePage)
    def get_changes(
        principal: PrincipalDep,
        database: DatabaseDep,
        since: Annotated[int, Query(ge=0, le=MAX_INT64)],
        anchor: Annotated[str | None, Query(pattern=UUID_PATTERN)] = None,
    ) -> ChangePage:
        del principal
        try:
            return database.read_changes(since, anchor)
        except ChangesConflict as error:
            raise HTTPException(status_code=409, detail={"code": error.code}) from error

    async def read_changes_body(request: Request, principal: PrincipalDep) -> bytearray:
        del principal
        return await _read_bounded_json_body(
            request, limit=MAX_CHANGES_BYTES, too_large_code="changes_too_large"
        )

    # The request and GET response use the same review and progress schemas.
    change_write_schema = ChangeWrite.model_json_schema(
        ref_template="#/components/schemas/{model}"
    )
    change_write_schema.pop("$defs")

    @app.post(
        CHANGES_PATH,
        response_model=ChangeReceipt,
        openapi_extra={"requestBody": {
            "required": True,
            "content": {"application/json": {"schema": change_write_schema}},
        }},
    )
    def post_changes(
        raw: Annotated[bytearray, Depends(read_changes_body)], database: DatabaseDep
    ) -> ChangeReceipt:
        try:
            data = json.loads(raw.decode("utf-8"), object_pairs_hook=_unique_json_object)
            request = ChangeWrite.model_validate(data)
        except (ValueError, RecursionError) as error:
            raise HTTPException(status_code=422, detail={"code": "invalid_changes"}) from error
        try:
            return ChangeReceipt(accepted=database.append_changes(request))
        except ChangesConflict as error:
            raise HTTPException(status_code=409, detail={"code": error.code}) from error

    async def read_publish_body(request: Request, principal: PrincipalDep) -> bytearray:
        del principal
        return await _read_bounded_json_body(
            request, limit=MAX_PUBLISH_BYTES, too_large_code="publication_too_large"
        )

    @app.post(
        PUBLISH_PATH,
        response_model=PublishResponse,
        openapi_extra={"requestBody": {
            "required": True,
            "content": {"application/json": {"schema": PublishRequest.model_json_schema()}},
        }},
    )
    def publish(
        raw: Annotated[bytearray, Depends(read_publish_body)],
        database: DatabaseDep,
    ) -> PublishResponse:
        try:
            data = json.loads(raw.decode("utf-8"), object_pairs_hook=_unique_json_object)
            request = PublishRequest.model_validate(data)
        except (ValueError, RecursionError) as error:
            raise HTTPException(status_code=422, detail={"code": "invalid_publication"}) from error
        try:
            notes = parse_documents(request.documents)
        except InvalidDocument as error:
            raise HTTPException(
                status_code=422,
                detail={"code": error.code, "document_index": error.index},
            ) from error
        try:
            return PublishResponse(notes=database.publish(notes))
        except PublicationIdentityConflict as error:
            raise HTTPException(status_code=409, detail={"code": "guid_conflict"}) from error

    @app.get(
        "/v1/export.apkg",
        response_class=Response,
        responses={200: {
            "description": "Anki exchange v1 package",
            "content": {APKG_MEDIA_TYPE: {"schema": {"type": "string", "format": "binary"}}},
        }},
    )
    def export_apkg(principal: PrincipalDep, database: DatabaseDep) -> Response:
        del principal
        notes = database.read_publications()
        if not notes:
            raise HTTPException(status_code=404, detail={"code": "no_publications"})
        return Response(
            build_apkg(notes),
            media_type=APKG_MEDIA_TYPE,
            headers={
                "Content-Disposition": 'attachment; filename="kanki.apkg"',
                "Cache-Control": "no-store",
            },
        )

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
