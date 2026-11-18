"""Convert stored exchange v1 notes to a content-only Anki package."""

import io
import itertools
import json
import sqlite3
import zipfile
from contextlib import closing
from html import escape
from urllib.parse import urlsplit

import genanki
from markdown_it import MarkdownIt

from .db import PublishedNoteRow

_FIELDS = ("UID", "Title", "Body", "Question", "Answer", "Relations", "Sources", "SchemaVersion")

# Anki preprocesses bracket-based media, TTS and LaTeX markers before HTML display.
_ANKI_ESCAPES = str.maketrans({"[": "&#91;", "]": "&#93;", "\\": "&#92;"})
_JSON_ESCAPES = str.maketrans({char: rf"\u{ord(char):04x}" for char in "<>&[]\u2028\u2029"})


class _CardMarkdown(MarkdownIt):
    def validateLink(self, url: str) -> bool:
        try:
            parts = urlsplit(url)
            return parts.scheme in {"http", "https"} and bool(parts.hostname)
        except ValueError:
            return False


_MARKDOWN = _CardMarkdown("commonmark", {"html": False}).disable(
    ["image", "heading", "lheading", "blockquote", "hr"],
)


def _render_markdown(text: str) -> str:
    return _MARKDOWN.render(text).translate(_ANKI_ESCAPES)


def _metadata_object(fields: dict[str, str]) -> str:
    # Escape only JSON strings, not structural syntax. Fields stay parseable as
    # raw JSON by exchange consumers and are inert if inserted into card HTML.
    return "{" + ",".join(
        f"{json.dumps(key)}:{json.dumps(value, ensure_ascii=False).translate(_JSON_ESCAPES)}"
        for key, value in fields.items()
    ) + "}"


def build_apkg(rows: list[PublishedNoteRow]) -> bytes:
    """Write the frozen one-card note type and preserve each note's stored mod."""
    model = genanki.Model(
        1936480171,
        "ObsidianTyped-E1-experiment",
        fields=[{"name": field} for field in _FIELDS],
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
        note = row.content
        relations = "\n".join(
            _metadata_object(relation.model_dump(exclude_none=True))
            for relation in note.relations
        )
        sources = "[" + ",".join(
            _metadata_object(source.model_dump(exclude_none=True))
            for source in note.sources
        ) + "]"
        deck.add_note(genanki.Note(model=model, guid=row.guid, fields=[
            note.uid,
            escape(note.title).translate(_ANKI_ESCAPES),
            _render_markdown(note.body),
            _render_markdown(note.question),
            _render_markdown(note.answer),
            relations,
            sources,
            str(note.schema_version),
        ]))

    # Use the pinned writer's SQLite schema without its temporary-file ZIP path.
    # Its timestamp is package-wide; supply the actual per-note mod separately.
    timestamp = max(row.mod for row in rows)
    with closing(sqlite3.connect(":memory:")) as database:
        genanki.Package(deck).write_to_db(
            database.cursor(), timestamp, itertools.count(timestamp * 1000),
        )
        database.executemany(
            "UPDATE notes SET mod = ? WHERE guid = ?",
            ((row.mod, row.guid) for row in rows if row.mod != timestamp),
        )
        database.commit()
        collection = database.serialize()

    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("collection.anki2", collection)
        archive.writestr("media", "{}")
    return output.getvalue()
