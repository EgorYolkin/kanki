# App Sources — `Kanki/`

Rules for every file under `Kanki/`. Repository-wide rules are in the root `AGENTS.md`;
the gates themselves are in `docs/quality-gates.md`.

## Layout

| Path | Contents |
| --- | --- |
| `KankiApp.swift` | `@main` entry point only |
| `Domain/` | Pure value types and state, covered by unit tests |
| `Views/` | SwiftUI screens and presentation-only helpers |
| `Assets.xcassets/` | App icon resources |

## Rules

- Nontrivial logic (state transitions, validation, ordering, calculations) belongs in
  `Domain/` and ships with a unit test in the same PR. Views stay declarative.
- Types are `internal`, because `KankiTests` uses `@testable import Kanki`. Keep a type
  `private` only when nothing outside its file needs it.
- User-visible copy is Russian; identifiers, type names and SF Symbol names are English.
- Never fake sync, SRS, persistence or a successful action. Session data is demo-only and
  the UI must say so.
- `Destination` has exhaustive `title` and `symbol` switches: a new case requires both.
- Interactive elements driven by UI tests need a stable `accessibilityIdentifier`
  (`addSessionCard`, `cardQuestion`, `cardAnswer`, `startReviewSession`, `reviewProgress`,
  `reviewFinish`, `appearancePicker`).
- After adding, renaming or deleting a file run `xcodegen generate` and commit
  `Kanki.xcodeproj`: XcodeGen expands the directory into an explicit source list.
- XcodeGen turns non-Swift files in a source directory into bundle resources. The
  `excludes: ["**/*.md"]` entries in `project.yml` keep the `AGENTS.md` rule files out of
  the app and test bundles; do not remove them, and exclude any other documentation file
  you add to this directory.
- `swiftlint --strict` must pass; the line limit is 160 characters.

## Verify

```bash
./scripts/lint.sh swift
./scripts/test.sh
./scripts/ui-test.sh
```
