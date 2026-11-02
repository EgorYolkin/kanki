---
name: kanki-cards
description: Add, read, edit or delete flashcards in the user's Kanki spaced-repetition app through its sync server (https://kanki.ink, REST + MCP stdio). Use this skill whenever the user asks to add cards to Kanki, push flashcards/questions to their iPhone review app, dump notes as cards, check their card list, or sync study material into Kanki — even if they just say "закинь в канки", "add these cards", "сделай карточки" without naming the server.
---

# Kanki cards via sync server

Kanki stores all cards in a single revisioned snapshot on a self-hosted sync
server. There is no per-card API: every write replaces the whole snapshot and
must carry the revision the client last read. Respect that contract or you
will clobber the user's review history.

## Configuration

Two environment variables are required for every access path:

```bash
export KANKI_SERVER_URL=https://kanki.ink   # no trailing slash needed
export KANKI_TOKEN=<device-or-agent-token>  # bearer token; never commit it
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
2. Modify `data` in place. Keep every field you did not intend to change,
   especially `reviews` and `schedules` — they are the user's FSRS history.
3. `PUT /v1/snapshot` with `{schema_version: 1, base_revision: <revision from
   step 1>, data: <full modified data>}`.
4. A `409` response means someone else wrote first (usually the iPhone).
   Re-read the snapshot, redo the change on the fresh data, retry. Never
   blind-retry with the same `base_revision`.

Never construct `data` from scratch when the server already has cards:
always start from the current snapshot. An empty server returns
`revision: 0, data: null` — then `data` starts as
`{"cards": [], "reviews": [], "schedules": {}}`.

## Card schema

```json
{
  "id": "2621F15A-306C-435A-9680-AEEB602F272D",   // UUID, uppercase; generate fresh
  "question": "annals",                            // user-visible front
  "answer": "летопись",                            // user-visible back
  "createdAt": "2026-11-02T13:13:19Z"              // ISO-8601, UTC, seconds
}
```

Language follows the material: Russian answers for Russian-learning cards,
etc. Do not prefill `schedules[id]` — the app schedules new cards itself on
first review. Deleting a card: remove it from `cards` **and** its entries
from `schedules` (reviews may stay; they are a log).

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
KANKI_SERVER_URL=https://kanki.ink KANKI_TOKEN=… \
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
- Don't invent endpoints: there is no `/v1/cards`, no search, no delta sync.
  Snapshot read/put is the whole API for now.
