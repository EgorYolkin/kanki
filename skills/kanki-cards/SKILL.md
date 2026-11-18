---
name: kanki-cards
description: Manage Kanki flashcards, categories, courses and video lessons via revisioned REST or MCP snapshots. Use for requests to add, read, edit, archive, delete or group study cards, including “закинь в канки”, “сделай карточки по видео” and batches for a specific lesson.
---

# Kanki cards via sync server

Kanki stores every card in a single revisioned snapshot on a self-hosted sync
server. There is no per-card API: each write replaces the whole snapshot and
must carry the revision the client last read. Respect that contract or you
will clobber the user's review history.

## Configuration

Two environment variables are required for every access path:

```bash
export KANKI_SERVER_URL=https://kanki.host   # no trailing slash needed
export KANKI_TOKEN=<device-or-agent-token>   # bearer token; never commit it
```

If `KANKI_TOKEN` is unset, ask the user — do not guess and do not use the
admin token for card edits. Tokens are issued once via
`POST /v1/tokens {label}` (admin-only; on the server host it is SSH-only,
`/v1/tokens` is 404 through the public proxy).

Quick sanity check:

```bash
curl -s "$KANKI_SERVER_URL/v1/me" -H "Authorization: Bearer $KANKI_TOKEN"
# {"label":"...","role":"device"}  — anything else means wrong token/server
```

## Snapshot contract (the one rule that matters)

1. `GET /v1/snapshot` → `{revision, schema_version, data, updated_at}`.
2. Modify `data` in place. Keep every field you did not intend to change:
   `reviews` and `schedules` are the user's FSRS history, and `deck_renames`
   is the record of category renames (see below).
3. `PUT /v1/snapshot` with `{schema_version: 1, base_revision: <revision from
   step 1>, data: <full modified data>}`.
4. On `409` or a lost response, GET again. Keep the original IDs, timestamps,
   base data and intended changes. Compare them with the fresh snapshot: if
   already applied, report success without a PUT. Otherwise replay only the
   missing, nonconflicting changes on the fresh data using its revision.
   Never resend the old body with a newer revision. If the same field changed
   independently, or a previously known target disappeared, stop and report
   the conflict rather than overwriting an edit or resurrecting a deletion.

Never construct `data` from scratch when the server already has a snapshot:
always start from the current snapshot. A server with no snapshot returns
`revision: 0, data: null` — then `data` starts as
`{"snapshot_version": 3, "cards": [], "reviews": [], "schedules": {}, "deck_renames": []}`.

`schema_version` is the server's payload version (currently `1`); the app's
own format version lives inside `data.snapshot_version`.
Before **any** write, reject an unknown outer or inner version, including
on a retry. Missing inner version is legacy; valid versions are 1–4. Reject
`lessons` in a legacy snapshot and absent or invalid `lessons` in v4.

## Card schema (unchanged in v4)

```json
{
  "id": "2621F15A-306C-435A-9680-AEEB602F272D",   // UUID, uppercase; generate fresh
  "question": "annals",                            // user-visible front
  "answer": "летопись",                            // user-visible back
  "createdAt": "2026-11-02T13:13:19Z",              // ISO-8601, UTC, seconds
  "deck": "Японский",                              // category, optional
  "isArchived": false                               // archived cards stay out of review
}
```

- `deck` is the category (Anki deck). Omit it, `null` or `""` → «Без
  категории» (no category). The app trims surrounding whitespace.
- `isArchived: true` keeps the card, its reviews and its schedule, but hides
  it from the review queue and from category counters. Prefer archiving over
  deleting when the user says the card is no longer wanted.
- Do not prefill `schedules[id]` — the app schedules new cards itself on the
  first review. To physically delete a card, remove it, its reviews (by
  `cardID`), schedule and references in **every** lesson in one PUT.
  Archiving keeps all references; archived cards are not reviewed.

Write `question` and `answer` as ordinary strings containing Markdown source.
Use real line feeds for line breaks; preserve indentation, blank lines and
trailing LF. Serialize the object once, not by interpolating JSON strings.
After one JSON decode, `"a\nb"` is two lines; `"a\\nb"` is one line with a
literal backslash and `n`. Neither sync nor export decodes escapes again.
Never replace literal `\n` globally: examples and paths can contain it.

## Add a video lesson in one write

Before the first production v4 write, save the **full revisioned GET response**
privately outside the live store and confirm every writing app and agent is
v4-aware. A card export is not a snapshot backup. If any writer is still v3,
use v3 cards and Markdown only; do not enable lessons on that server yet.

1. GET once for the whole video. Check `schema_version` is 1 and the inner
   version is absent (legacy) or 1–4. Stop on unknown versions, `lessons`
   under a legacy version, or missing/invalid `lessons` in v4.
