"""Markdown publication input and its normalized exchange v1 records."""

import re
from typing import Annotated, Literal

import yaml
from pydantic import AfterValidator, BaseModel, ConfigDict, Field
from yaml.events import AliasEvent
from yaml.nodes import MappingNode

MAX_PUBLISH_BYTES = 1024 * 1024
_FRONTMATTER_END = re.compile(r"^---$", re.MULTILINE)
_UNSUPPORTED_TEXT = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\ud800-\udfff]")


class InvalidDocument(ValueError):
    def __init__(self, code: str, index: int) -> None:
        super().__init__(code)
        self.code = code
        self.index = index


class _FrontmatterLoader(yaml.SafeLoader):
    """Single shallow YAML document with no alias or duplicate-key semantics."""

    _depth = 0

    def compose_node(self, parent, index):
        if self._depth >= 16 or self.check_event(AliasEvent):
            raise yaml.YAMLError("Unsupported YAML structure")
        self._depth += 1
        try:
            return super().compose_node(parent, index)
        finally:
            self._depth -= 1

    def construct_mapping(self, node: MappingNode, deep: bool = False) -> dict:
        mapping = {}
        for key_node, value_node in node.value:
            key = self.construct_object(key_node, deep=deep)
            if not isinstance(key, str) or key in mapping:
                raise yaml.YAMLError("Frontmatter keys must be unique strings")
            mapping[key] = self.construct_object(value_node, deep=deep)
        return mapping


def _text(value: str) -> str:
    if _UNSUPPORTED_TEXT.search(value):
        raise ValueError("Unsupported control character")
    return value.replace("\r\n", "\n").replace("\r", "\n")


def _nonblank(value: str) -> str:
    if not value.strip():
        raise ValueError("Expected nonblank text")
    return value


_Text = Annotated[str, AfterValidator(_text)]
_NonblankText = Annotated[_Text, AfterValidator(_nonblank)]
_UID = Annotated[str, Field(
    min_length=38,
    max_length=38,
    pattern=r"^n-[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
)]


class _StrictModel(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")


class Source(_StrictModel):
    ref: _NonblankText
    locator: _Text | None = None


class Relation(_StrictModel):
    t: Literal["requires", "part_of", "related", "contrast"]
    to: _UID
    note: _Text | None = None


class PublishedNote(_StrictModel):
    uid: _UID
    schema_version: int = Field(ge=1, le=1)
    kind: Literal["concept", "fact", "source"]
    title: _NonblankText
    body: _NonblankText
    question: _Text
    answer: _Text
    sources: list[Source]
    relations: list[Relation]


class PublishRequest(_StrictModel):
    documents: list[str] = Field(min_length=1, max_length=100)


class PublicationIdentity(BaseModel):
    uid: str
    guid: str
    mod: int


class PublishResponse(BaseModel):
    notes: list[PublicationIdentity]


def parse_documents(documents: list[str]) -> list[PublishedNote]:
    """Validate the entire ordered batch before anything can be persisted."""
    seen = set()
    notes = []
    for index, document in enumerate(documents):
        try:
            note = _parse_document(document)
        except (ValueError, yaml.YAMLError) as error:
            raise InvalidDocument("invalid_document", index) from error
        if note.uid in seen:
            raise InvalidDocument("duplicate_uid", index)
        seen.add(note.uid)
        notes.append(note)
    return notes


def _parse_document(document: str) -> PublishedNote:
    document = _text(document)
    if not document.startswith("---\n"):
        raise ValueError("Missing opening frontmatter delimiter")
    rest = document[4:]
    closing = _FRONTMATTER_END.search(rest)
    if closing is None:
        raise ValueError("Missing closing frontmatter delimiter")
    frontmatter = yaml.load(rest[:closing.start()], Loader=_FrontmatterLoader)
    if not isinstance(frontmatter, dict):
        raise ValueError("Expected a frontmatter mapping")
    body = rest[closing.end():].removeprefix("\n")
    if body.strip():
        if "body" in frontmatter:
            raise ValueError("Body appears in two places")
        frontmatter["body"] = body
    return PublishedNote.model_validate(frontmatter)
