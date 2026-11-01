# Repository Guidelines

## Project Overview

Kanki is a native SwiftUI iOS app (Swift 6, iOS 17+) for Markdown-based notes, typed relations, a knowledge graph, spaced repetition and eventual Anki `.apkg` interoperability. **Current code is a navigation shell plus a locally stored demo**: session cards, their ratings and the appearance theme persist on device; there are no real notes, SRS, import, server or sync. The future server is the source of truth; never present planned behavior as implemented. Read `tasks/plan.md` before changing scope and `tasks/todo.md` for stage status; GitHub issues track stage work (iOS stages #3–#9, macOS proposal #14).

Stage-1 constraints: label any sample data as demo; do not fake sync, SRS, server state or successful actions. Local persistence must be real (`LocalCardStore`) and must surface write failures. Do not freeze database/network contracts or the Anki note type before experiment Э1 (#3).

## Gitflow (required)

- `main` is release-only. Never commit/push directly to `main`; release through a `dev` → `main` PR.
- `dev` is integration-only. Start **each** feature, fix or documentation change in a separate `feature/<topic>`, `fix/<topic>` or `docs/<topic>` branch from current `origin/dev`, then PR into `dev`. Never commit/push directly to `dev`; never force-push shared branches.
- Check your branch before committing. Use `git fetch origin` then `git switch -c docs/<topic> origin/dev` (substitute type); local `dev` may lag. Existing branches created before this policy may target `dev` without history rewrites.
- Read `CODE_OF_CONDUCT.md` and `CONTRIBUTING.md`; the human running an agent is accountable for published output. Do not put secrets, private notes or Anki collections in issues, PRs or logs. Use `docs/agent-task-template.md` for handoffs and `.github/pull_request_template.md` for PRs.

## Issue-first delivery (required)

- Before any code, documentation, build or workflow change, **create or choose a dedicated GitHub issue for that task**. A roadmap-stage issue may be the parent, but does not replace a task issue. Do not start implementation from a chat request alone. For sensitive reports use GitHub's private security reporting channel first; never put secrets or personal data in a public issue.
- Write the issue's goal, scope/non-goals, dependencies, an ordered checkbox plan, observable acceptance criteria and verification method **before editing**. Link the issue from the branch/commits where practical (e.g. `refs #21`). Keep its checkboxes and comments current as work progresses; record actual verification and blockers, never check an unverified item.
- Commit on the dedicated branch as work proceeds, referencing the issue (`refs #21`). **After** implementation and verification, push and open a PR targeting `dev` with `Closes #N` (release: link the release issue in `dev` → `main`). The PR lists commits/changes, actual verification, outstanding risks and deliberately deferred work. A blocked/partial task stays open; split remaining work into a new linked issue before claiming completion.
- Review/merge closes the task issue; confirm GitHub actually closed it, otherwise close it with a link to the merged PR. Update `tasks/todo.md` and the stage issue when a stage is accepted. Issue/PR templates live under `.github/`; follow `CONTRIBUTING.md` for the complete sequence. Existing pre-policy PRs need not be rewritten.

## Architecture & Data Flow

`Kanki/KankiApp.swift` currently contains the entire app: `KankiApp` → `AppShell` (`TabView`) → four independent `NavigationStack`s for Learning, Notes, Graph and Settings. `Destination: Hashable` is the value-based route (`card`, `note`, `editor`, `search`, `library`, `merges`, `conflicts`), with exhaustive `title` and `symbol` switches. `NavigationLink(value:)` in the three list-based tabs resolves to `PlaceholderScreen` via `.navigationDestination(for:)`; **Graph has no destination registration**, so register one before adding links there. `SectionIntro` wraps `ContentUnavailableView` for empty states; all leaf destinations are placeholders.

`LearningScreen` owns the stage-1 demo: `SessionCard` (id, question, answer, createdAt) and `SessionReview` (`RecallRating` 1–4 plus timestamp), loaded from and written to `LocalCardStore` — a Codable `LearningSnapshot` in `Application Support/Kanki/cards.json`, written atomically. Cards, ratings and the theme survive relaunch; a running review queue does not. A write/read failure surfaces in an alert. `ReviewSessionScreen` (`startReviewSession`, `reviewFinish`) walks the stored cards as a queue and shows a session summary («Сеанс завершён»). Due dates, FSRS, import and sync do not exist.

There are no models, networking, database, async operations, dependency injection or state container yet. The *planned*, not implemented, path is note import → relations/edges and FTS5 → card display in WKWebView → swift-fsrs scheduling/review log → delta sync and `(guid, ord)` Anki progress mapping. Do not introduce a repository/view-model layer before its feature needs it.

## Key Directories

| Path | Purpose |
|---|---|
| `Kanki/` | All app Swift sources and `Assets.xcassets` (AppIcon). Add new app sources here. |
| `KankiUITests/` | XCUITest target `KankiUITests` for shell, session-card and settings paths; separate from the app target. |
| `Kanki.xcodeproj/` | Tracked XcodeGen output; never hand-edit. |
| `tasks/` | Russian roadmap (`plan.md`) and acceptance/status ledger (`todo.md`); stage issues mirror progress. |
| `experiments/` | Reproducible Anki Э1 scripts and expected `.apkg` contents; outputs stay outside the repo. |
| `docs/`, `.github/` | Agent handoff and GitHub issue/PR templates; no CI workflow exists yet. |
| `CHANGELOG.md` | Russian history of changes actually present in the branch; no planned work. |

## Development Commands

```bash
xcodegen generate  # required after adding/removing/renaming a source or resource under Kanki/
xcrun --sdk iphonesimulator swiftc -typecheck -parse-as-library \
  -target arm64-apple-ios17.0-simulator Kanki/KankiApp.swift
xcodebuild -project Kanki.xcodeproj -scheme Kanki -configuration Debug \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild test -project Kanki.xcodeproj -scheme Kanki \
  -destination 'platform=iOS Simulator,id=371F437D-173C-4965-9F4C-4D0216D182C8' \
  CODE_SIGNING_ALLOWED=NO  # iPhone 17e; use any available booted simulator id
```

`-parse-as-library` is required for `@main`. When adding Swift files, typecheck all `Kanki/*.swift` together and regenerate the project: XcodeGen expands the directory into an **explicit** source list, so a new file can pass standalone typecheck yet be absent from the build. Scheme `Kanki` is discovered locally but no shared scheme is committed; if discovery fails, use `-target Kanki` or define a scheme in `project.yml`.

Build and UI tests are verified on iPhone 17e Simulator (iOS 26.3.1) with Xcode 27.2: `xcodebuild test` runs two `SessionCardUITests` (shell navigation and the session-card/rating path). A stale simulator can abort both tests with `Test crashed with signal kill`; `xcrun simctl shutdown <id>` then `xcrun simctl boot <id>` clears it. Report the actual command and result; a typecheck alone is not a build or test proof.

## Code Conventions & Common Patterns

- Swift 6 project mode; SwiftUI `View` value structs, `var body: some View`, `List { Section }`, `.navigationTitle(...)`; pushed placeholders use `.navigationBarTitleDisplayMode(.inline)`.
- `KankiApp`, `Destination` and `AppShell` have module visibility; screens/helpers are file-private `private struct`. Promote deliberately when sharing or testing. Types use PascalCase; properties and enum cases use camelCase/lowercase.
- User-visible strings are Russian literals; identifiers and SF Symbol names are English. `Destination` cases require updates to both exhaustive `title` and `symbol` switches. Tab labels and navigation titles are separate literals.
- `SectionIntro(symbol:title:detail:)` is the current empty-state pattern; it has no CTA. `SettingsScreen` is a real page: an appearance picker (`appearancePicker`) backed by `@AppStorage("appearance")` (`AppAppearance`: системное/светлое/тёмное, applied in `KankiApp` via `preferredColorScheme`), a non-interactive `Label("Сервер не подключён", systemImage: "icloud.slash")` with an explanation of when sync arrives, a note that cards/ratings are stored on this iPhone while no server is configured, version/build from `Info.plist`, and links to merges/conflicts. No fake connect button.
- No error-handling, async, DI or app-state convention exists yet. For future actor-crossing models honor Swift 6 isolation/`Sendable`; choose patterns when implementing the actual feature, not as a speculative scaffold.
- Keep in-app copy and `tasks/` Russian; commit messages English.

## Important Files

| File | Role |
|---|---|
| `Kanki/KankiApp.swift` | Entry point, routes, tabs, empty states, placeholder screens, the session-card/rating demo and the floating review button. |
| `Kanki/LocalCardStore.swift` | Codable card/review models and the JSON snapshot in Application Support; `--reset-store` clears it for tests. |
| `KankiUITests/SessionCardUITests.swift` | UI tests for tabs, placeholder navigation, session cards and persistence across relaunch. |
| `project.yml` | Sole build specification: app target `Kanki` and `KankiUITests`, iOS 17, Swift 6, signing disabled, generated Info.plist. |
| `tasks/plan.md`, `tasks/todo.md` | Eight-stage plan and current stage acceptance ledger; cross-check stage issues. |
| `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` | Review/verification process and participant/agent conduct. |
| `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/task.yml` | PR evidence and structured task requests. |

## Runtime/Tooling Preferences

macOS with Xcode 27.2 (Xcode 26.3 or newer also supported) and XcodeGen 2.46.0. `project.yml` generates the committed `.xcodeproj` (objectVersion 77; Xcode 16+). No SwiftPM dependencies, package manager, resource catalog or checked-in Info.plist. Set Info.plist keys in `project.yml`; regenerate when adding resources. `CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]: NO` keeps simulator builds and UI tests signing-free while device builds keep normal signing: running from Xcode on a connected iPhone needs a Team selected on the Signing page, and `xcodegen generate` rewrites `project.pbxproj`, so re-select it or pass `DEVELOPMENT_TEAM=<id>` on the `xcodebuild` command line as `scripts/personal_team.py` does. Never commit team IDs, UDIDs or provisioning profiles.

## Testing & QA

XCUITest target `KankiUITests` exists; there is no unit-test target, CI, linter or formatter. Gates for a change: `xcodegen generate` when sources/resources move, `swiftc -typecheck -parse-as-library`, `xcodebuild build`, and `xcodebuild test` for user-visible changes (see commands above). Run tests on an available booted simulator; if the whole suite dies with `signal kill`, reboot the simulator rather than re-running blindly. Tests that depend on stored cards launch with the `--reset-store` argument to start from an empty snapshot. Verify changed user paths on the simulator: tab access, destination navigation, explanatory empty states and no misleading affordances. Report actual commands/results and blockers; never equate typecheck with a successful build or test.

Keep the test target a sibling directory in `project.yml`, **not under `Kanki/`** (its entire path belongs to the app target), then regenerate. Private screens require an intentional visibility change for direct tests. Update both `tasks/todo.md` and the relevant stage issue when acceptance criteria actually land; leave blocked work unchecked with the reason.
