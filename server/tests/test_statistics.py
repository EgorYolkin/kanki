import json
import sqlite3
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from uuid import uuid4
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from kanki_server.app import create_app
from kanki_server.statistics import MAX_EVENTS_BYTES, calculate_statistics


ADMIN = {"Authorization": "Bearer synthetic-admin"}
STATS = "/v1/statistics"
EVENTS = "/v1/statistics/events"
CARD = "6D6857DB-1E62-4B8C-9124-20B49B3AABD4"
STAMP = "2024-03-10T08:00:00Z"


def event(kind="visit", **fields):
    return {"id": str(uuid4()), "kind": kind, "timestamp": STAMP, **fields}


def app(path: Path):
    return create_app(database_path=path, admin_token="synthetic-admin")


@pytest.fixture
def client(tmp_path):
    with TestClient(app(tmp_path / "statistics.sqlite3")) as client:
        yield client


def test_both_routes_reject_missing_invalid_and_revoked_tokens(client):
    device = client.post("/v1/tokens", headers=ADMIN, json={"label": "synthetic"}).json()
    assert client.delete(f"/v1/tokens/{device['id']}", headers=ADMIN).status_code == 204
    for headers in ({}, {"Authorization": "Bearer bad"}, {"Authorization": f"Bearer {device['token']}"}):
        assert client.get(STATS, headers=headers).status_code == 401
        assert client.post(EVENTS, headers=headers, json={"events": [event()]}).status_code == 401


@pytest.mark.parametrize("zone", ["Mars/Test", "../UTC", "/etc/localtime", "", "a" * 129])
def test_invalid_reporting_zone(client, zone):
    assert client.get(STATS, params={"timezone": zone}, headers=ADMIN).status_code == 422


def test_empty_collection_returns_contiguous_zero_days(client):
    result = client.get(STATS, params={"timezone": "Asia/Tokyo"}, headers=ADMIN)
    assert result.status_code == 200
    data = result.json()
    assert data["totalReviews"] == data["streakDays"] == 0
    assert data["topics"] == []
    assert data["ratings"] == [0, 0, 0, 0]
    days = data["days"]
    assert len(days) == 365
    start = date.fromisoformat(days[0]["date"])
    assert days == [{"date": (start + timedelta(days=i)).isoformat(), "visits": 0, "reviews": 0}
                    for i in range(365)]


def test_existing_snapshot_and_idempotent_shared_events_survive_restart(tmp_path):
    path = tmp_path / "kanki.sqlite3"
    snapshot = {
        "cards": [{"id": CARD, "deck": "  Science::Demo  ", "isArchived": True}],
        "reviews": [{"cardID": CARD.lower(), "rating": 2, "reviewedAt": STAMP}],
    }
    # A database from before the statistics table existed, with a real revision.
    with sqlite3.connect(path) as connection:
        connection.execute("CREATE TABLE snapshots (id INTEGER PRIMARY KEY, revision INTEGER, "
                           "schema_version INTEGER, data TEXT, updated_at TEXT)")
        connection.execute("INSERT INTO snapshots VALUES (1, 7, 1, ?, ?)", (json.dumps(snapshot), STAMP))

    review = event("imported_review", rating=4, topic="Science::Demo")
    with TestClient(app(path)) as first:
        token = first.post("/v1/tokens", headers=ADMIN, json={"label": "synthetic"}).json()["token"]
        device = {"Authorization": f"Bearer {token}"}
        # Two deliveries in one request and a later retry from another device.
        response = first.post(EVENTS, headers=device, json={"events": [review, review]})
        assert response.status_code == 204 and not response.content

    with TestClient(app(path)) as second:
        different_payload = {**review, "id": review["id"].upper(), "rating": 1, "topic": "Changed"}
        assert second.post(EVENTS, headers=ADMIN, json={"events": [different_payload]}).status_code == 204
        result = second.get(STATS, headers=device).json()
        assert result["totalReviews"] == 2
        assert result["ratings"] == [0, 1, 0, 1]
        assert result["topics"] == [{"name": "Science::Demo", "count": 2}]
        fetched = second.get("/v1/snapshot", headers=ADMIN).json()
        assert fetched["revision"] == 7 and fetched["data"] == snapshot
        assert second.put("/v1/snapshot", headers=ADMIN,
                          json={"base_revision": 7, "data": {"reviews": []}}).status_code == 200
        result = second.get(STATS, headers=ADMIN).json()
        assert result["totalReviews"] == 1 and result["ratings"] == [0, 0, 0, 1]


