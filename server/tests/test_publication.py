"""Publication through the HTTP interface and a real, disposable Anki collection."""

import io
import json
import sqlite3
import zipfile
from contextlib import closing
from datetime import datetime
from html.parser import HTMLParser
from pathlib import Path
from uuid import UUID

import genanki
import pytest
from anki.collection import Collection
from anki.importing import ImportAnkiPackageOptions, ImportAnkiPackageRequest
from anki.scheduler.v3 import CardAnswer
from fastapi.testclient import TestClient

from kanki_server import db
from kanki_server.app import create_app
from kanki_server.publication import parse_documents

ADMIN = {"Authorization": "Bearer synthetic-administrator"}
PUBLISH = "/v1/publish"
EXPORT = "/v1/export.apkg"
CHANGES = "/v1/changes"
UID_A = "n-018f3a2b-7c41-7000-8000-000000000001"
UID_B = "n-018f3a2b-7c41-7000-8000-000000000002"
MEDIA_MARKER = "[sound:synthetic.mp3]"
LITERAL_HTML = '<script>synthetic</script> <img src="synthetic.png">'


def document(uid: str, *, body: str = "Начальный **текст**.", extra: dict | None = None) -> str:
    fields = {
        "uid": uid,
        "kind": "fact",
        "schema_version": 1,
        "title": "Синтетическая заметка",
        "question": "Вопрос?",
        "answer": "Ответ.",
        "sources": [],
        "relations": [],
    }
    fields.update(extra or {})
    # JSON flow mappings are valid YAML, including quoted multiline values.
    frontmatter = json.dumps(fields, ensure_ascii=False).replace("\u2028", r"\u2028")
    return f"---\n{frontmatter}\n---\n{body}\n"


def app_for(path: Path) -> TestClient:
    return TestClient(create_app(database_path=path, admin_token="synthetic-administrator"))


def publish(client: TestClient, headers: dict[str, str], *documents: str) -> list[dict]:
    response = client.post(PUBLISH, headers=headers, json={"documents": documents})
    assert response.status_code == 200, response.text
    return response.json()["notes"]


def import_package(collection: Collection, path: Path, package: bytes):
    path.write_bytes(package)
    return collection.import_anki_package(ImportAnkiPackageRequest(
        package_path=str(path),
        options=ImportAnkiPackageOptions(update_notes=0, update_notetypes=0, with_scheduling=True),
    )).log


def exported_rows(package: bytes) -> list[tuple]:
    with zipfile.ZipFile(io.BytesIO(package)) as archive:
        assert set(archive.namelist()) == {"collection.anki2", "media"}
        assert json.loads(archive.read("media")) == {}
        with closing(sqlite3.connect(":memory:")) as database:
            database.deserialize(archive.read("collection.anki2"))
            assert database.execute("SELECT COUNT(*) FROM revlog").fetchone() == (0,)
            assert database.execute("SELECT DISTINCT ord, type, queue FROM cards").fetchall() == [(0, 0, 0)]
            return database.execute("SELECT guid, mid, mod, flds FROM notes ORDER BY guid").fetchall()


class _CardMarkup(HTMLParser):
    def __init__(self, html: str) -> None:
        super().__init__()
        self.tags = []
        self.hrefs = []
        self.text = []
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        self.tags.append(tag)
        if tag == "a":
            self.hrefs.append(dict(attrs)["href"])

    def handle_data(self, data):
        self.text.append(data)


