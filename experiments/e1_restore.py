"""Restore E1 .apkg content and separately reviewed progress into a temporary SQLite DB.

This validates the experiment's (guid, ord) correspondence, not a production
Kanki schema or a general-purpose Anki importer.
"""

import argparse
import io
import json
import sqlite3
import tempfile
import zipfile
from pathlib import Path

import zstandard

from e1 import FIELDS

INVERSE = {"requires": "required_for", "part_of": "has_part", "related": "related", "contrast": "contrast"}


def package_rows(package: Path):
    with zipfile.ZipFile(package) as archive, tempfile.TemporaryDirectory() as temp:
        source = Path(temp) / "collection.anki2"
        if "collection.anki21b" in archive.namelist():
            with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(archive.read("collection.anki21b"))) as stream:
                source.write_bytes(stream.read())
        else:
            source.write_bytes(archive.read("collection.anki2"))
        with sqlite3.connect(source) as connection:
            notes = connection.execute("SELECT id, guid, mid, flds FROM notes").fetchall()
            cards = connection.execute("SELECT id, nid, ord, due, ivl, queue FROM cards").fetchall()
            reviews = connection.execute("SELECT id, cid, ease, ivl, lastIvl, factor, time, type FROM revlog").fetchall()
    return notes, cards, reviews


def unpack_notes(notes):
    by_nid = {}
    by_guid = {}
    seen_uids = set()
    for nid, guid, model, fields in notes:
        values = fields.split("\x1f")
        if len(values) != len(FIELDS) or not values[0].startswith("n-") or values[7] != "1":
            raise ValueError("E1 requires eight fields, UID first and SchemaVersion=1")
        if guid in by_guid or values[0] in seen_uids:
            raise ValueError("Duplicate guid or UID in package")
        by_nid[nid] = guid
        seen_uids.add(values[0])
        by_guid[guid] = (model, values)
    return by_nid, by_guid


def card_keys(cards, by_nid):
    by_card = {}
    by_key = {}
    for cid, nid, ord_, due, interval, queue in cards:
        guid = by_nid[nid]
        key = (guid, ord_)
        if key in by_key:
            raise ValueError("Duplicate (guid, ord) in package")
        by_key[key] = (due, interval, queue)
        by_card[cid] = key
    return by_card, by_key


def restore(content: Path, progress: Path, output: Path) -> None:
    """Keep newest content and reviewed scheduling; reject changed card identity/type."""
    if output.exists():
        raise FileExistsError(f"Refusing to overwrite {output}")
    content_notes, content_cards, _ = package_rows(content)
    progress_notes, progress_cards, reviews = package_rows(progress)
    content_nids, by_guid = unpack_notes(content_notes)
    progress_nids, reviewed = unpack_notes(progress_notes)
    progress_cids, progress_keys = card_keys(progress_cards, progress_nids)
    _, content_keys = card_keys(content_cards, content_nids)
    if len(by_guid) != 2 or set(content_keys) != {(guid, 0) for guid in by_guid}:
        raise ValueError("E1 requires exactly two notes and one card per note")
    if by_guid.keys() != reviewed.keys() or content_keys.keys() != progress_keys.keys():
        raise ValueError("Content and scheduling packages disagree about note/card identity")
    for guid, (model, fields) in by_guid.items():
        old_model, old_fields = reviewed[guid]
        if model != old_model or fields[0] != old_fields[0]:
            raise ValueError("Note type or UID changed between content and scheduling")

    with tempfile.TemporaryDirectory(prefix="kanki-e1-restore-") as temp:
        temporary = Path(temp) / "restored.sqlite"
        with sqlite3.connect(temporary) as database:
            database.executescript("""
                CREATE TABLE notes(uid TEXT PRIMARY KEY, guid TEXT UNIQUE NOT NULL,
                    model_id INTEGER NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL,
                    question TEXT NOT NULL, answer TEXT NOT NULL, relations TEXT NOT NULL,
                    sources TEXT NOT NULL, schema_version TEXT NOT NULL);
                CREATE TABLE cards(guid TEXT NOT NULL, ord INTEGER NOT NULL,
                    due INTEGER NOT NULL, interval INTEGER NOT NULL, queue INTEGER NOT NULL,
                    PRIMARY KEY(guid, ord));
                CREATE TABLE edges(src_uid TEXT NOT NULL, rel_type TEXT NOT NULL,
                    dst_uid TEXT NOT NULL, seq INTEGER NOT NULL, derived INTEGER NOT NULL,
                    PRIMARY KEY(src_uid, rel_type, dst_uid, seq, derived));
                CREATE TABLE review_log(id INTEGER PRIMARY KEY, guid TEXT NOT NULL,
                    ord INTEGER NOT NULL, anki_cid INTEGER NOT NULL, ease INTEGER NOT NULL,
                    ivl INTEGER NOT NULL, last_ivl INTEGER NOT NULL, factor INTEGER NOT NULL,
                    time_ms INTEGER NOT NULL, review_type INTEGER NOT NULL);
            """)
            for guid, (model, fields) in by_guid.items():
                uid, title, body, question, answer, relations, sources, version = fields
                database.execute("INSERT INTO notes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                 (uid, guid, model, title, body, question, answer, relations, sources, version))
                for seq, line in enumerate(relations.splitlines()):
                    relation = json.loads(line)
                    kind, target = relation["t"], relation["to"]
                    if kind not in INVERSE or not isinstance(target, str) or not target.startswith("n-"):
                        raise ValueError("Unsupported E1 relation")
                    database.execute("INSERT INTO edges VALUES (?, ?, ?, ?, 0)", (uid, kind, target, seq))
                    database.execute("INSERT INTO edges VALUES (?, ?, ?, ?, 1)", (target, INVERSE[kind], uid, seq))
            for (guid, ord_), (due, interval, queue) in progress_keys.items():
                database.execute("INSERT INTO cards VALUES (?, ?, ?, ?, ?)", (guid, ord_, due, interval, queue))
            for rid, cid, ease, interval, last_interval, factor, time_ms, review_type in reviews:
                if cid not in progress_cids:
                    raise ValueError("Review references a card absent from scheduling package")
                guid, ord_ = progress_cids[cid]
                database.execute("INSERT INTO review_log VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                 (rid, guid, ord_, cid, ease, interval, last_interval, factor, time_ms, review_type))
        temporary.replace(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("content", type=Path, help="updated test3.apkg")
    parser.add_argument("progress", type=Path, help="reviewed test2.apkg")
    parser.add_argument("output", type=Path, help="new isolated SQLite database")
    args = parser.parse_args()
    restore(args.content, args.progress, args.output)
    print(f"Restored E1 content and scheduling into {args.output}")


if __name__ == "__main__":
    main()
