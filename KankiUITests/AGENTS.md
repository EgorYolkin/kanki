# UI Tests — `KankiUITests/`

XCUITest target for user-visible paths. Gates are described in `docs/quality-gates.md`.

## Rules

- Verify user scenarios end to end: tab access, destination navigation, empty states,
  session-card rating, the review queue and its summary, honest settings statuses.
- Classes are `@MainActor`; drive the app through `XCUIApplication()`, not through
  internal APIs.
- Prefer `waitForExistence(timeout:)` and `accessibilityIdentifier` over positional
  queries; never use `sleep`.
- Assert exact Russian copy only where it is the contract under test. When a string
  changes, update the assertion in the same PR.
- Synthetic data only ("Почему небо голубое?", "Что такое Km?"). Never attach
  screenshots containing personal notes or real Anki collections.
- Tests must pass on a clean simulator; a stale simulator failing with
  `signal kill` is an environment issue — reboot it instead of re-running blindly.
- Do not weaken or delete a check to make CI pass; report a real defect instead.

## Verify

```bash
./scripts/ui-test.sh
```
