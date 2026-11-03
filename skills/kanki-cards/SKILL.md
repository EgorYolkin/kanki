---
name: kanki-cards
description: Add, read, edit, archive or delete flashcards in the user's Kanki spaced-repetition app through its sync server (https://kanki.host, REST + MCP stdio), including assigning cards to categories. Use this skill whenever the user asks to add cards to Kanki, put flashcards into a category or deck, push study material to their iPhone review app, dump notes as cards, check their card list, or move cards between categories — even if they just say "закинь в канки", "add these cards", "сделай карточки" without naming the server.
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
4. A `409` response means someone else wrote first (usually the iPhone).
   Re-read the snapshot, redo the change on the fresh data, retry. Never
   blind-retry with the same `base_revision`.

Never construct `data` from scratch when the server already has cards:
always start from the current snapshot. A server with no snapshot returns
`revision: 0, data: null` — then `data` starts as
`{"snapshot_version": 3, "cards": [], "reviews": [], "schedules": {}, "deck_renames": []}`.

`schema_version` is the server's payload version (currently `1`); the app's
own format version lives inside `data.snapshot_version`.

## Card schema (`snapshot_version: 3`)

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
  first review. Deleting a card: remove it from `cards` **and** its entry
  from `schedules` (reviews may stay; they are a log).

Media, HTML and rich text are out of scope: the app renders plain question
and answer strings.

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

The iPhone does not poll; changes appear after the user pulls in Settings →
«Загрузить с сервера» (or an empty launch). Say so instead of promising
instant sync.

## Don'ts

- Don't put tokens, snapshot dumps or the server admin token in issues, PRs,
  commits or chat logs.
- Don't rewrite `reviews`/`schedules` "to clean up" — they encode FSRS memory
  state; damage is silent and permanent.
- Don't drop `deck_renames`, `snapshot_version` or `isArchived` when rewriting
  `data`: older values are replayed by other devices and by the app's decoder.
- Don't invent endpoints: there is no `/v1/cards`, no search, no delta sync.
  Snapshot read/put is the whole API for now.
