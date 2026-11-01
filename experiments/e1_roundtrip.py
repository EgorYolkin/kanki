"""Run E1 using Anki's import/scheduler/export backend in an isolated collection.

This is an experiment, not the Kanki database or production converter.
Run after e1.py generate:
  uv run --no-project --with anki==26.09.3 --with zstandard python experiments/e1_roundtrip.py /tmp/kanki-e1
"""

import argparse
import io
import json
import sqlite3
import tempfile
import zipfile
from pathlib import Path

import zstandard
from anki.collection import Collection
from anki.exporting import ExportAnkiPackageOptions
from anki.importing import ImportAnkiPackageOptions, ImportAnkiPackageRequest
from anki.scheduler.v3 import CardAnswer

from e1 import UID_A, UID_B, inspect
from e1_restore import restore


def exported_state(package: Path):
    """Read the modern collection; collection.anki2 is only a legacy placeholder."""
    with zipfile.ZipFile(package) as archive, tempfile.TemporaryDirectory() as temp:
        database = Path(temp) / "collection.anki21"
        with zstandard.ZstdDecompressor().stream_reader(io.BytesIO(archive.read("collection.anki21b"))) as source:
            database.write_bytes(source.read())
        with sqlite3.connect(database) as connection:
            notes = connection.execute("SELECT id, guid, flds FROM notes").fetchall()
            cards = connection.execute("SELECT nid, ord, id, due, ivl, queue FROM cards").fetchall()
            revlog = connection.execute("SELECT cid FROM revlog").fetchall()
    by_id = {nid: (guid, fields.split("\x1f")) for nid, guid, fields in notes}
    by_card = {(by_id[nid][0], ord_): (cid, due, interval, queue) for nid, ord_, cid, due, interval, queue in cards}
    relations = {
        (fields[0], relation["t"], relation["to"])
        for _, fields in by_id.values()
        for line in fields[5].splitlines()
        for relation in (json.loads(line),)
    }
    return by_id, by_card, {cid for (cid,) in revlog}, relations


def run(directory: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="kanki-e1-") as temp:
        collection = Collection(str(Path(temp) / "collection.anki2"))
        try:
            def import_package(name: str):
                return collection.import_anki_package(ImportAnkiPackageRequest(
                    package_path=str(directory / name),
                    options=ImportAnkiPackageOptions(update_notes=0, update_notetypes=0, with_scheduling=True),
                )).log

            def state():
                notes = {collection.get_note(nid).fields[0]: collection.get_note(nid) for nid in collection.find_notes("")}
                cards = {}
                for cid in collection.find_cards(""):
                    card = collection.get_card(cid)
                    cards[(collection.get_note(card.nid).guid, card.ord)] = (card.due, card.ivl, card.queue)
                return notes, cards, collection.db.scalar("SELECT COUNT(*) FROM revlog")

            first = import_package("test1.apkg")
            notes, _, logs = state()
            assert len(first.new) == 2 and len(notes) == 2 and logs == 0
            assert len(collection.find_cards("")) == 2
            assert "Что означает Km?" in collection.get_card(collection.find_cards("")[0]).question()
            assert "requires" in collection.get_card(collection.find_cards("")[1]).answer()

            collection.decks.select(collection.decks.id("Kanki E1 experiment", create=False))
            for queued in collection.sched.get_queued_cards(fetch_limit=2).cards:
                card = collection.get_card(queued.card.id)
                card.start_timer()
                collection.sched.answer_card(collection.sched.build_answer(
                    card=card, states=queued.states, rating=CardAnswer.Rating.GOOD,
                ))
            original_notes, reviewed, logs = state()
            assert logs == 2 and len(reviewed) == 2
            assert all(key[1] == 0 for key in reviewed)

            package = directory / "test2.apkg"
            collection.export_anki_package(
                out_path=str(package),
                options=ExportAnkiPackageOptions(with_scheduling=True, with_media=False),
                limit=None,
            )
            exported_notes, exported_cards, exported_logs, relations = exported_state(package)
            assert len(exported_notes) == 2 and len(exported_logs) == 2
            assert len(exported_cards) == 2 and len(exported_logs & {card[0] for card in exported_cards.values()}) == 2
            assert {(guid, ord_): (due, ivl, queue) for (guid, ord_), (_, due, ivl, queue) in exported_cards.items()} == reviewed
            assert relations == {(UID_B, "requires", UID_A)}
            inverse = {(target, "required_for", source) for source, kind, target in relations if kind == "requires"}
            assert inverse == {(UID_A, "required_for", UID_B)}

            update = import_package("test3.apkg")
            updated_notes, updated_progress, logs = state()
            assert len(update.updated) == 2 and not update.new
            assert updated_progress == reviewed and logs == 2
            assert updated_notes[UID_A].guid == original_notes[UID_A].guid
            assert updated_notes[UID_A].fields[2] == "Обновлённая модель скорости реакции."
            assert json.loads(updated_notes[UID_A].fields[5])["to"] == UID_B

            repeat = import_package("test3.apkg")
            assert not repeat.updated and not repeat.new and len(repeat.duplicate) == 2
            conflict = import_package("test4-type-change.apkg")
            assert len(conflict.conflicting) == 1 and not conflict.updated and not conflict.new
            final_notes, final_progress, final_logs = state()
            assert len(final_notes) == 2 and final_progress == reviewed and final_logs == 2
            restored = Path(temp) / "restored.sqlite"
            restore(directory / "test3.apkg", package, restored)
            with sqlite3.connect(restored) as database:
                assert database.execute("SELECT body FROM notes WHERE uid = ?", (UID_A,)).fetchone()[0] == "Обновлённая модель скорости реакции."
                assert set(database.execute("SELECT src_uid, rel_type, dst_uid, derived FROM edges")) == {
                    (UID_B, "requires", UID_A, 0), (UID_A, "required_for", UID_B, 1),
                    (UID_A, "related", UID_B, 0), (UID_B, "related", UID_A, 1),
                }
                assert set(database.execute("SELECT guid, ord, due, interval, queue FROM cards")) == {
                    (guid, ord_, due, ivl, queue) for (guid, ord_), (due, ivl, queue) in reviewed.items()
                }
                assert sorted(database.execute("SELECT guid, ord FROM review_log")) == sorted(reviewed)
            rejected = Path(temp) / "rejected.sqlite"
            try:
                restore(directory / "test4-type-change.apkg", package, rejected)
            except ValueError:
                assert not rejected.exists()
            else:
                raise AssertionError("E1 type-change package was not rejected")
            print("Reverse import: current content, 4 canonical/derived edges, 2 reviews and due/interval restored by (guid, ord)")
            print("Anki 26.09.3 backend: 2 notes, 2 cards, 2 reviews; export/import preserved (guid, ord), progress and Relations")
            print("Re-import: 0 added, 0 updated; note-type change: 1 conflict, original notes and progress intact")
            inspect(package)
        finally:
            collection.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    run(parser.parse_args().directory)
