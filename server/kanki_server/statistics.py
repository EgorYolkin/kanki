from collections import Counter
from collections.abc import Iterable, Iterator
from datetime import UTC, date, datetime, timedelta
from itertools import chain
from typing import Annotated, Any, Literal, Self
from unicodedata import normalize
from uuid import UUID
from zoneinfo import ZoneInfo

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


MAX_EVENTS_BYTES = 256 * 1024
MAX_BATCH_SIZE = 100
MAX_TOPIC_LENGTH = 256
CALENDAR_DAYS = 365
UNCATEGORIZED = "Без категории"
ONE_DAY = timedelta(days=1)


def _timestamp(value: object) -> datetime:
    if not isinstance(value, str) or len(value) > 64 or value[10:11] not in ("T", " "):
        raise ValueError("expected ISO 8601 timestamp")

    instant = datetime.fromisoformat(value)
    if instant.tzinfo is None:
        raise ValueError("expected timezone offset")
    try:
        instant = instant.astimezone(UTC)
    except OverflowError as error:
        raise ValueError("timestamp out of range") from error
    # Leave room to convert this instant to any reporting time zone.
    if not 1 < instant.year < 9999:
        raise ValueError("timestamp out of range")

    return instant


class StatisticsEvent(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: UUID
    kind: Literal["visit", "imported_review"]
    timestamp: datetime
    rating: Annotated[int, Field(strict=True, ge=1, le=4)] | None = None
    topic: Annotated[str, Field(max_length=MAX_TOPIC_LENGTH)] | None = None

    @field_validator("timestamp", mode="before")
    @classmethod
    def validate_timestamp(cls, value: object) -> datetime:
        return _timestamp(value)

    @model_validator(mode="after")
    def validate_kind(self) -> Self:
        if self.kind == "visit" and (self.rating is not None or self.topic is not None):
            raise ValueError("visit has no rating or topic")
        if self.kind == "imported_review" and self.rating is None:
            raise ValueError("imported review requires a rating")
        return self


class StatisticsEvents(BaseModel):
    model_config = ConfigDict(extra="forbid")

    events: list[StatisticsEvent] = Field(min_length=1, max_length=MAX_BATCH_SIZE)


class StatisticsDay(BaseModel):
    date: date
    visits: int
    reviews: int


class StatisticsTopic(BaseModel):
    name: str
    count: int


class Statistics(BaseModel):
    totalReviews: int
    streakDays: int
    days: list[StatisticsDay]
    ratings: list[int]
    topics: list[StatisticsTopic]


def _topic_name(value: object) -> str:
    return (normalize("NFC", value.strip()) if isinstance(value, str) else "") or UNCATEGORIZED


def _card_id(value: object) -> UUID | None:
    if isinstance(value, str) and len(value) == 36:
        try:
            return UUID(value)
        except ValueError:
            pass
    return None


type Activity = tuple[str, int | None, str | None]


def _manual_reviews(snapshot: dict[str, Any]) -> Iterator[Activity]:
    reviews = snapshot.get("reviews")
    if not isinstance(reviews, list):
        return

    decks: dict[UUID, str] = {}
    cards = snapshot.get("cards")
    if isinstance(cards, list):
        for card in cards:
            if isinstance(card, dict) and (card_id := _card_id(card.get("id"))) is not None:
                decks[card_id] = _topic_name(card.get("deck"))

    for review in reviews:
        if not isinstance(review, dict):
            continue
        rating = review.get("rating")
        card_id = _card_id(review.get("cardID"))
        timestamp = review.get("reviewedAt")
        if (card_id is not None and type(rating) is int and 1 <= rating <= 4
                and isinstance(timestamp, str)):
            yield timestamp, rating, decks.get(card_id)


def calculate_statistics(
    snapshot: dict[str, Any], events: Iterable[Activity], zone: ZoneInfo, today: date
) -> Statistics:
    """
    Count reviews from the current snapshot and committed events in local calendar days.
    Visits affect the calendar but do not start or extend a review streak.
    """

    start = today - (CALENDAR_DAYS - 1) * ONE_DAY
    reviews: Counter[date] = Counter()
    visits: Counter[date] = Counter()
    topics: Counter[str] = Counter()
    ratings = [0, 0, 0, 0]
    for timestamp, rating, topic in chain(_manual_reviews(snapshot), events):
        try:
            day = _timestamp(timestamp).astimezone(zone).date()
        except ValueError:
            # Snapshot v1 stores arbitrary JSON; a bad historical row is not a review.
            continue
        if day > today:
            continue
        if rating is None:
            if day >= start:
                visits[day] += 1
        else:
            reviews[day] += 1
            ratings[rating - 1] += 1
            topics[_topic_name(topic)] += 1

    streak = 0
    day = today if today in reviews else today - ONE_DAY
    while day in reviews:
        streak += 1
        day -= ONE_DAY

    calendar = (start + offset * ONE_DAY for offset in range(CALENDAR_DAYS))
    return Statistics(
        totalReviews=sum(ratings),
        streakDays=streak,
        days=[StatisticsDay(date=day, visits=visits[day], reviews=reviews[day]) for day in calendar],
        ratings=ratings,
        topics=[StatisticsTopic(name=name, count=count)
                for name, count in sorted(topics.items(), key=lambda item: (-item[1], item[0]))],
    )
