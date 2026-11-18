"""Convert stored exchange v1 notes to a content-only Anki package."""

import io
import itertools
import sqlite3
import zipfile
from contextlib import closing

import genanki

from .db import PublishedNoteRow
from .exchange import FIELD_NAMES, MODEL_ID, exchange_fields


class _PublishedNote(genanki.Note):
    """Use the stored modification time, not the package creation time."""

    def __init__(self, model: genanki.Model, guid: str, fields: list[str], mod: int) -> None:
        super().__init__(model=model, guid=guid, fields=fields)
        self.mod = mod

    def write_to_db(self, cursor, timestamp, deck_id, id_gen):
        super().write_to_db(cursor, self.mod, deck_id, id_gen)


def build_apkg(rows: list[PublishedNoteRow]) -> bytes:
    """
    Write the frozen one-card note type and preserve each note's stored mod.
    """

    model = genanki.Model(
        MODEL_ID,
        "ObsidianTyped-E1-experiment",
        fields=[{"name": field} for field in FIELD_NAMES],
        templates=[{
            "name": "Question and answer",
            "qfmt": '{{#UID}}<div class="mathjax_ignore">'
                    '{{Question}}{{^Question}}{{Title}}{{/Question}}</div>{{/UID}}',
            "afmt": '{{FrontSide}}<hr id="answer"><div class="mathjax_ignore">'
                    '{{Answer}}<div class="relations">{{Relations}}</div></div>',
        }],
        css=".relations { white-space: pre-wrap; }",
    )
    deck = genanki.Deck(1936480172, "Kanki")
    for row in rows:
        deck.add_note(_PublishedNote(
            mod=row.mod,
            model=model,
            guid=row.guid,
            fields=exchange_fields(row.content),
        ))

    # Use the pinned writer's SQLite schema without its temporary-file ZIP path.
    timestamp = max(row.mod for row in rows)
    with closing(sqlite3.connect(":memory:")) as database:
        genanki.Package(deck).write_to_db(
            database.cursor(), timestamp, itertools.count(timestamp * 1000),
        )
        database.commit()
        collection = database.serialize()

    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("collection.anki2", collection)
        archive.writestr("media", "{}")
    return output.getvalue()
