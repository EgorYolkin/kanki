from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Literal
from uuid import uuid4

import genanki

from .changes import (
    MAX_CHANGES_PER_PAGE,
    Change,
    ChangePage,
    ChangeWrite,
    PublicationEvent,
    PublicationNote,
)
from .exchange import MODEL_ID, exchange_fields
from .publication import PublicationIdentity, PublishedNote


class RevisionConflict(Exception):
    def __init__(self, current_revision: int) -> None:
        super().__init__(f"snapshot revision is {current_revision}")
        self.current_revision = current_revision


class PublicationIdentityConflict(Exception):
    pass


class ChangesConflict(Exception):
    def __init__(
        self, code: Literal["future_cursor", "stream_mismatch", "event_id_conflict"]
    ) -> None:
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class PublishedNoteRow:
    guid: str
    mod: int
    content: PublishedNote


@dataclass(frozen=True)
class SnapshotRow:
    revision: int
    schema_version: int
    data: dict[str, Any]
    updated_at: str


@dataclass(frozen=True)
class TokenRow:
    id: str
    label: str
    created_at: str
    revoked_at: str | None


class Database:
    """SQLite in WAL mode. One connection per operation; single writer via BEGIN IMMEDIATE."""

    def __init__(self, path: Path) -> None:
        self.path = path

    @contextmanager
    def connect(self) -> Iterator[sqlite3.Connection]:
        connection = sqlite3.connect(self.path, timeout=5.0)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=NORMAL")
        connection.execute("PRAGMA busy_timeout=5000")
        connection.execute("PRAGMA foreign_keys=ON")
        try:
            yield connection
        finally:
            connection.close()

    def initialize(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as connection, connection:
            connection.execute("PRAGMA synchronous=FULL")
            connection.executescript(
                """
                BEGIN IMMEDIATE;

                CREATE TABLE IF NOT EXISTS snapshots (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    revision INTEGER NOT NULL,
                    schema_version INTEGER NOT NULL,
                    data TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS tokens (
                    id TEXT PRIMARY KEY,
                    label TEXT NOT NULL,
                    token_hash TEXT NOT NULL UNIQUE,
                    created_at TEXT NOT NULL,
                    revoked_at TEXT
                );

                CREATE TABLE IF NOT EXISTS published_notes (
                    uid TEXT NOT NULL PRIMARY KEY,
                    guid TEXT NOT NULL UNIQUE,
                    mod INTEGER NOT NULL,
                    content TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS change_stream (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    stream TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS changes (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_id TEXT UNIQUE,
                    event TEXT NOT NULL
                );
                """
            )
            if connection.execute("SELECT 1 FROM change_stream WHERE id = 1").fetchone() is None:
                connection.execute(
                    "INSERT INTO change_stream (id, stream) VALUES (1, ?)",
                    (str(uuid4()),),
                )
                rows = connection.execute(
                    "SELECT guid, mod, content FROM published_notes ORDER BY uid"
                )
                for row in rows:
                    self._append_publication_change(
                        connection, row["guid"], row["mod"],
                        PublishedNote.model_validate_json(row["content"]),
                    )

    def ping(self) -> None:
        with self.connect() as connection:
            connection.execute("SELECT 1").fetchone()

    def read_snapshot(self) -> SnapshotRow | None:
        with self.connect() as connection:
            row = connection.execute(
                "SELECT revision, schema_version, data, updated_at FROM snapshots WHERE id = 1"
            ).fetchone()
        if row is None:
            return None
        return SnapshotRow(
            revision=row["revision"],
            schema_version=row["schema_version"],
            data=json.loads(row["data"]),
            updated_at=row["updated_at"],
        )

    def write_snapshot(
        self,
        *,
        schema_version: int,
        data: dict[str, Any],
        base_revision: int,
    ) -> SnapshotRow:
        payload = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        updated_at = datetime.now(timezone.utc).isoformat()
        with self.connect() as connection:
            connection.execute("BEGIN IMMEDIATE")
            try:
                row = connection.execute("SELECT revision FROM snapshots WHERE id = 1").fetchone()
                current_revision = row["revision"] if row else 0
                if current_revision != base_revision:
                    raise RevisionConflict(current_revision)
                revision = current_revision + 1
                connection.execute(
                    """
                    INSERT INTO snapshots (id, revision, schema_version, data, updated_at)
                    VALUES (1, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        revision = excluded.revision,
                        schema_version = excluded.schema_version,
                        data = excluded.data,
                        updated_at = excluded.updated_at
                    """,
                    (revision, schema_version, payload, updated_at),
                )
                connection.commit()
            except BaseException:
                connection.rollback()
                raise
        return SnapshotRow(
            revision=revision,
            schema_version=schema_version,
            data=data,
            updated_at=updated_at,
        )

    def publish(self, notes: list[PublishedNote]) -> list[PublicationIdentity]:
        payloads = [(note, note.model_dump_json(exclude_none=True)) for note in notes]
        identities = []
        try:
            with self.connect() as connection, connection:
                connection.execute("PRAGMA synchronous=FULL")
                connection.execute("BEGIN IMMEDIATE")
                now = int(datetime.now(timezone.utc).timestamp())
                for note, content in payloads:
                    uid = note.uid
                    row = connection.execute(
                        "SELECT guid, mod, content FROM published_notes WHERE uid = ?",
                        (uid,),
                    ).fetchone()
                    changed = row is None or row["content"] != content
                    if row is None:
                        guid, mod = genanki.guid_for(uid), now
                        connection.execute(
                            "INSERT INTO published_notes (uid, guid, mod, content) "
                            "VALUES (?, ?, ?, ?)",
                            (uid, guid, mod, content),
                        )
                    else:
                        guid, mod = row["guid"], row["mod"]
                        if changed:
                            mod = max(now, mod + 1)
                            connection.execute(
                                "UPDATE published_notes SET mod = ?, content = ? WHERE uid = ?",
                                (mod, content, uid),
                            )
                    if changed:
                        self._append_publication_change(connection, guid, mod, note)
                    identities.append(PublicationIdentity(uid=uid, guid=guid, mod=mod))
        except sqlite3.IntegrityError as error:
            if error.sqlite_errorcode != sqlite3.SQLITE_CONSTRAINT_UNIQUE:
                raise
            raise PublicationIdentityConflict() from error
        return identities

    def read_publications(self) -> list[PublishedNoteRow]:
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT guid, mod, content FROM published_notes ORDER BY uid"
            ).fetchall()
        return [
            PublishedNoteRow(row["guid"], row["mod"], PublishedNote.model_validate_json(row["content"]))
            for row in rows
        ]

    @staticmethod
    def _append_publication_change(
        connection: sqlite3.Connection, guid: str, mod: int, note: PublishedNote
    ) -> None:
        event = PublicationEvent(
            kind="publication",
            note=PublicationNote(
                guid=guid, modelID=MODEL_ID, mod=mod, fields=exchange_fields(note)
            ),
        )
        connection.execute(
            "INSERT INTO changes (event) VALUES (?)",
            (event.model_dump_json(by_alias=True),),
        )

    def read_changes(self, since: int) -> ChangePage:
        """
        Return one page from a consistent view of the stream and its latest cursor.
        """

        with self.connect() as connection, connection:
            connection.execute("BEGIN")
            stream = connection.execute(
                "SELECT stream FROM change_stream WHERE id = 1"
            ).fetchone()["stream"]
            latest = connection.execute(
                "SELECT COALESCE(MAX(seq), 0) FROM changes"
            ).fetchone()[0]
            if since > latest:
                raise ChangesConflict("future_cursor")

            rows = connection.execute(
                "SELECT seq, event FROM changes WHERE seq > ? ORDER BY seq LIMIT ?",
                (since, MAX_CHANGES_PER_PAGE + 1),
            ).fetchall()
        more = len(rows) > MAX_CHANGES_PER_PAGE
        if more:
            rows.pop()

        return ChangePage(
            stream=stream,
            changes=[Change(seq=row["seq"], event=json.loads(row["event"])) for row in rows],
            more=more,
        )

    def append_changes(self, request: ChangeWrite) -> list[str]:
        """
        Append raw observations atomically, acknowledging exact retries in place.
        """

        payloads = [
            (event.id, event.model_dump_json(by_alias=True)) for event in request.events
        ]
        with self.connect() as connection, connection:
            connection.execute("PRAGMA synchronous=FULL")
            connection.execute("BEGIN IMMEDIATE")
            stream = connection.execute(
                "SELECT stream FROM change_stream WHERE id = 1"
            ).fetchone()["stream"]
            if request.stream != stream:
                raise ChangesConflict("stream_mismatch")

            for event_id, payload in payloads:
                row = connection.execute(
                    "SELECT event FROM changes WHERE event_id = ?", (event_id,)
                ).fetchone()
                if row is None:
                    connection.execute(
                        "INSERT INTO changes (event_id, event) VALUES (?, ?)",
                        (event_id, payload),
                    )
                elif row["event"] != payload:
                    raise ChangesConflict("event_id_conflict")

        return [event_id for event_id, _ in payloads]

    def create_token(self, *, token_id: str, label: str, token_hash: str, created_at: str) -> TokenRow:
        with self.connect() as connection:
            connection.execute(
                "INSERT INTO tokens (id, label, token_hash, created_at) VALUES (?, ?, ?, ?)",
                (token_id, label, token_hash, created_at),
            )
            connection.commit()
        return TokenRow(id=token_id, label=label, created_at=created_at, revoked_at=None)

    def find_active_token(self, token_hash: str) -> TokenRow | None:
        with self.connect() as connection:
            row = connection.execute(
                """
                SELECT id, label, created_at, revoked_at
                FROM tokens
                WHERE token_hash = ? AND revoked_at IS NULL
                """,
                (token_hash,),
            ).fetchone()
        if row is None:
            return None
        return TokenRow(
            id=row["id"],
            label=row["label"],
            created_at=row["created_at"],
            revoked_at=row["revoked_at"],
        )

    def list_tokens(self) -> list[TokenRow]:
        with self.connect() as connection:
            rows = connection.execute(
                "SELECT id, label, created_at, revoked_at FROM tokens ORDER BY created_at"
            ).fetchall()
        return [
            TokenRow(
                id=row["id"],
                label=row["label"],
                created_at=row["created_at"],
                revoked_at=row["revoked_at"],
            )
            for row in rows
        ]

    def revoke_token(self, token_id: str) -> bool:
        revoked_at = datetime.now(timezone.utc).isoformat()
        with self.connect() as connection:
            cursor = connection.execute(
                "UPDATE tokens SET revoked_at = ? WHERE id = ? AND revoked_at IS NULL",
                (revoked_at, token_id),
            )
            connection.commit()
        return cursor.rowcount > 0