def test_publication_survives_restart_and_updates_real_anki(tmp_path: Path, monkeypatch) -> None:
    class FixedClock(datetime):
        @classmethod
        def now(cls, tz=None):
            return cls.fromtimestamp(1_800_000_000, tz)

    monkeypatch.setattr(db, "datetime", FixedClock)
    database_path = tmp_path / "server.sqlite3"
    first_a = document(UID_A, extra={"question": "", "answer": ""})
    first_b = document(UID_B, extra={"relations": [{"t": "requires", "to": UID_A}]})
    with app_for(database_path) as client:
        response = client.post("/v1/tokens", headers=ADMIN, json={"label": "synthetic-agent"})
        assert response.status_code == 201
        headers = {"Authorization": f"Bearer {response.json()['token']}"}
        snapshot = client.put("/v1/snapshot", headers=headers, json={
            "schema_version": 1, "base_revision": 0, "data": {"cards": []},
        })
        assert snapshot.status_code == 200
        initial = publish(client, headers, first_a, first_b)
        assert [row["guid"] for row in initial] == [genanki.guid_for(UID_A), genanki.guid_for(UID_B)]
        assert publish(client, headers, first_a.replace("\n", "\r\n"), first_b) == initial

    with app_for(database_path) as client, closing(Collection(str(tmp_path / "clean.anki2"))) as collection:
        assert not collection.find_notes("")
        assert not collection.find_cards("")
        assert client.get("/v1/snapshot", headers=headers).json() == snapshot.json()
        response = client.get(EXPORT, headers=headers)
        assert response.status_code == 200
        assert response.headers["content-type"] == "application/zip"
        assert response.headers["content-disposition"] == 'attachment; filename="kanki.apkg"'
        assert response.headers["cache-control"] == "no-store"
        package = tmp_path / "synthetic.apkg"
        first = import_package(collection, package, response.content)
        assert len(first.new) == 2
        assert not first.updated
        notes = {note["UID"]: note for note in map(collection.get_note, collection.find_notes(""))}
        assert set(notes) == {UID_A, UID_B}
        assert tuple(notes[UID_A].keys()) == (
            "UID", "Title", "Body", "Question", "Answer", "Relations", "Sources", "SchemaVersion",
        )
        assert notes[UID_A]["SchemaVersion"] == "1"
        assert notes[UID_A]["Question"] == notes[UID_A]["Answer"] == ""
        assert json.loads(notes[UID_B]["Relations"]) == {"t": "requires", "to": UID_A}
        cards = {card.note()["UID"]: card for card in map(collection.get_card, collection.find_cards(""))}
        assert set(cards) == {UID_A, UID_B}
        assert all(card.ord == 0 for card in cards.values())
        assert "Синтетическая заметка" in cards[UID_A].question()
        assert "requires" in cards[UID_B].answer()
        assert collection.db.scalar("SELECT COUNT(*) FROM revlog") == 0

        card = cards[UID_A]
        collection.decks.select(card.did)
        states = {queued.card.id: queued.states for queued in collection.sched.get_queued_cards(fetch_limit=2).cards}
        card.start_timer()
        collection.sched.answer_card(collection.sched.build_answer(
            card=card,
            states=states[card.id],
            rating=CardAnswer.Rating.GOOD,
        ))
        progress_sql = "SELECT id, ord, due, ivl, queue, reps FROM cards ORDER BY id"
        progress = collection.db.all(progress_sql)
        reviews = collection.db.all("SELECT * FROM revlog")
        assert len(reviews) == 1

        relation_note = f"{LITERAL_HTML}\u2028{MEDIA_MARKER}"
        updated_a = document(UID_A, body="", extra={
            "body": f"Обновлённый **текст**. {LITERAL_HTML}",
            "question": f"**Как?** {LITERAL_HTML} {MEDIA_MARKER}",
            "answer": '[Источник](https://example.invalid/doc) '
                      '[не ссылка](file:///synthetic) ![без медиа](https://example.invalid/img)',
            "relations": [
                {"t": "related", "to": UID_B, "note": relation_note},
                {"t": "contrast", "to": UID_B},
            ],
            "sources": [{"ref": "synthetic", "locator": LITERAL_HTML}],
        })
        invalid = client.post(PUBLISH, headers=headers, json={"documents": [
            updated_a, document(UID_B, extra={"schema_version": 2}),
        ]})
        assert invalid.status_code == 422
        unchanged = client.get(EXPORT, headers=headers).content
        assert [row[:3] for row in exported_rows(unchanged)] == sorted(
            (row["guid"], 1936480171, row["mod"]) for row in initial
        )
        repeated = import_package(collection, package, unchanged)
        assert not repeated.new and not repeated.updated and len(repeated.duplicate) == 2

        updated = publish(client, headers, updated_a)[0]
        assert updated["guid"] == initial[0]["guid"]
        assert updated["mod"] == initial[0]["mod"] + 1
        assert publish(client, headers, updated_a, first_b) == [updated, initial[1]]
        response = client.get(EXPORT, headers=headers)
        assert response.status_code == 200
        assert [row[:3] for row in exported_rows(response.content)] == sorted(
            (row["guid"], 1936480171, row["mod"]) for row in (updated, initial[1])
        )
        changed = import_package(collection, package, response.content)
        assert not changed.new and len(changed.updated) == 1 and len(changed.duplicate) == 1
        assert len(collection.find_notes("")) == len(collection.find_cards("")) == 2
        note = collection.get_note(notes[UID_A].id)
        assert note.guid == updated["guid"]
        assert note["Body"].startswith("<p>Обновлённый <strong>текст</strong>.")
        assert [json.loads(line) for line in note["Relations"].splitlines()] == [
            {"t": "related", "to": UID_B, "note": relation_note},
            {"t": "contrast", "to": UID_B},
        ]
        assert json.loads(note["Sources"]) == [{"ref": "synthetic", "locator": LITERAL_HTML}]
        card = collection.get_card(card.id)
        front = _CardMarkup(card.render_output().question_text)
        back = _CardMarkup(card.render_output().answer_text)
        assert "strong" in front.tags and LITERAL_HTML in "".join(front.text)
        assert {"img", "script"}.isdisjoint(front.tags + back.tags)
        assert "file:///synthetic" not in back.hrefs
        assert "https://example.invalid/doc" in back.hrefs
        assert not card.question_av_tags() and not card.answer_av_tags()
        assert collection.db.all(progress_sql) == progress
        assert collection.db.all("SELECT * FROM revlog") == reviews
        duplicate = import_package(collection, package, response.content)
        assert not duplicate.new and not duplicate.updated and len(duplicate.duplicate) == 2


