# GitHub Configuration — `.github/`

Issue/PR templates and the CI workflow.

## Workflow rules

- Minimal permissions (`contents: read`); never `write-all`.
- Pin action major versions (`actions/checkout@v4`) — no moving `main`/`master` refs.
- Set `concurrency` with `cancel-in-progress: true` so superseded runs stop.
- No `continue-on-error`, `|| true` or skipped steps to make a red run green.
- No secrets are needed by this project; do not add tokens for coverage services or
  deployment without a dedicated issue.
- CI must call the scripts from `scripts/` so local and CI commands cannot drift.
- Upload `build/*.xcresult` on failure only; artifacts expire.
- Changing a gate, runner or trigger requires an issue and an update to
  `docs/quality-gates.md`.

## Templates

- `ISSUE_TEMPLATE/task.yml` and `pull_request_template.md` are Russian and mandatory:
  goal, boundaries, plan, acceptance criteria, verification, risks.
- Templates must never imply unimplemented behaviour or ask for private data; direct
  security reports to GitHub private vulnerability reporting.
