"""
Serialize published notes in the frozen Anki exchange v1 format.
"""

import json
from html import escape
from urllib.parse import urlsplit

from markdown_it import MarkdownIt

from .publication import PublishedNote

MODEL_ID = 1936480171
FIELD_NAMES = ("UID", "Title", "Body", "Question", "Answer", "Relations", "Sources", "SchemaVersion")

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


def exchange_fields(note: PublishedNote) -> list[str]:
    """
    Render the ordered v1 fields for both package and delta consumers.
    """

    relations = "\n".join(
        _metadata_object(relation.model_dump(exclude_none=True))
        for relation in note.relations
    )
    sources = "[" + ",".join(
        _metadata_object(source.model_dump(exclude_none=True))
        for source in note.sources
    ) + "]"
    return [
        note.uid,
        escape(note.title).translate(_ANKI_ESCAPES),
        _render_markdown(note.body),
        _render_markdown(note.question),
        _render_markdown(note.answer),
        relations,
        sources,
        str(note.schema_version),
    ]