def test_publication_backfill_pages_match_package_and_survive_restart(tmp_path: Path) -> None:
    database_path = tmp_path / "legacy.sqlite3"
    uids = [f"n-018f3a2b-7c41-7000-8000-{number:012x}" for number in range(51)]
    documents = [
        document(uid, extra={
            "question": f"**Как?** {MEDIA_MARKER}",
            "sources": [{"ref": "synthetic", "locator": LITERAL_HTML}],
            "relations": [{"t": "related", "to": UID_A, "note": LITERAL_HTML}],
        })
        for uid in uids
    ]
    notes = parse_documents(documents)
    with closing(sqlite3.connect(database_path)) as connection, connection:
        connection.execute("""
            CREATE TABLE published_notes (
                uid TEXT NOT NULL PRIMARY KEY,
                guid TEXT NOT NULL UNIQUE,
                mod INTEGER NOT NULL,
                content TEXT NOT NULL
            )
        """)
        connection.executemany(
            "INSERT INTO published_notes (uid, guid, mod, content) VALUES (?, ?, ?, ?)",
            [
                (
                    note.uid, genanki.guid_for(note.uid), 1_800_000_000 + index,
                    note.model_dump_json(exclude_none=True),
                )
                for index, note in reversed(list(enumerate(notes)))
            ],
        )

    with app_for(database_path) as client:
        first = client.get(CHANGES, headers=ADMIN, params={"since": 0})
        assert first.status_code == 200, first.text
        page = first.json()
        stream = page["stream"]
        assert page["more"] is True
        assert [entry["seq"] for entry in page["changes"]] == list(range(1, 51))

        response = client.get(CHANGES, headers=ADMIN, params={
            "since": 50, "anchor": page["changes"][-1]["anchor"],
        })
        assert response.status_code == 200
        tail = response.json()
        assert tail["stream"] == stream
        assert tail["more"] is False
        assert [entry["seq"] for entry in tail["changes"]] == [51]
        events = [entry["event"] for entry in page["changes"] + tail["changes"]]
        anchors = [UUID(entry["anchor"]) for entry in page["changes"] + tail["changes"]]
        assert len(set(anchors)) == 51
        assert all(anchor.version == 4 for anchor in anchors)
        assert {event["kind"] for event in events} == {"publication"}
        assert [event["note"]["fields"][0] for event in events] == uids

        package = client.get(EXPORT, headers=ADMIN)
        assert package.status_code == 200
        assert sorted(
            (note["guid"], note["modelID"], note["mod"], "\x1f".join(note["fields"]))
            for note in (event["note"] for event in events)
        ) == exported_rows(package.content)
        assert publish(client, ADMIN, documents[0]) == [
            {"uid": uids[0], "guid": events[0]["note"]["guid"], "mod": events[0]["note"]["mod"]}
        ]
        cursor = {"since": 51, "anchor": tail["changes"][-1]["anchor"]}

    with app_for(database_path) as client:
        assert client.get(CHANGES, headers=ADMIN, params={"since": 0}).json() == page
        assert client.get(CHANGES, headers=ADMIN, params=cursor).json() == {
            "stream": stream, "changes": [], "more": False,
        }
        updated = publish(client, ADMIN, document(uids[0], body="Версия два."))[0]
        repeated = publish(client, ADMIN, document(uids[0], body="Версия два."))[0]
        assert repeated == updated
        latest = client.get(CHANGES, headers=ADMIN, params=cursor).json()
        new_anchor = UUID(latest["changes"][0]["anchor"])
        assert new_anchor.version == 4 and new_anchor not in anchors
        assert latest == {
            "stream": stream,
            "changes": [{
                "seq": 52,
                "anchor": str(new_anchor),
                "event": {
                    "kind": "publication",
                    "note": {
                        "guid": events[0]["note"]["guid"],
                        "modelID": 1936480171,
                        "mod": updated["mod"],
                        "fields": [
                            uids[0], "Синтетическая заметка", "<p>Версия два.</p>\n",
                            "<p>Вопрос?</p>\n", "<p>Ответ.</p>\n", "", "[]", "1",
                        ],
                    },
                },
            }],
            "more": False,
        }


