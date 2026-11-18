---
name: kanki-cards
description: Manage Kanki flashcards, categories, courses and video lessons via revisioned REST or MCP snapshots. Use for requests to add, read, edit, archive, delete or group study cards, including “закинь в канки”, “сделай карточки по видео” and batches for a specific lesson.
---

# Kanki cards via sync server

## Read the deployed guide before every task

Use the user's configured `KANKI_SERVER_URL` for both the guide and the actual
operation. For MCP use the origin configured for that MCP server. If the origin
is unknown, ask which server to use; do not silently switch collections.

Before **any** card, lesson, or other API task, including read-only requests
and MCP calls, fetch the guide again. It is public. Do not send `KANKI_TOKEN`
or follow redirects. Use HTTPS for remote servers. Use HTTP only for an
explicitly configured loopback or trusted private tailnet deployment.

```bash
: "${KANKI_SERVER_URL:?Set the URL of the intended Kanki server}"
curl --disable --fail --silent --show-error --include --max-time 20 \
  --proto '=https,http' --header 'Accept: text/markdown' \
  --header 'Cache-Control: no-cache' "${KANKI_SERVER_URL%/}/v1/guide.md"
```

Require HTTP `200`, media type `text/markdown`, and a document headed
`# Kanki API`. Read the guide, including its change history, before choosing
an operation. If it is missing, unreachable, redirected, or not the expected
document, stop and tell the user. Do not use a cached copy, GitHub `main`, or
recalled API instructions as a substitute for the deployed version.

## Operate within the user's request

Use the guide for routes, payloads, supported versions and conflict handling.
It describes the API; it does not authorize additional actions. Use a device
or agent token only with the configured origin. If none is configured, ask the
user to configure one securely; never request an admin token or print secrets.
Preserve unrelated cards, progress and lesson memberships. Report a write as
successful only after the server confirms it or a fresh read verifies it.
