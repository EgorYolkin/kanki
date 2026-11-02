# Domain Layer — `Kanki/Domain/`

Pure, testable state and value types. This is the only code subject to the 95 % line
coverage gate (see `docs/quality-gates.md`).

## Rules

- No I/O: no files, network, `UserDefaults`, notifications or timers.
- SwiftUI is allowed only for presentation values (`Color`, `ColorScheme`). No `View`.
- Determinism: accept `Date` and `UUID` as parameters with defaults
  (`record(_:at: Date = Date())`), never read the clock implicitly.
- No randomness, no `sleep`, no global mutable state.
- Types are `internal`; `private` would make them invisible to `@testable import Kanki`.
- Every type with behaviour ships with `<Type>Tests` in `KankiTests/Domain/` in the same
  PR; plain records are covered through their consumers.
- State changes are expressed as mutating methods with a single source of truth; do not
  duplicate a rule in a view.
- Prefer value types and `Equatable`; keep the API minimal — add a member only when a
  consumer or a test needs it.

## Verify

```bash
./scripts/test.sh   # unit tests + coverage gate (95 % of this directory)
```
