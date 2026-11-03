from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from kanki_server.app import create_app

ADMIN_TOKEN = "admin-secret"


def auth(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def database_path(tmp_path: Path) -> Path:
    return tmp_path / "kanki.sqlite3"


@pytest.fixture
def client(database_path: Path):
    app = create_app(
        database_path=database_path,
        admin_token=ADMIN_TOKEN,
        max_snapshot_bytes=1024,
    )
    with TestClient(app) as test_client:
        yield test_client


def create_device_token(client: TestClient, label: str = "device") -> str:
    response = client.post("/v1/tokens", json={"label": label}, headers=auth(ADMIN_TOKEN))
    assert response.status_code == 201
    return response.json()["token"]


def test_health_needs_no_token(client: TestClient) -> None:
    response = client.get("/v1/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_identity_requires_token(client: TestClient) -> None:
    assert client.get("/v1/me").status_code == 401
    assert client.get("/v1/me", headers=auth("wrong")).status_code == 401

    response = client.get("/v1/me", headers=auth(ADMIN_TOKEN))

    assert response.status_code == 200
    assert response.json() == {"label": "admin", "role": "admin"}


def test_snapshot_starts_empty(client: TestClient) -> None:
    token = create_device_token(client)

    response = client.get("/v1/snapshot", headers=auth(token))

    assert response.status_code == 200
    assert response.json() == {
        "revision": 0,
        "schema_version": 1,
        "data": None,
        "updated_at": None,
    }


def test_snapshot_round_trip_and_conflict(client: TestClient) -> None:
    token = create_device_token(client)
    first = {"cards": [{"id": "a"}], "reviews": [], "schedules": {}}

    response = client.put(
        "/v1/snapshot",
        json={"schema_version": 1, "base_revision": 0, "data": first},
        headers=auth(token),
    )
    assert response.status_code == 200
    assert response.json()["revision"] == 1

    fetched = client.get("/v1/snapshot", headers=auth(token)).json()
    assert fetched["revision"] == 1
    assert fetched["data"] == first

    stale = client.put(
        "/v1/snapshot",
        json={"schema_version": 1, "base_revision": 0, "data": {"cards": []}},
        headers=auth(token),
    )
    assert stale.status_code == 409
    assert stale.json()["detail"] == {
        "code": "revision_conflict",
        "current_revision": 1,
    }

    second = client.put(
        "/v1/snapshot",
        json={"schema_version": 1, "base_revision": 1, "data": {"cards": []}},
        headers=auth(token),
    )
    assert second.status_code == 200
    assert second.json()["revision"] == 2


def test_snapshot_etag_conditional_get(client: TestClient) -> None:
    token = create_device_token(client)
    empty = client.get("/v1/snapshot", headers=auth(token))
    assert empty.status_code == 200
    assert empty.headers["ETag"] == '"0"'

    data = {"cards": [{"id": "a"}], "reviews": [], "schedules": {}}
    stored = client.put(
        "/v1/snapshot",
        json={"schema_version": 1, "base_revision": 0, "data": data},
        headers=auth(token),
    )
    revision = stored.json()["revision"]

    current = client.get("/v1/snapshot", headers=auth(token))
    assert current.status_code == 200
    etag = current.headers["ETag"]
    assert etag == f'"{revision}"'

    not_modified = client.get(
        "/v1/snapshot",
        headers={**auth(token), "If-None-Match": etag},
    )
    assert not_modified.status_code == 304
    assert not_modified.content == b""
    assert not_modified.headers["ETag"] == etag

    stale = client.get(
        "/v1/snapshot",
        headers={**auth(token), "If-None-Match": f'"{revision - 1}"'},
    )
    assert stale.status_code == 200
    assert stale.json()["revision"] == revision
    assert stale.headers["ETag"] == etag


def test_snapshot_etag_accepts_weak_and_wildcard(client: TestClient) -> None:
    token = create_device_token(client)
    current = client.get("/v1/snapshot", headers=auth(token))
    etag = current.headers["ETag"]

    weak = client.get(
        "/v1/snapshot",
        headers={**auth(token), "If-None-Match": f"W/{etag}"},
    )
    assert weak.status_code == 304

    wildcard = client.get(
        "/v1/snapshot",
        headers={**auth(token), "If-None-Match": "*"},
    )
    assert wildcard.status_code == 304


def test_snapshot_requires_auth(client: TestClient) -> None:
    assert client.get("/v1/snapshot").status_code == 401
    assert (
        client.put(
            "/v1/snapshot",
            json={"schema_version": 1, "base_revision": 0, "data": {}},
        ).status_code
        == 401
    )


def test_rejects_unknown_schema_and_oversized_snapshot(client: TestClient) -> None:
    token = create_device_token(client)

    wrong_schema = client.put(
        "/v1/snapshot",
        json={"schema_version": 2, "base_revision": 0, "data": {}},
        headers=auth(token),
    )
    assert wrong_schema.status_code == 422

    oversized = client.put(
        "/v1/snapshot",
        json={"schema_version": 1, "base_revision": 0, "data": {"blob": "x" * 2000}},
        headers=auth(token),
    )
    assert oversized.status_code == 413
    assert oversized.json()["detail"] == {"code": "snapshot_too_large"}


def test_device_token_cannot_manage_tokens(client: TestClient) -> None:
    token = create_device_token(client)

    assert (
        client.post("/v1/tokens", json={"label": "other"}, headers=auth(token)).status_code
        == 403
    )
    assert client.get("/v1/tokens", headers=auth(token)).status_code == 403


def test_revoked_token_is_rejected(client: TestClient) -> None:
    created = client.post(
        "/v1/tokens",
        json={"label": "agent"},
        headers=auth(ADMIN_TOKEN),
    ).json()

    assert (
        client.get("/v1/me", headers=auth(created["token"])).status_code == 200
    )
    assert (
        client.delete(f"/v1/tokens/{created['id']}", headers=auth(ADMIN_TOKEN)).status_code
        == 204
    )
    assert client.get("/v1/me", headers=auth(created["token"])).status_code == 401
    assert (
        client.delete(f"/v1/tokens/{created['id']}", headers=auth(ADMIN_TOKEN)).status_code
        == 404
    )


def test_token_is_stored_as_hash(database_path: Path, client: TestClient) -> None:
    token = create_device_token(client)

    with sqlite3.connect(database_path) as connection:
        stored = connection.execute("SELECT token_hash FROM tokens").fetchone()[0]

    assert stored != token
    assert len(stored) == 64


def test_snapshot_survives_restart(database_path: Path) -> None:
    first_app = create_app(database_path=database_path, admin_token=ADMIN_TOKEN)
    with TestClient(first_app) as first_client:
        token = create_device_token(first_client)
        first_client.put(
            "/v1/snapshot",
            json={"schema_version": 1, "base_revision": 0, "data": {"cards": []}},
            headers=auth(token),
        )

    second_app = create_app(database_path=database_path, admin_token=ADMIN_TOKEN)
    with TestClient(second_app) as second_client:
        response = second_client.get("/v1/snapshot", headers=auth(token))

    assert response.status_code == 200
    assert response.json()["revision"] == 1


def test_database_uses_wal(database_path: Path) -> None:
    app = create_app(database_path=database_path, admin_token=ADMIN_TOKEN)
    with TestClient(app):
        pass

    with sqlite3.connect(database_path) as connection:
        mode = connection.execute("PRAGMA journal_mode").fetchone()[0]

    assert mode.lower() == "wal"


def test_admin_disabled_without_token(database_path: Path) -> None:
    app = create_app(database_path=database_path, admin_token=None)

    with TestClient(app) as client:
        assert client.get("/v1/health").status_code == 200
        response = client.post(
            "/v1/tokens",
            json={"label": "device"},
            headers=auth("anything"),
        )

    assert response.status_code == 401