2. Trim the lesson title (required) and course. An empty course means no
   course: omit `course` or use `null`, never the reserved name `Без курса`.
   Course describes the source; `deck` describes the topic. An optional
   `source_url` must be absolute HTTP(S) with a host.
3. If the user supplied a lesson UUID, resolve that ID, not a title search.
   If it is missing, clarify rather than silently choosing another lesson.
   Otherwise match the exact trimmed `(course, title)` pair, including case;
   reuse its stored spelling. Identical titles in different courses are
   different lessons. For a new lesson allocate one UUID and `createdAt`
   once; empty lessons with `card_ids: []` are valid.
4. Allocate each new card's UUID and `createdAt` once for the operation.
   Add the new cards to `cards`; append their IDs to the selected lesson's
   `card_ids` in video order. To link an existing card, use its original ID.
   Each ID must exist and appear at most once per lesson; another lesson may
   reference the same card. Do not copy its schedule or reviews.
5. In that same PUT, enable `snapshot_version: 4` and add `lessons` when
   creating the first lesson. Otherwise retain the existing lessons. Never
   add `lessons` to v3 or downgrade v4, even after deleting its last lesson.
   Deleting a lesson removes only that lesson, not its cards or progress.
6. On retry follow the revision rule above. If someone created the same
   `(course, title)` concurrently, reuse their lesson ID when the original
   intent was creation by name. Check prepared card IDs and memberships
   separately; preserve existing rows, edits and order, append only missing
   links. Do not deduplicate by question text or allocate fresh retry IDs.

## Categories

Categories are derived from card names — there is no separate table or
endpoint, so creating a category means putting at least one card into it.

- **One category per card.** A card belongs to exactly one `deck` value.
- **Hierarchy lives in the name** via `::`, e.g. `Японский::Кандзи`. Picking
  a category in the app also covers its subcategories, and the app lists one
  row per distinct full name.
- **Name rules** (the app's own validation): non-empty after trimming, not
  `Без категории` (reserved), and no duplicate of an existing name. The app's
  text field additionally forbids typing `::`; an agent writing directly to
  the snapshot may still create hierarchical names — do it only when the user
  asks for nested categories.
- **Reuse existing names.** Read the snapshot first and copy an existing
  `deck` string verbatim instead of inventing a near-duplicate
  (`Японский` vs `японский` are two different rows).
- **Renames** are recorded in `data.deck_renames` as `{"from": "...", "to":
  "..."}`. When you rename a category for the user:
  1. rewrite every `cards[].deck` that equals `from` or starts with `from + "::"`
     (keeping the subcategory tail),
  2. append `{from, to}` to `deck_renames`,
  3. leave earlier rename entries in place.
  Never rename by silently rewriting `deck` alone — other devices replay
  `deck_renames` to keep their view consistent. A category disappears only
  when no card carries its name and no rename covers it; its cards fall back
  to «Без категории».
- **Moving cards between categories** is just assigning a different `deck`;
  that is not a rename and must not add a `deck_renames` entry.

## Path A: REST with curl (default)

Prefer this for one-off edits; it is transparent and dependency-free.

```bash
curl -s "$KANKI_SERVER_URL/v1/snapshot" -H "Authorization: Bearer $KANKI_TOKEN"
# edit data (jq or a small python script), then:
curl -s -X PUT "$KANKI_SERVER_URL/v1/snapshot" \
  -H "Authorization: Bearer $KANKI_TOKEN" -H "Content-Type: application/json" \
  -d @new-snapshot.json
```

Batch rule: one `get → edit → put` cycle for the whole batch, not per card —
each `PUT` bumps the revision and races the phone.

## Path B: MCP stdio

If the checkout is available (repo `server/`), the same operations come as
MCP tools — use them when the agent runtime speaks MCP:

```bash
KANKI_SERVER_URL=https://kanki.host KANKI_TOKEN=… \
  uv run --project <repo>/server kanki-mcp
```

Tools: `health`, `me`, `get_snapshot`, `put_snapshot(base_revision, data)`.
Same contract: `get_snapshot` first, pass its `revision` as `base_revision`.

## After writing

The configured app reconciles on activation, not continuously. For an
explicit pull use Settings → «Загрузить с сервера». If both sides changed,
resolve the conflict rather than promising immediate sync.

## Don'ts

- Don't put tokens, snapshot dumps or the server admin token in issues, PRs,
  commits or chat logs.
- Don't rewrite `reviews`/`schedules` "to clean up" — they encode FSRS memory
  state; damage is silent and permanent.
- Don't drop `deck_renames`, `snapshot_version` or `isArchived` when rewriting
  `data`: older values are replayed by other devices and by the app's decoder.
- Don't invent endpoints: there is no `/v1/cards`, no search, no delta sync.
  Snapshot read/put is the whole API for now.
