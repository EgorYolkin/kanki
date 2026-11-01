"""Disposable AnkiDesktop E1 fixture; not the production exchange converter.

Run with: uv run --no-project --with genanki==0.13.1 python experiments/e1.py ...
"""

import argparse
import json
import sqlite3
import tempfile
import zipfile
from pathlib import Path

UID_A = "n-018f3a2b-7c41-7000-8000-000000000001"
UID_B = "n-018f3a2b-7c41-7000-8000-000000000004"
MODEL_ID = 1936480171
DECK_ID = 1936480172
FIELDS = ("UID", "Title", "Body", "Question", "Answer", "Relations", "Sources", "SchemaVersion")


def generate(directory: Path) -> None:
    import genanki

    model = genanki.Model(
        MODEL_ID,
        "ObsidianTyped-E1-experiment",
        fields=[{"name": field} for field in FIELDS],
        templates=[{
            "name": "Question and answer",
            "qfmt": "{{Question}}",
            "afmt": "{{FrontSide}}<hr id=answer>{{Answer}}<br>{{Relations}}",
        }],
    )
    directory.mkdir(parents=True, exist_ok=True)
    for filename, timestamp, updated in (("test1.apkg", 1_800_000_000, False), ("test3.apkg", 1_800_000_001, True)):
        deck = genanki.Deck(DECK_ID, "Kanki E1 experiment")
        deck.add_note(genanki.Note(model=model, guid=genanki.guid_for(UID_A), fields=[
            UID_A, "Кинетика Михаэлиса–Ментен",
            "Обновлённая модель скорости реакции." if updated else "Модель скорости ферментативной реакции.",
            "Что означает Km?", "Концентрация субстрата при половине Vmax.",
            json.dumps({"t": "related", "to": UID_B}, ensure_ascii=False) if updated else "",
            "[]", "1",
        ]))
        deck.add_note(genanki.Note(model=model, guid=genanki.guid_for(UID_B), fields=[
            UID_B, "Ингибиторы", "Конкурентный ингибитор связывается с активным центром.",
            "Как влияет конкурентный ингибитор на Km?", "Km растёт, Vmax не меняется.",
            json.dumps({"t": "requires", "to": UID_A}, ensure_ascii=False), "[]", "1",
        ]))
        genanki.Package(deck).write_to_file(directory / filename, timestamp=timestamp)
        print(f"{filename}: mod={timestamp}, 2 notes, 2 cards")

    changed_model = genanki.Model(
        MODEL_ID + 10,
        "ObsidianTyped-E1-negative-control",
        fields=[{"name": field} for field in (*FIELDS, "Extra")],
        templates=[{"name": "Question and answer", "qfmt": "{{Question}}", "afmt": "{{FrontSide}}<hr id=answer>{{Answer}}"}],
    )
    changed_deck = genanki.Deck(DECK_ID, "Kanki E1 experiment")
    changed_deck.add_note(genanki.Note(model=changed_model, guid=genanki.guid_for(UID_A), fields=[
        UID_A, "Кинетика Михаэлиса–Ментен", "Контроль смены типа заметки.",
        "Что означает Km?", "Концентрация субстрата при половине Vmax.",
        "", "[]", "1", "новое поле",
    ]))
    genanki.Package(changed_deck).write_to_file(directory / "test4-type-change.apkg", timestamp=1_800_000_002)
    print("test4-type-change.apkg: different model id, same note guid (negative control)")


def inspect(package: Path) -> None:
    with zipfile.ZipFile(package) as archive, tempfile.TemporaryDirectory() as temp:
        database = Path(temp) / "collection.anki2"
        database.write_bytes(archive.read("collection.anki2"))
        with sqlite3.connect(database) as connection:
            notes = connection.execute("SELECT id, guid, mid, mod, flds FROM notes ORDER BY id").fetchall()
            cards = connection.execute("SELECT nid, ord, due, ivl FROM cards ORDER BY nid, ord").fetchall()
            logs = connection.execute("SELECT COUNT(*) FROM revlog").fetchone()[0]
    print(f"{package.name}: {len(notes)} notes, {len(cards)} cards, {logs} revlog rows")
    for note_id, guid, model_id, mod, raw_fields in notes:
        fields = raw_fields.split("\x1f")
        print(f"  {fields[0]} guid={guid} model={model_id} mod={mod} cards={[(ord_, due, ivl) for nid, ord_, due, ivl in cards if nid == note_id]}")
        if len(fields) == len(FIELDS) and fields[5]:
            for line in fields[5].splitlines():
                relation = json.loads(line)
                print(f"    {fields[0]} --{relation['t']}--> {relation['to']}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    subcommands.add_parser("generate").add_argument("directory", type=Path)
    subcommands.add_parser("inspect").add_argument("package", type=Path)
    options = parser.parse_args()
    if options.command == "generate":
        generate(options.directory)
    else:
        inspect(options.package)


if __name__ == "__main__":
    main()