def test_observations_before_publication_keep_distinct_uids(tmp_path: Path) -> None:
    guid = genanki.guid_for(UID_A)
    review = {
        "kind": "review", "id": "a0000000-0000-4000-8000-000000000001",
        "uid": UID_A, "guid": guid, "ord": 0, "reviewedAt": 1_800_000_000.25, "rating": 3,
    }
    progress = {
        "kind": "progress", "id": "a0000000-0000-4000-8000-000000000002",
        "uid": UID_B, "guid": guid, "ord": 0,
        "progress": {"due": 0, "ivl": 0, "queue": 0, "reviews": []},
    }
    with app_for(tmp_path / "server.sqlite3") as client:
        page = client.get(CHANGES, headers=ADMIN, params={"since": 0}).json()
        accepted = client.post(CHANGES, headers=ADMIN, json={
            "since": 0, "stream": page["stream"], "events": [review, progress],
        })
        assert accepted.status_code == 200
        assert publish(client, ADMIN, document(UID_A))[0]["guid"] == guid
        changes = client.get(CHANGES, headers=ADMIN, params={"since": 0}).json()["changes"]
        assert [change["event"] for change in changes[:2]] == [review, progress]
        assert changes[2]["event"]["note"]["fields"][0] == UID_A


def test_old_delta_database_keeps_publication_history_but_not_observations(tmp_path: Path) -> None:
    database_path = tmp_path / "legacy-delta.sqlite3"
    with app_for(database_path) as client:
        identity = publish(client, ADMIN, document(UID_A))[0]
        publish(client, ADMIN, document(UID_A, body="Версия два."))
        original = client.get(CHANGES, headers=ADMIN, params={"since": 0}).json()

    observations = [
        {
            "kind": "review", "id": "a0000000-0000-4000-8000-000000000001",
            "guid": identity["guid"], "ord": 0, "reviewedAt": 1_800_000_000.25, "rating": 3,
        },
        {
            "kind": "progress", "id": "a0000000-0000-4000-8000-000000000002",
            "guid": "unpublished-guid", "ord": 0,
            "progress": {"due": 0, "ivl": 0, "queue": 0, "reviews": []},
        },
    ]
    with closing(sqlite3.connect(database_path)) as connection, connection:
        connection.executescript("""
            BEGIN IMMEDIATE;
            DROP TABLE changes;
            CREATE TABLE changes (
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                event_id TEXT UNIQUE,
                event TEXT NOT NULL
            );
        """)
        connection.executemany(
            "INSERT INTO changes (seq, event_id, event) VALUES (?, ?, ?)",
            [
                (1, None, json.dumps(original["changes"][0]["event"])),
                (2, observations[0]["id"], json.dumps(observations[0])),
                (3, None, json.dumps(original["changes"][1]["event"])),
                (4, observations[1]["id"], json.dumps(observations[1])),
            ],
        )

    with app_for(database_path) as client:
        migrated = client.get(CHANGES, headers=ADMIN, params={"since": 0}).json()
        assert migrated["stream"] != original["stream"]
        assert [change["seq"] for change in migrated["changes"]] == [1, 3]
        assert [change["event"] for change in migrated["changes"]] == [
            change["event"] for change in original["changes"]
        ]
        assert all(UUID(change["anchor"]).version == 4 for change in migrated["changes"])
        bad_get = client.get(CHANGES, headers=ADMIN, params={"since": 1})
        assert bad_get.status_code == 409
        assert bad_get.json() == {"detail": {"code": "anchor_mismatch"}}
        bad_post = client.post(CHANGES, headers=ADMIN, json={
            "stream": original["stream"], "since": 0,
            "events": [{**observations[0], "uid": UID_A}],
        })
        assert bad_post.status_code == 409
        assert bad_post.json() == {"detail": {"code": "stream_mismatch"}}
        assert client.get(CHANGES, headers=ADMIN, params={"since": 0}).json() == migrated

    with app_for(database_path) as client:
        assert client.get(CHANGES, headers=ADMIN, params={"since": 0}).json() == migrated
        assert client.get(EXPORT, headers=ADMIN).status_code == 200


