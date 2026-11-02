# Unit Tests — `KankiTests/`

XCTest target for `Kanki/Domain`. Coverage below 95 % fails the build gate.

## Rules

- One `<Type>Tests` file per domain type **with behaviour**, mirroring `Kanki/Domain/`;
  see `KankiTests/Domain/`. A plain record such as `SessionReview` has nothing to assert
  on its own and is covered through its consumers (`SessionLog`, `ReviewSessionState`).
- Import with `@testable import Kanki`; the tested types stay `internal`.
- Test observable behaviour, boundaries and error paths — not private helpers or the
  exact implementation. Avoid asserting a value that is merely returned unchanged.
- Determinism: inject fixed `Date` values and `UUID`s; never depend on the clock, locale,
  device or launch order.
- No UI, network, file system, `UserDefaults` or screen-size dependencies in this target.
- Never lower the gate, never `XCTSkip` instead of fixing a failure, never delete a test
  to make CI green; fix the code or open an issue.
- The gate is aggregate — 95 % of the whole `Kanki/Domain` directory — so a small
  uncovered type can still slip through. Add the test because the rule says so, never
  because the number went red.

## Verify

```bash
./scripts/test.sh   # runs only this target and applies the coverage gate
```
