# Repository Guidelines

## Project Overview

Kanki is a native SwiftUI iOS app (Swift 6, iOS 17+) for Markdown-based notes, typed relations, a knowledge graph, spaced repetition and eventual Anki `.apkg` interoperability. **Current code is only a navigation shell**: no real notes, persistence, SRS, import or sync. The future server is the source of truth; never present planned behavior as implemented. Read `tasks/plan.md` before changing scope and `tasks/todo.md` for stage status; GitHub issues track stage work (iOS stages #2–#9, macOS proposal #14).

Stage-1 constraints: label any sample data as demo; do not fake sync, SRS, persistence or successful actions. Do not freeze database/network contracts or the Anki note type before experiment Э1 (#3).

## Gitflow (required)

- `main` is release-only. Never commit/push directly to `main`; release through a `dev` → `main` PR.
- `dev` is integration-only. Start **each** feature, fix or documentation change in a separate `feature/<topic>`, `fix/<topic>` or `docs/<topic>` branch from current `origin/dev`, then PR into `dev`. Never commit/push directly to `dev`; never force-push shared branches.
- Check your branch before committing. Use `git fetch origin` then `git switch -c docs/<topic> origin/dev` (substitute type); local `dev` may lag. Existing branches created before this policy may target `dev` without history rewrites.
- Read `CODE_OF_CONDUCT.md` and `CONTRIBUTING.md`; the human running an agent is accountable for published output. Do not put secrets, private notes or Anki collections in issues, PRs or logs. Use `docs/agent-task-template.md` for handoffs and `.github/pull_request_template.md` for PRs.

## Architecture & Data Flow

`Kanki/KankiApp.swift` currently contains the entire app: `KankiApp` → `AppShell` (`TabView`) → four independent `NavigationStack`s for Learning, Notes, Graph and Settings. `Destination: Hashable` is the value-based route (`card`, `note`, `editor`, `search`, `library`, `merges`, `conflicts`), with exhaustive `title` and `symbol` switches. `NavigationLink(value:)` in the three list-based tabs resolves to `PlaceholderScreen` via `.navigationDestination(for:)`; **Graph has no destination registration**, so register one before adding links there. `SectionIntro` wraps `ContentUnavailableView` for empty states; all leaf destinations are placeholders.

There are no models, networking, database, async operations, dependency injection or state container yet. The *planned*, not implemented, path is note import → relations/edges and FTS5 → card display in WKWebView → swift-fsrs scheduling/review log → delta sync and `(guid, ord)` Anki progress mapping. Do not introduce a repository/view-model layer before its feature needs it.

## Key Directories

| Path | Purpose |
|---|---|
| `Kanki/` | All app Swift sources; currently one file. Add new app sources here. |
| `Kanki.xcodeproj/` | Tracked XcodeGen output; never hand-edit. |
| `tasks/` | Russian roadmap (`plan.md`) and acceptance/status ledger (`todo.md`); stage issues mirror progress. |
| `docs/`, `.github/` | Agent handoff and GitHub issue/PR templates; no CI workflow exists yet. |

## Development Commands

```bash
xcodegen generate  # required after adding/removing/renaming a source or resource under Kanki/
xcrun --sdk iphonesimulator swiftc -typecheck -parse-as-library \
  -target arm64-apple-ios17.0-simulator Kanki/KankiApp.swift
xcodebuild -project Kanki.xcodeproj -scheme Kanki -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
```

`-parse-as-library` is required for `@main`. When adding Swift files, typecheck all `Kanki/*.swift` together and regenerate the project: XcodeGen expands the directory into an **explicit** source list, so a new file can pass standalone typecheck yet be absent from the build. Scheme `Kanki` is discovered locally but no shared scheme is committed; if discovery fails, use `-target Kanki` or define a scheme in `project.yml`.

**Observed environment blocker:** the iOS Simulator runtime was downloaded, but `xcrun simctl`/`xcodebuild` now stop on an unaccepted Xcode license. The environment owner must review/accept it with `sudo xcodebuild -license`; do not accept legal terms on their behalf. Build and simulator run remain unverified (issue #2). Do not claim them from typecheck alone.

## Code Conventions & Common Patterns

- Swift 6 project mode; SwiftUI `View` value structs, `var body: some View`, `List { Section }`, `.navigationTitle(...)`; pushed placeholders use `.navigationBarTitleDisplayMode(.inline)`.
- `KankiApp`, `Destination` and `AppShell` have module visibility; screens/helpers are file-private `private struct`. Promote deliberately when sharing or testing. Types use PascalCase; properties and enum cases use camelCase/lowercase.
- User-visible strings are Russian literals; identifiers and SF Symbol names are English. `Destination` cases require updates to both exhaustive `title` and `symbol` switches. Tab labels and navigation titles are separate literals.
- `SectionIntro(symbol:title:detail:)` is the current empty-state pattern; it has no CTA. Settings shows unavailable sync as a secondary, non-interactive `Label("Сервер не подключён", systemImage: "icloud.slash")`, not a fake connect button.
- No error-handling, async, DI or app-state convention exists yet. For future actor-crossing models honor Swift 6 isolation/`Sendable`; choose patterns when implementing the actual feature, not as a speculative scaffold.
- Keep in-app copy and `tasks/` Russian; commit messages English.

## Important Files

| File | Role |
|---|---|
| `Kanki/KankiApp.swift` | Entry point, routes, tabs, empty state and placeholder screens. |
| `project.yml` | Sole build specification: app target `Kanki`, iOS 17, Swift 6, signing disabled, generated Info.plist. |
| `tasks/plan.md`, `tasks/todo.md` | Eight-stage plan and current stage acceptance ledger; cross-check stage issues. |
| `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` | Review/verification process and participant/agent conduct. |
| `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/agent-task.yml` | PR evidence and structured agent work requests. |

## Runtime/Tooling Preferences

macOS with Xcode 26.3 and XcodeGen 2.46.0. `project.yml` generates the committed `.xcodeproj` (objectVersion 77; Xcode 16+). No SwiftPM dependencies, package manager, resource catalog or checked-in Info.plist. Set Info.plist keys in `project.yml`; regenerate when adding resources. `CODE_SIGNING_ALLOWED: NO` supports simulator builds but not device distribution without signing configuration.

## Testing & QA

There is no test target, test suite, CI, linter, formatter or test runner. Current static gate is the `swiftc -typecheck -parse-as-library` command above; build/run must be attempted when the Xcode license is resolved. Verify changed user paths on a simulator: tab access, destination navigation, explanatory empty states and no misleading affordances. Report actual commands/results and blockers; never equate typecheck with a successful build.

When tests become necessary, create a sibling test directory/target in `project.yml`, **not under `Kanki/`** (its entire path belongs to the app target), then regenerate. Private screens require an intentional visibility change for direct tests. Update both `tasks/todo.md` and the relevant stage issue when acceptance criteria actually land; leave blocked work unchecked with the reason.