def test_failed_publication_rolls_back_notes_and_changes(tmp_path: Path, monkeypatch) -> None:
    with app_for(tmp_path / "server.sqlite3") as client:
        monkeypatch.setattr(genanki, "guid_for", lambda uid: "synthetic-collision")
        response = client.post(PUBLISH, headers=ADMIN, json={
            "documents": [document(UID_A), document(UID_B)],
        })
        assert response.status_code == 409
        assert response.json()["detail"] == {"code": "guid_conflict"}
        assert client.get(EXPORT, headers=ADMIN).status_code == 404
        assert client.get(CHANGES, headers=ADMIN, params={"since": 0}).json()["changes"] == []

        publish(client, ADMIN, document(UID_A))
        page = client.get(CHANGES, headers=ADMIN, params={"since": 0}).json()
        assert [entry["seq"] for entry in page["changes"]] == [1]


@pytest.mark.parametrize("bad_document", [
    "No frontmatter",
    document(UID_B, extra={"schema_version": True}),
    document(UID_B, extra={"uid": "n-invalid"}),
    document(UID_B, extra={"title": ""}),
    document(UID_B, extra={"sources": [{}]}),
    document(UID_B, extra={"sources": [{"ref": "source", "locator": None}]}),
    document(UID_B, extra={"relations": [{"t": "related", "to": UID_A, "note": None}]}),
    document(UID_B).replace('"Ответ."', '!!bool "not-a-boolean"'),
    document(UID_B, extra={"relations": [{"t": "required_for", "to": UID_A}]}),
    document(UID_B, extra={"relations": [{"t": "related", "to": "n-invalid"}]}),
    document(UID_B, extra={"answer": "a\x1fb"}),
    document(UID_B, extra={"body": "Second body"}),
    document(UID_B).replace('"answer": "Ответ.", ', ""),
    document(UID_B).replace('"answer": "Ответ."', '"answer": "Ответ.", "answer": "Дубль"'),
    "---\nkind: &kind fact\ntitle: *kind\n---\nBody",
])
def test_invalid_batch_writes_nothing(tmp_path: Path, bad_document: str) -> None:
    with app_for(tmp_path / "server.sqlite3") as client:
        response = client.post(PUBLISH, headers=ADMIN, json={"documents": [document(UID_A), bad_document]})
        assert response.status_code == 422
        assert response.json()["detail"] == {"code": "invalid_document", "document_index": 1}
        assert client.get(EXPORT, headers=ADMIN).json() == {"detail": {"code": "no_publications"}}


def test_publication_auth_and_request_failures(tmp_path: Path) -> None:
    with app_for(tmp_path / "server.sqlite3") as client:
        assert client.post(PUBLISH, json={"documents": [document(UID_A)]}).status_code == 401
        assert client.get(EXPORT, headers={"Authorization": "Bearer invalid"}).status_code == 401
        assert client.get(EXPORT, headers=ADMIN).status_code == 404
        assert client.post(PUBLISH, headers=ADMIN, content="not JSON").status_code == 415
        assert client.post(PUBLISH, headers=ADMIN, json={"documents": []}).status_code == 422
        duplicate_key = client.post(
            PUBLISH, headers={**ADMIN, "Content-Type": "application/json"},
            content='{"documents":[],"documents":' + json.dumps([document(UID_A)]) + '}',
        )
        assert duplicate_key.status_code == 422
        assert duplicate_key.json()["detail"] == {"code": "invalid_publication"}
        assert client.post(PUBLISH, headers={**ADMIN, "Content-Type": "application/json"},
                           content=iter([b" " * (512 * 1024)] * 3)).status_code == 413
        response = client.post(PUBLISH, headers=ADMIN, json={"documents": [document(UID_A)] * 2})
        assert response.status_code == 422
        assert response.json()["detail"] == {"code": "duplicate_uid", "document_index": 1}
        assert client.get(EXPORT, headers=ADMIN).status_code == 404
