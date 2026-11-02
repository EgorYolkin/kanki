# Scripts — `scripts/`

Local entry points that CI calls verbatim. `docs/quality-gates.md` is the contract.

## Rules

- Bash: `set -euo pipefail` and `cd "$(dirname "$0")/.."`. No `|| true`,
  no silent error swallowing.
- Python 3 standard library only; no virtualenv or third-party packages.
- Actions must be idempotent and safe to re-run; generated output goes under `build/`
  (ignored by git).
- Never hardcode device UDIDs, Team IDs, bundle IDs or credentials. Simulator choice comes
  from `simulator_destination.sh`.
- Exit codes are meaningful: `0` success, non-zero failure, and the coverage gate uses
  `1` for "below threshold" and `2` for "no coverage data".
- CI runs these files, not inline copies. If a check becomes gating, add it to
  `.github/workflows/ci.yml` and document it.
- A new script requires an entry in `docs/quality-gates.md` and a mention in the PR.
- `macos-ui-test.sh` is the only macOS runner: it builds the native app and runs
  `KankiMacUITests` through the `Kanki macOS` scheme. `ci.sh` calls it, and CI has a
  separate macOS job with the same commands.

## Verify

```bash
./scripts/ci.sh
```
