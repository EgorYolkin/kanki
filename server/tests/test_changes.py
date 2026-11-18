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
UID = "n-018f3a2b-7c41-7000-8000-000000000001"
OTHER_UID = "n-018f3a2b-7c41-7000-8000-000000000002"


def event_id(number: int) -> str:
    return f"a0000000-0000-4000-8000-{number:012x}"


def review(number: int) -> dict:
    return {
        "kind": "review", "id": event_id(number), "guid": "imported-peer-card",
        "uid": UID,
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
        "uid": UID,
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


def checkpoint(change: dict) -> dict:
    return {"since": change["seq"], "anchor": change["anchor"]}


def assert_changes(page: dict, expected: list[tuple[int, dict]]) -> None:
    assert [(change["seq"], change["event"]) for change in page["changes"]] == expected
    anchors = [UUID(change["anchor"]) for change in page["changes"]]
    assert len(set(anchors)) == len(anchors)
    assert all(anchor.version == 4 for anchor in anchors)


def get_page(
    client: TestClient, *, cursor: dict | None = None, headers: dict[str, str] = ADMIN
) -> dict:
    response = client.get(CHANGES, params=cursor or {"since": 0}, headers=headers)
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
            first.post(CHANGES, headers=ADMIN, json={"stream": stream, "since": 0, "events": events})

    with TestClient(create_app(database_path=database_path, admin_token=ADMIN_TOKEN)) as second:
        page = get_page(second)
        assert page["stream"] == stream
        assert page["more"] is False
        assert_changes(page, list(enumerate(events, 1)))
        reordered = [dict(reversed(list(event.items()))) for event in events]
        receipt = second.post(CHANGES, headers=ADMIN, json={
            "events": reordered, "stream": stream, "since": 0,
        })
        assert receipt.status_code == 200, receipt.text
        assert receipt.json() == {"accepted": [event_id(2), event_id(1)]}
        assert get_page(second) == page
        assert get_page(second, cursor=checkpoint(page["changes"][-1])) == {
            "stream": stream, "changes": [], "more": False,
        }
        assert second.get("/v1/export.apkg", headers=ADMIN).status_code == 404


def test_collision_and_wrong_stream_roll_back_entire_batch(client: TestClient) -> None:
    stream = get_page(client)["stream"]
    stored, fresh = review(1), review(2)
    first = client.post(CHANGES, headers=ADMIN, json={
        "stream": stream, "since": 0, "events": [stored],
    })
    assert first.status_code == 200
    initial = get_page(client)

    wrong_stream = client.post(CHANGES, headers=ADMIN, json={
        "stream": event_id(10), "since": 0, "events": [fresh],
    })
    assert wrong_stream.status_code == 409
    assert wrong_stream.json() == {"detail": {"code": "stream_mismatch"}}

    unchecked = client.post(CHANGES, headers=ADMIN, json={
        "stream": stream, "since": 1, "events": [fresh],
    })
    assert unchecked.status_code == 409
    assert unchecked.json() == {"detail": {"code": "anchor_mismatch"}}
    assert get_page(client) == initial

    cursor = checkpoint(initial["changes"][0])
    for collision in ({**stored, "rating": 4}, {**stored, "uid": OTHER_UID}, progress(1)):
        conflict = client.post(CHANGES, headers=ADMIN, json={
            "stream": stream, **cursor, "events": [fresh, collision],
        })
        assert conflict.status_code == 409
        assert conflict.json() == {"detail": {"code": "event_id_conflict"}}
        assert get_page(client) == initial

    mixed = client.post(CHANGES, headers=ADMIN, json={
        "stream": stream, **cursor, "events": [fresh, stored],
    })
    assert mixed.status_code == 200
    assert mixed.json() == {"accepted": [fresh["id"], stored["id"]]}
    assert_changes(get_page(client, cursor=cursor), [(2, fresh)])


def test_restored_database_rejects_reused_cursor_even_with_same_stream(tmp_path: Path) -> None:
    live_path = tmp_path / "live.sqlite3"
    restored_path = tmp_path / "restored.sqlite3"
    with TestClient(create_app(database_path=live_path, admin_token=ADMIN_TOKEN)) as live:
        stream = get_page(live)["stream"]
        first = live.post(CHANGES, headers=ADMIN, json={
            "stream": stream, "since": 0, "events": [review(1)],
        })
        assert first.status_code == 200
        shared = checkpoint(get_page(live)["changes"][0])
        with closing(sqlite3.connect(live_path)) as source:
            with closing(sqlite3.connect(restored_path)) as backup:
                source.backup(backup)

        second = live.post(CHANGES, headers=ADMIN, json={
            "stream": stream, **shared, "events": [review(2)],
        })
        assert second.status_code == 200
        abandoned = checkpoint(get_page(live, cursor=shared)["changes"][0])

    with TestClient(create_app(database_path=restored_path, admin_token=ADMIN_TOKEN)) as restored:
        assert checkpoint(get_page(restored)["changes"][0]) == shared

        def assert_stale(code: str) -> None:
            before = get_page(restored)
            old_get = restored.get(CHANGES, headers=ADMIN, params=abandoned)
            old_post = restored.post(CHANGES, headers=ADMIN, json={
                "stream": stream, **abandoned, "events": [review(3)],
            })
            for response in (old_get, old_post):
                assert response.status_code == 409
                assert response.json() == {"detail": {"code": code}}
            assert get_page(restored) == before

        assert_stale("future_cursor")
        repopulated = restored.post(CHANGES, headers=ADMIN, json={
            "stream": stream, **shared, "events": [review(2)],
        })
        assert repopulated.status_code == 200
        tail = get_page(restored, cursor=shared)
        assert tail["stream"] == stream
        assert_changes(tail, [(abandoned["since"], review(2))])
        replacement = checkpoint(tail["changes"][0])
        assert replacement["anchor"] != abandoned["anchor"]
        assert_stale("anchor_mismatch")

        assert get_page(restored, cursor=replacement)["changes"] == []
        valid = restored.post(CHANGES, headers=ADMIN, json={
            "stream": stream, **replacement, "events": [review(3)],
        })
        assert valid.status_code == 200
        assert_changes(get_page(restored, cursor=replacement), [(3, review(3))])

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
        "stream": initial["stream"], "since": 0, "events": [review(1)],
    })
    assert response.status_code == 200
    assert_changes(get_page(client, headers=device), [(1, review(1))])
    current = client.get(SNAPSHOT, headers=device)
    assert current.status_code == 200
    assert current.json() == snapshot.json()
    assert current.headers["ETag"] == '"1"'
    assert client.get(SNAPSHOT, headers={**device, "If-None-Match": '"1"'}).status_code == 304


