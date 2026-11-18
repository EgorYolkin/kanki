"""
Wire records for the append-only publication and observation stream.
"""

from typing import Annotated, Literal, Self

from pydantic import BaseModel, ConfigDict, Field, model_validator

from .publication import _UID

MAX_CHANGES_PER_PAGE = 50
MAX_EVENTS_PER_POST = 50
MAX_CHANGES_BYTES = 1024 * 1024
MAX_INT64 = (1 << 63) - 1

_Int64 = Annotated[int, Field(ge=-MAX_INT64 - 1, le=MAX_INT64)]
UUID_PATTERN = r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
_UUID = Annotated[str, Field(pattern=UUID_PATTERN)]
_Guid = Annotated[str, Field(min_length=1)]


class _StrictModel(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")


class RawReview(_StrictModel):
    id: _Int64
    ease: _Int64
    ivl: _Int64
    last_ivl: _Int64 = Field(alias="lastIvl")
    factor: _Int64
    time: _Int64
    type: _Int64


class RawProgress(_StrictModel):
    due: _Int64
    ivl: _Int64
    queue: _Int64
    reviews: list[RawReview] = Field(max_length=100)

    @model_validator(mode="after")
    def unique_review_ids(self) -> Self:
        if len({review.id for review in self.reviews}) != len(self.reviews):
            raise ValueError("Raw review IDs must be unique within an observation")

        return self


class _CardEvent(_StrictModel):
    id: _UUID
    uid: _UID
    guid: _Guid
    ord: int = Field(ge=0, le=0)


class ReviewEvent(_CardEvent):
    kind: Literal["review"]
    reviewed_at: float = Field(alias="reviewedAt", allow_inf_nan=False)
    rating: int = Field(ge=1, le=4)


class ProgressEvent(_CardEvent):
    kind: Literal["progress"]
    progress: RawProgress


class PublicationNote(_StrictModel):
    guid: _Guid
    model_id: _Int64 = Field(alias="modelID")
    mod: _Int64
    fields: list[str]


class PublicationEvent(_StrictModel):
    kind: Literal["publication"]
    note: PublicationNote


ClientEvent = Annotated[ReviewEvent | ProgressEvent, Field(discriminator="kind")]
StreamEvent = Annotated[
    PublicationEvent | ReviewEvent | ProgressEvent, Field(discriminator="kind")
]


class Change(_StrictModel):
    seq: _Int64
    anchor: _UUID
    event: StreamEvent


class ChangePage(_StrictModel):
    stream: _UUID
    changes: list[Change]
    more: bool


class ChangeWrite(_StrictModel):
    stream: _UUID
    since: int = Field(ge=0, le=MAX_INT64)
    anchor: _UUID | None = None
    events: list[ClientEvent] = Field(max_length=MAX_EVENTS_PER_POST)

    @model_validator(mode="after")
    def unique_event_ids(self) -> Self:
        if len({event.id for event in self.events}) != len(self.events):
            raise ValueError("Event IDs must be unique within a batch")

        return self


class ChangeReceipt(_StrictModel):
    accepted: list[_UUID]
