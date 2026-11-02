# Documentation — `docs/`

## Rules

- Russian prose; identifiers, commands and file names stay English.
- `docs/quality-gates.md` is the single source of truth for checks, thresholds and tool
  versions. Other documents link to it instead of repeating commands.
- Link the GitHub issue for any behaviour that is planned rather than implemented.
  Never describe a placeholder as working.
- `docs/agent-task-template.md` must stay consistent with
  `.github/ISSUE_TEMPLATE/task.yml`.
- Every Markdown file must pass `./scripts/lint.sh markdown` (`markdownlint-cli2`,
  `.markdownlint-cli2.jsonc`).
- Relative links are preferred; do not link to local absolute paths or `file://` URLs.