@pytest.mark.parametrize("bad_event", [
    pytest.param({**review(2), "id": event_id(2).upper()}, id="uppercase-id"),
    pytest.param({**review(2), "guid": ""}, id="empty-key"),
    pytest.param({k: v for k, v in review(2).items() if k != "uid"}, id="review-missing-uid"),
    pytest.param({k: v for k, v in progress(2).items() if k != "uid"}, id="progress-missing-uid"),
    pytest.param({**review(2), "uid": UID.upper()}, id="uppercase-uid"),
    pytest.param({**progress(2), "uid": event_id(2)}, id="non-publication-uid"),
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
        content=json.dumps({"stream": stream, "since": 0, "events": [review(1), bad_event]}),
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
        "stream": event_id(1).upper(), "since": 0, "events": [],
    }).status_code == 422
    assert client.post(CHANGES, headers=ADMIN, json={
        "stream": stream, "since": 0, "events": [review(1), progress(1)],
    }).status_code == 422
    for bad_since in (None, -1, True, "0", INT64_MAX + 1):
        payload = {"stream": stream, "events": []}
        if bad_since is not None:
            payload["since"] = bad_since
        assert client.post(CHANGES, headers=ADMIN, json=payload).status_code == 422

    malformed = {"since": 0, "anchor": "not-a-uuid"}
    assert client.get(CHANGES, headers=ADMIN, params=malformed).status_code == 422
    assert client.post(CHANGES, headers=ADMIN, json={
        "stream": stream, **malformed, "events": [],
    }).status_code == 422

    unexpected = {"since": 0, "anchor": event_id(1)}
    for response in (
        client.get(CHANGES, headers=ADMIN, params=unexpected),
        client.post(CHANGES, headers=ADMIN, json={
            "stream": stream, **unexpected, "events": [review(1)],
        }),
    ):
        assert response.status_code == 409
        assert response.json() == {"detail": {"code": "anchor_mismatch"}}

    headers = {**ADMIN, "Content-Type": "application/json"}
    duplicate_key = json.dumps({
        "stream": stream, "since": 0, "events": [review(1)],
    })[:-1] + ',"events":[]}'
    assert client.post(CHANGES, headers=headers, content=duplicate_key).status_code == 422
    request = client.build_request(
        "POST", CHANGES, headers=headers, content=iter([b" " * (MAX_CHANGES_BYTES // 2)] * 3),
    )
    assert "content-length" not in request.headers
    too_large = client.send(request)
    assert too_large.status_code == 413
    assert too_large.json() == {"detail": {"code": "changes_too_large"}}

    events = [review(number) for number in range(51)]
    excessive = client.post(CHANGES, headers=ADMIN, json={
        "stream": stream, "since": 0, "events": events,
    })
    assert excessive.status_code == 422
    assert get_page(client)["changes"] == []
    accepted = client.post(CHANGES, headers=ADMIN, json={
        "stream": stream, "since": 0, "events": events[:50],
    })
    assert accepted.status_code == 200
    assert accepted.json() == {"accepted": [event["id"] for event in events[:50]]}
    page = get_page(client)
    assert page["more"] is False
    assert len(page["changes"]) == 50