@pytest.mark.parametrize("bad", [
    event(id="not-a-uuid"), event("unknown"), event(rating=3), event(topic="Demo"),
    event(timestamp="2024-01-01"), event(timestamp="2024-01-01T00:00:00"), event(timestamp=100),
    event(timestamp="0001-01-01T00:00:00+23:00"), event(surprise=True), event("imported_review"),
    event("imported_review", rating=0), event("imported_review", rating=5),
    event("imported_review", rating=True), event("imported_review", rating="1"),
    event("imported_review", rating=2, topic="a" * 257),
])
def test_invalid_batch_is_atomic(client, bad):
    response = client.post(EVENTS, headers=ADMIN, json={"events": [event("imported_review", rating=3), bad]})
    assert response.status_code == 422
    assert client.get(STATS, headers=ADMIN).json()["totalReviews"] == 0


def test_body_limits_and_malformed_json(client):
    for payload in ({"events": []}, {"events": [event()] * 101}, {"events": [event()], "extra": 1}):
        assert client.post(EVENTS, headers=ADMIN, json=payload).status_code == 422
    headers = {**ADMIN, "Content-Type": "application/json"}
    body = iter([b" " * MAX_EVENTS_BYTES, b"!"])
    assert client.post(EVENTS, headers=headers, content=body).status_code == 413
    for body in (b"{", b'{"events": [], "events": []}'):
        assert client.post(EVENTS, headers=headers, content=body).status_code == 422
    assert client.post(EVENTS, headers=ADMIN, content="{}").status_code == 415


def test_legacy_garbage_does_not_hide_valid_reviews(client):
    valid = {"cardID": CARD, "reviewedAt": STAMP, "rating": 3}
    rows = [None, 1, [], {}, {**valid, "reviewedAt": {}}, {**valid, "cardID": {}},
            {**valid, "reviewedAt": "bad"}, {**valid, "rating": True}, {**valid, "rating": 5}, valid]
    for revision, snapshot in enumerate((
        {"cards": {}, "reviews": True},
        {"cards": [None, {"id": [], "deck": []}, {"id": CARD, "deck": {}}], "reviews": rows},
        {"reviews": [valid]},
    )):
        response = client.put("/v1/snapshot", headers=ADMIN, json={"base_revision": revision, "data": snapshot})
        assert response.status_code == 200
        result = client.get(STATS, headers=ADMIN).json()
        assert result["ratings"] == [0, 0, int(revision != 0), 0]
        assert result["topics"] == ([{"name": "Без категории", "count": 1}] if revision else [])


def test_dst_calendar_and_streak_use_local_dates_across_both_sources():
    zone = ZoneInfo("America/Los_Angeles")
    today = date(2024, 3, 11)
    # Midnight after the spring transition is 07:00Z rather than 08:00Z.
    events = [("2024-03-11T06:59:59.999Z", 3, None), ("2024-03-11T07:00:00Z", None, None),
              ("2024-03-12T07:00:00Z", 1, "Future")]
    snapshot = {"reviews": [{"reviewedAt": "2024-03-10T07:59:59Z", "rating": 2, "cardID": CARD}]}
    result = calculate_statistics(snapshot, events, zone, today)
    assert result.streakDays == 2  # Today is a visit, but yesterday had a review.
    assert result.ratings == [0, 1, 1, 0]
    assert [(d.date.isoformat(), d.reviews, d.visits) for d in result.days[-3:]] == [
        ("2024-03-09", 1, 0), ("2024-03-10", 1, 0), ("2024-03-11", 0, 1),
    ]
    utc = calculate_statistics(snapshot, events, ZoneInfo("UTC"), today)
    assert utc.days[-1].reviews == 1
    assert calculate_statistics(snapshot, events[:2], zone, date(2024, 3, 12)).streakDays == 0


def test_retries_do_not_multiply_visits_but_distinct_ids_do(client):
    now = datetime.now(UTC).isoformat()
    one, two = event(timestamp=now), event(timestamp=now)
    for events in ([one, one, two], [two, one]):
        assert client.post(EVENTS, headers=ADMIN, json={"events": events}).status_code == 204
    result = client.get(STATS, headers=ADMIN).json()
    assert sum(day["visits"] for day in result["days"]) == 2
    assert result["totalReviews"] == result["streakDays"] == 0


def test_streak_and_totals_can_exceed_calendar_window():
    today = date(2024, 3, 1)
    events = [((today - timedelta(days=i)).isoformat() + "T12:00:00Z", 4, "  Demo  ") for i in range(370)]
    result = calculate_statistics({}, events, ZoneInfo("UTC"), today)
    assert result.totalReviews == result.streakDays == 370
    assert len(result.days) == sum(day.reviews for day in result.days) == 365
    assert result.days[-2].date == date(2024, 2, 29)
    assert [(topic.name, topic.count) for topic in result.topics] == [("Demo", 370)]
