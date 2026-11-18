# Anki Experiments — `experiments/`

Reproducible checks against a real Anki backend (Э1 and later).

## Rules

- Every experiment states the exact Anki backend version it was run against and the
  expected `.apkg` contents.
- Scripts are reproducible from a clean checkout; pin dependency versions.
- Outputs (`.apkg`, `collection.anki2`, logs) stay outside the repository — write them to
  a temporary directory and delete them.
- Never commit real collections, private notes, credentials or AnkiWeb data.
- Use the [accepted Anki exchange v1 contract](../docs/anki-exchange-v1.md) as the
  baseline. Record what passed, what failed and what was not verified; do not treat
  the exchange profile as a sync contract.
- Markdown notes must pass `./scripts/lint.sh markdown`.
