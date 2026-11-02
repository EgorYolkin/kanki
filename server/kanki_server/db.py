from __future__ import annotations

import json
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator


class RevisionConflict(Exception):
    def __init__(self, current_revision: int) -> None:
        super().__init__(f"snapshot revision is {current_revision}")
        self.current_revision = current_revision


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
        with self.connect() as connection:
            connection.executescript(
                """
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
                """
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
