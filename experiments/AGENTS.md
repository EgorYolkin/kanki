# Anki Experiments — `experiments/`

Reproducible checks against a real Anki backend (Э1 and later).

## Rules

- Every experiment states the exact Anki backend version it was run against and the
  expected `.apkg` contents.
- Scripts are reproducible from a clean checkout; pin dependency versions.
- Outputs (`.apkg`, `collection.anki2`, logs) stay outside the repository — write them to
  a temporary directory and delete them.
- Never commit real collections, private notes, credentials or AnkiWeb data.
- Do not freeze the eight-field note type or sync contracts before Э1 acceptance; record
  what passed, what failed and what was not verified.
- Markdown notes must pass `./scripts/lint.sh markdown`.
