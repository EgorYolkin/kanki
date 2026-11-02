# App Sources — `Kanki/`

Rules for every file under `Kanki/`. Repository-wide rules are in the root `AGENTS.md`;
the gates themselves are in `docs/quality-gates.md`.

## Layout

| Path | Contents |
| --- | --- |
| `KankiApp.swift` | `@main` entry point only |
| `Domain/` | Pure value types and state, covered by unit tests |
| `Views/` | SwiftUI screens and presentation-only helpers |
| `Server/` | HTTP client and token storage; no business rules |
| `Assets.xcassets/` | App icon resources |

## Platforms

One app target builds both platforms (`supportedDestinations: [iOS, macOS]`): iOS 17+ and
macOS 14+. The same sources ship on both; a screen must work on both.

- Platform differences live at the edges: `#if os(...)` is allowed in `KankiApp.swift`
  (scene modifiers), in `Views/SectionCommands.swift` (macOS menu) and around one
  platform-only modifier with a comment. Never fork a whole screen or domain type.
- Prefer a cross-platform API over a conditional: `.toolbarTitleDisplayMode(.inline)`
  works on both, while `.navigationBarTitleDisplayMode` is iOS-only.
- macOS-specific behavior (window size, menu shortcuts) belongs in the scene, not in
  screens, so iOS keeps its native navigation.

## Rules

- Nontrivial logic (state transitions, validation, ordering, calculations) belongs in
  `Domain/` and ships with a unit test in the same PR. Views stay declarative.
- Types are `internal`, because `KankiTests` uses `@testable import Kanki`. Keep a type
  `private` only when nothing outside its file needs it.
- User-visible copy is Russian; identifiers, type names and SF Symbol names are English.
- Never fake sync, SRS, server state or a successful action. Session data is demo-only;
  it is stored locally by `LocalCardStore`, store failures must surface, and the UI must
  not imply a server or SRS that does not exist. The manual server check and snapshot
  push/pull are real; a revision conflict must be shown, never merged silently.
- `Destination` has exhaustive `title` and `symbol` switches: a new case requires both.
- Interactive elements driven by UI tests need a stable `accessibilityIdentifier`
  (`addSessionCard`, `cardQuestion`, `cardAnswer`, `startReviewSession`, `reviewProgress`,
  `reviewFinish`, `appearance-system`, `appearance-light`, `appearance-dark`,
  `serverURL`, `serverToken`, `serverCheck`, `serverStatus`, `serverPush`, `serverPull`).
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
