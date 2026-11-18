"""
Exercise the delta stream through real HTTP handlers and disposable SQLite files.
"""

import json
import sqlite3
from contextlib import closing
from pathlib import Path
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from starlette.types import Message, Receive, Scope, Send

from kanki_server.app import create_app
from kanki_server.changes import MAX_CHANGES_BYTES

CHANGES = "/v1/changes"
SNAPSHOT = "/v1/snapshot"
ADMIN_TOKEN = "synthetic-administrator"
ADMIN = {"Authorization": f"Bearer {ADMIN_TOKEN}"}
INT64_MIN = -(1 << 63)
INT64_MAX = (1 << 63) - 1


def event_id(number: int) -> str:
    return f"a0000000-0000-4000-8000-{number:012x}"


def review(number: int) -> dict:
    return {
        "kind": "review", "id": event_id(number), "guid": "imported-peer-card",
        "ord": 0, "reviewedAt": 1_800_000_000.25, "rating": 3,
    }


def progress(number: int) -> dict:
    raw_reviews = [
        {
            "id": INT64_MAX - index, "ease": 3, "ivl": -600, "lastIvl": -60,
            "factor": 2500, "time": 42, "type": 0,
        }
        for index in range(100)
    ]
    return {
        "kind": "progress", "id": event_id(number), "guid": "imported-peer-card",
        "ord": 0, "progress": {"due": INT64_MIN, "ivl": 12, "queue": -1, "reviews": raw_reviews},
    }


@pytest.fixture
def client(tmp_path: Path):
    with TestClient(create_app(
        database_path=tmp_path / "server.sqlite3",
        admin_token=ADMIN_TOKEN,
        max_snapshot_bytes=1024,
    )) as test_client:
        yield test_client


def get_page(client: TestClient, since: int = 0, headers: dict[str, str] = ADMIN) -> dict:
    response = client.get(CHANGES, params={"since": since}, headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def test_lost_response_can_be_retried_after_restart(tmp_path: Path) -> None:
    database_path = tmp_path / "server.sqlite3"
    app = create_app(database_path=database_path, admin_token=ADMIN_TOKEN)

    async def drop_receipt(scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] != "POST" or scope["path"] != CHANGES:
            await app(scope, receive, send)
            return

        async def drop_response_start(message: Message) -> None:
            if message["type"] == "http.response.start" and message["status"] == 200:
                raise ConnectionError("synthetic lost receipt")
            await send(message)

        await app(scope, receive, drop_response_start)

    events = [review(2), progress(1)]
    with TestClient(drop_receipt) as first:
        initial = get_page(first)
        stream = initial["stream"]
        assert str(UUID(stream)) == stream
        assert initial == {"stream": stream, "changes": [], "more": False}
        with pytest.raises(ConnectionError, match="synthetic lost receipt"):
            first.post(CHANGES, headers=ADMIN, json={"stream": stream, "events": events})

    with TestClient(create_app(database_path=database_path, admin_token=ADMIN_TOKEN)) as second:
        expected = {
            "stream": stream,
            "changes": [{"seq": index, "event": event} for index, event in enumerate(events, 1)],
            "more": False,
        }
        assert get_page(second) == expected
        reordered = [dict(reversed(list(event.items()))) for event in events]
        receipt = second.post(CHANGES, headers=ADMIN, json={"events": reordered, "stream": stream})
        assert receipt.status_code == 200, receipt.text
        assert receipt.json() == {"accepted": [event_id(2), event_id(1)]}
        assert get_page(second) == expected
        assert get_page(second, since=2) == {"stream": stream, "changes": [], "more": False}
        assert second.get("/v1/export.apkg", headers=ADMIN).status_code == 404


def test_collision_and_wrong_stream_roll_back_entire_batch(client: TestClient) -> None:
    stream = get_page(client)["stream"]
    stored, fresh = review(1), review(2)
    first = client.post(CHANGES, headers=ADMIN, json={"stream": stream, "events": [stored]})
    assert first.status_code == 200
    initial = get_page(client)

    wrong_stream = client.post(CHANGES, headers=ADMIN, json={
        "stream": event_id(10), "events": [fresh],
    })
    assert wrong_stream.status_code == 409
    assert wrong_stream.json() == {"detail": {"code": "stream_mismatch"}}

    for collision in ({**stored, "rating": 4}, progress(1)):
        conflict = client.post(CHANGES, headers=ADMIN, json={
            "stream": stream, "events": [fresh, collision],
        })
        assert conflict.status_code == 409
        assert conflict.json() == {"detail": {"code": "event_id_conflict"}}
        assert get_page(client) == initial

    mixed = client.post(CHANGES, headers=ADMIN, json={"stream": stream, "events": [fresh, stored]})
    assert mixed.status_code == 200
    assert mixed.json() == {"accepted": [fresh["id"], stored["id"]]}
    assert get_page(client, since=1)["changes"] == [{"seq": 2, "event": fresh}]


def test_restored_database_rejects_future_cursor_even_with_same_stream(tmp_path: Path) -> None:
    live_path = tmp_path / "live.sqlite3"
    restored_path = tmp_path / "restored.sqlite3"
    with TestClient(create_app(database_path=live_path, admin_token=ADMIN_TOKEN)) as live:
        stream = get_page(live)["stream"]
        first = live.post(CHANGES, headers=ADMIN, json={"stream": stream, "events": [review(1)]})
        assert first.status_code == 200
        with closing(sqlite3.connect(live_path)) as source:
            with closing(sqlite3.connect(restored_path)) as backup:
                source.backup(backup)
        second = live.post(CHANGES, headers=ADMIN, json={"stream": stream, "events": [review(2)]})
        assert second.status_code == 200
        cursor = get_page(live)["changes"][-1]["seq"]

    with TestClient(create_app(database_path=restored_path, admin_token=ADMIN_TOKEN)) as restored:
        future = restored.get(CHANGES, headers=ADMIN, params={"since": cursor})
        assert future.status_code == 409
        assert future.json() == {"detail": {"code": "future_cursor"}}
        assert get_page(restored) == {
            "stream": stream, "changes": [{"seq": 1, "event": review(1)}], "more": False,
        }

    with TestClient(create_app(
        database_path=tmp_path / "new.sqlite3", admin_token=ADMIN_TOKEN
    )) as fresh:
        assert get_page(fresh)["stream"] != stream


def test_device_bearer_auth_and_snapshot_are_unchanged(client: TestClient) -> None:
    assert client.get(CHANGES, params={"since": 0}).status_code == 401
    assert client.post(CHANGES, json={}).status_code == 401
    invalid = {"Authorization": "Bearer wrong"}
    assert client.get(CHANGES, headers=invalid, params={"since": 0}).status_code == 401
    token = client.post("/v1/tokens", headers=ADMIN, json={"label": "synthetic-device"})
    assert token.status_code == 201
    device = {"Authorization": f"Bearer {token.json()['token']}"}
    initial = get_page(client, headers=device)
    snapshot = client.put(SNAPSHOT, headers=device, json={
        "schema_version": 1, "base_revision": 0, "data": {"cards": ["synthetic"]},
    })
    assert snapshot.status_code == 200
    assert get_page(client, headers=device) == initial
    response = client.post(CHANGES, headers=device, json={
        "stream": initial["stream"], "events": [review(1)],
    })
    assert response.status_code == 200
    assert get_page(client, headers=device)["changes"] == [{"seq": 1, "event": review(1)}]
    current = client.get(SNAPSHOT, headers=device)
    assert current.status_code == 200
    assert current.json() == snapshot.json()
    assert current.headers["ETag"] == '"1"'
    assert client.get(SNAPSHOT, headers={**device, "If-None-Match": '"1"'}).status_code == 304


@pytest.mark.parametrize("bad_event", [
    pytest.param({**review(2), "id": event_id(2).upper()}, id="uppercase-id"),
    pytest.param({**review(2), "guid": ""}, id="empty-key"),
    pytest.param({**review(2), "ord": False}, id="boolean-ord"),
    pytest.param({**review(2), "ord": 1}, id="nonzero-ord"),
    pytest.param({**review(2), "rating": "3"}, id="string-rating"),
    pytest.param({**review(2), "rating": 5}, id="out-of-range-rating"),
    pytest.param({**review(2), "reviewedAt": float("inf")}, id="nonfinite-date"),
    pytest.param({**review(2), "kind": "publication"}, id="client-publication"),
    pytest.param({**review(2), "extra": 1}, id="unknown-field"),
    pytest.param({**progress(2), "progress": {
        "due": INT64_MAX + 1, "ivl": 0, "queue": 0, "reviews": [],
    }}, id="int64-overflow"),
    pytest.param({**progress(2), "progress": {
        "due": 0, "ivl": 0, "queue": 0, "reviews": [progress(2)["progress"]["reviews"][0]] * 101,
    }}, id="too-many-raw-reviews"),
    pytest.param({**progress(2), "progress": {
        "due": 0, "ivl": 0, "queue": 0, "reviews": [progress(2)["progress"]["reviews"][0]] * 2,
    }}, id="duplicate-raw-review-id"),
])
def test_invalid_observation_writes_nothing(client: TestClient, bad_event: dict) -> None:
    stream = get_page(client)["stream"]
    response = client.post(
        CHANGES, headers={**ADMIN, "Content-Type": "application/json"},
        content=json.dumps({"stream": stream, "events": [review(1), bad_event]}),
    )
    assert response.status_code == 422
    assert response.json() == {"detail": {"code": "invalid_changes"}}
    assert get_page(client)["changes"] == []


def test_request_limits_and_cursor_validation(client: TestClient) -> None:
    stream = get_page(client)["stream"]
    assert client.get(CHANGES, headers=ADMIN).status_code == 422
    for bad_cursor in (-1, "0.5", INT64_MAX + 1):
        assert client.get(CHANGES, headers=ADMIN, params={"since": bad_cursor}).status_code == 422
    assert client.post(CHANGES, headers=ADMIN, content="not JSON").status_code == 415
    assert client.post(CHANGES, headers=ADMIN, json={
        "stream": event_id(1).upper(), "events": [],
    }).status_code == 422
    assert client.post(CHANGES, headers=ADMIN, json={
        "stream": stream, "events": [review(1), progress(1)],
    }).status_code == 422

    headers = {**ADMIN, "Content-Type": "application/json"}
    duplicate_key = json.dumps({"stream": stream, "events": [review(1)]})[:-1] + ',"events":[]}'
    assert client.post(CHANGES, headers=headers, content=duplicate_key).status_code == 422
    request = client.build_request(
        "POST", CHANGES, headers=headers, content=iter([b" " * (MAX_CHANGES_BYTES // 2)] * 3),
    )
    assert "content-length" not in request.headers
    too_large = client.send(request)
    assert too_large.status_code == 413
    assert too_large.json() == {"detail": {"code": "changes_too_large"}}

    events = [review(number) for number in range(51)]
    excessive = client.post(CHANGES, headers=ADMIN, json={"stream": stream, "events": events})
    assert excessive.status_code == 422
    assert get_page(client)["changes"] == []
    accepted = client.post(CHANGES, headers=ADMIN, json={"stream": stream, "events": events[:50]})
    assert accepted.status_code == 200
    assert accepted.json() == {"accepted": [event["id"] for event in events[:50]]}
    page = get_page(client)
    assert page["more"] is False
    assert len(page["changes"]) == 50
