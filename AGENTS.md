# Repository Guidelines

## Project Overview

Kanki is a native SwiftUI app (Swift 6) built from one shared code base for iOS 17+ and macOS 14+ — one app target, one set of sources — for Markdown-based notes, typed relations, a knowledge graph, spaced repetition and eventual Anki `.apkg` interoperability. **Current code is a navigation shell plus a locally stored demo and a self-hosted sync server**: session cards, their ratings and the appearance theme persist on device through `LocalCardStore`; the app can manually check the server and push or pull a whole revisioned snapshot. There are no real notes, SRS, import or automatic/delta sync. The server is the future source of truth; never present planned behavior as implemented. Read `tasks/plan.md` before changing scope and `tasks/todo.md` for stage status; GitHub issues track stage work (iOS stages #3–#9, macOS stage #14 with the shell slice in #52).

Stage-1 constraints: label any sample data as demo; do not fake automatic sync, SRS, server state or successful actions. Local persistence (`LocalCardStore`), the server connection and revision-guarded snapshot exchange are real; their failures are surfaced in the UI. Do not freeze the Anki note type before experiment Э1 (#3); the server snapshot contract is explicitly provisional.

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

## Directory Rules

Repository-wide rules are here. Directory rules add local constraints and are mandatory for any file under that path:

| Path | Local rules |
| --- | --- |
| `Kanki/` | `Kanki/AGENTS.md` — layering, visibility, accessibility identifiers |
| `Kanki/Domain/` | `Kanki/Domain/AGENTS.md` — pure testable state, 95 % gate |
| `Kanki/Views/` | `Kanki/Views/AGENTS.md` — declarative SwiftUI only |
| `KankiTests/` | `KankiTests/AGENTS.md` — unit-test conventions |
| `KankiUITests/` | `KankiUITests/AGENTS.md` — UI-test conventions and stability |
| `KankiMacUITests/` | `KankiMacUITests/AGENTS.md` — macOS UI tests: window and ⌘1–⌘4 |
| `scripts/` | `scripts/AGENTS.md` — single local/CI entry points |
| `.github/` | `.github/AGENTS.md` — workflow and template rules |
| `docs/` | `docs/AGENTS.md` — documentation rules |
| `tasks/` | `tasks/AGENTS.md` — roadmap and verified-only ledger |
| `experiments/` | `experiments/AGENTS.md` — reproducible Anki checks, no collections |

If two rules conflict, the directory rule wins for files inside that directory; the quality gates in `docs/quality-gates.md` win over both.

## Architecture & Data Flow

`Kanki/KankiApp.swift` contains only the `@main` entry point and the `--reset-store` launch hook; the persisted theme lives in `Kanki/Views/AppShell.swift` (`@AppStorage("appearance")` and `.preferredColorScheme`), so changing it in Settings re-renders the whole shell. `AppShell` builds the `TabView` from `AppSection` (`learning`, `notes`, `graph`, `settings`) with four independent `NavigationStack`s. The selected section is bound from `KankiApp`, so the tabs, the ⌘1–⌘4 menu on macOS (`SectionCommands`, compiled only under `#if os(macOS)`) and its `defaultSize` window share one source of truth. `Destination` (`note`, `editor`, `search`, `library`, `merges`, `conflicts`) is the value-based route with exhaustive `title` and `symbol` switches. `NavigationLink(value:)` in the three list-based tabs resolves to `PlaceholderScreen` via `.navigationDestination(for:)`; **Graph has no destination registration**, so register one before adding links there. `SectionIntro` wraps `ContentUnavailableView` for empty states; all leaf destinations are placeholders.

`Kanki/Domain/` holds the only testable state: `SessionCard` (question/answer, `createdAt`, `Codable`), `SessionReview` (`cardID`, `RecallRating` 1–4, timestamp), `SessionLog` (review count and last rating, restorable from a snapshot), `LearningSnapshot` (cards + reviews, `Codable`), `CardSearch` (query filtering), `CardDraft` (trimming and submit validation), `ReviewSessionState` (queue index, revealed answer, per-rating counts, summary rows) plus the presentation enums. `LearningScreen` owns cards and a `SessionLog`, loads them from `LocalCardStore` (JSON `LearningSnapshot` in `Application Support/Kanki/cards.json`, written atomically) and saves after every card or rating; read/write failures surface in an alert. `ReviewSessionScreen` walks `ReviewSessionState` one card at a time and ends with a session summary («Сеанс завершён»). The «Обучение» screen shows a floating action stack above the tab bar in the bottom-right corner: `addSessionCard` (44 pt plus) above `startReviewSession` (56 pt play), Liquid Glass on iOS 26 / macOS 26 and `.regularMaterial` below; search filters the list by question and answer. A running review queue is not persisted. Due dates, FSRS, import and sync do not exist.

`Kanki/Server/` holds the HTTP client and token storage: `SettingsScreen` keeps the URL in `@AppStorage`, stores the token in Keychain (with a sandbox-file fallback for unsigned simulators), checks `/v1/me`, and pushes or pulls `LearningSnapshot` manually with a `base_revision`; a `409` is shown as a conflict, never merged silently. `server/` is a FastAPI + SQLite WAL service with bearer tokens, `/v1/snapshot`, OpenAPI and MCP stdio tools; deployment is over SSH and the data path is HTTP inside Tailscale. There are no models beyond the demo, no app database, no background sync, no dependency injection or state container yet. The *planned*, not implemented, path is note import → relations/edges and FTS5 → card display in WKWebView → swift-fsrs scheduling/review log → delta sync and `(guid, ord)` Anki progress mapping. Do not introduce a repository/view-model layer before its feature needs it.

## Key Directories

| Path | Purpose |
| --- | --- |
| `Kanki/KankiApp.swift` | `@main` entry point and the `--reset-store` launch hook. |
| `Kanki/LocalCardStore.swift` | JSON snapshot of cards and reviews in Application Support; reset for UI tests. |
| `Kanki/Server/` | HTTP client and token storage; no UI or business rules. |
| `server/` | FastAPI + SQLite WAL sync server, MCP tools, tests and deploy unit. |
| `Kanki/Domain/` | Pure value types and state; the unit-test coverage scope. |
| `Kanki/Views/` | SwiftUI screens, shell, empty state and placeholders. |
| `Kanki/Assets.xcassets/` | App icon resources. |
| `KankiTests/` | XCTest unit target for `Kanki/Domain` (95 % line coverage gate). |
| `KankiUITests/` | XCUITest target for shell, session-card, review and settings paths. |
| `KankiMacUITests/` | XCUITest target for the macOS window and ⌘1–⌘4 section switching. |
| `scripts/` | Single local/CI entry points (`lint.sh`, `test.sh`, `ui-test.sh`, `macos-ui-test.sh`, `ci.sh`, coverage gate, simulator destination). |
| `.github/` | CI workflow, issue/PR templates. |
| `Kanki.xcodeproj/` | Tracked XcodeGen output; never hand-edit. |
| `tasks/` | Russian roadmap (`plan.md`) and acceptance/status ledger (`todo.md`); stage issues mirror progress. |
| `experiments/` | Reproducible Anki Э1 scripts and expected `.apkg` contents; outputs stay outside the repo. |
| `docs/` | Quality gates, agent handoff template. |
| `CHANGELOG.md` | Russian history of changes actually present in the branch; no planned work. |

## Development Commands

```bash
xcodegen generate        # required after adding/removing/renaming a source or resource under Kanki/
./scripts/lint.sh        # swiftlint --strict + markdownlint-cli2
./scripts/test.sh        # unit tests (KankiTests) + 95 % coverage gate
./scripts/ui-test.sh     # five KankiUITests on a simulator
./scripts/ci.sh          # full local contour, including iOS UI tests
xcodebuild -project Kanki.xcodeproj -scheme Kanki -configuration Debug \
  -destination 'platform=macOS' build   # native macOS app, ad-hoc signed
./scripts/macos-ui-test.sh             # macOS UI test: window and ⌘1–⌘4
```

`xcodegen generate` writes the shared `Kanki` scheme from `project.yml`: it runs `KankiTests` and `KankiUITests` and gathers coverage for the `Kanki` target. `project.yml` expands each source directory into an **explicit** file list, so a new file can pass a standalone typecheck yet be absent from the build — always regenerate and commit the project.

Simulator selection is automatic (`scripts/simulator_destination.sh` picks a booted iPhone or the newest available runtime). A stale simulator can abort tests with `Test crashed with signal kill`; `xcrun simctl shutdown <id>` then `xcrun simctl boot <id>` clears it. Report the actual command and result; a typecheck alone is not a build or test proof.

## Code Conventions & Common Patterns

- Swift 6 project mode; SwiftUI `View` value structs, `var body: some View`, `List { Section }`, `.navigationTitle(...)`; pushed screens use `.toolbarTitleDisplayMode(.inline)` (available in iOS 17 and macOS 14, unlike the iOS-only `.navigationBarTitleDisplayMode`).
- Layering: behavior in `Kanki/Domain` (pure, tested), rendering in `Kanki/Views`; views hold only presentation `@State` (sheet flags, selected card, transient submit guard). Types are `internal` so `@testable import Kanki` works; keep `private` only when nothing outside the file needs the type.
- User-visible strings are Russian literals; identifiers and SF Symbol names are English. `Destination` cases require updates to both exhaustive `title` and `symbol` switches. Tab labels and navigation titles are separate literals.
- `SectionIntro(symbol:title:detail:)` is the current empty-state pattern; it has no CTA. `SettingsScreen` is a real page: theme buttons (`appearance-system` / `appearance-light` / `appearance-dark`, checkmark plus selected trait) backed by `@AppStorage("appearance")` (`AppAppearance`: системное/светлое/тёмное) and applied in `AppShell` via `preferredColorScheme`, the only persisted user preference besides demo data, server URL/token fields, a real `/v1/me` connection check, manual snapshot push/pull with revision conflicts, a note that cards and ratings are stored on this device, version/build from `Info.plist`, and links to merges/conflicts. No fake connect button.
- No error-handling, async, DI or app-state convention exists yet. For future actor-crossing models honor Swift 6 isolation/`Sendable`; choose patterns when implementing the actual feature, not as a speculative scaffold.
- Platform differences stay at the edges: `#if os(...)` is allowed in the app entry point (`KankiApp` scene modifiers), in macOS-only commands (`SectionCommands`) and around a platform-only modifier — never to fork a whole screen or a domain type per platform. Prefer a cross-platform API (`.toolbarTitleDisplayMode`) over a conditional.
- Determinism in domain code: inject `Date`/`UUID` instead of reading them implicitly. Views never recompute a rule that `Domain` already owns.
- Keep in-app copy and `tasks/` Russian; commit messages English.

## Important Files

| File | Role |
| --- | --- |
| `Kanki/KankiApp.swift` | Entry point (`@main`) and `--reset-store` hook. |
| `Kanki/LocalCardStore.swift` | Atomic JSON snapshot of cards and reviews; `--reset-store` support. |
| `Kanki/Server/ServerClient.swift` | Bearer HTTP client for `/v1/me` and snapshot push/pull. |
| `Kanki/Server/ServerTokenStore.swift` | Keychain token with sandbox-file fallback for unsigned simulators. |
| `server/kanki_server/app.py` | FastAPI routes, auth, revision conflict. |
| `server/kanki_server/mcp_server.py` | MCP stdio tools over the REST API. |
| `docs/server-protocol.md` | Protocol, auth, revision and security decisions. |
| `Kanki/Views/AppShell.swift` | Tabs, navigation stacks and destination registration. |
| `Kanki/Domain/ReviewSessionState.swift` | Review queue: index, revealed answer, counts, summary. |
| `Kanki/Domain/CardDraft.swift` | New-card trimming and submit validation. |
| `KankiTests/Domain/` | One `<Type>Tests` file per domain type with behaviour; plain records are covered through their consumers. |
| `KankiUITests/SessionCardUITests.swift`, `KankiUITests/SettingsUITests.swift` | UI tests for navigation, session cards, search, persistence across relaunch, review queue, export, server settings and appearance. |
| `project.yml` | Sole build specification: one multi-platform app target (iOS/macOS), `KankiTests`, `KankiUITests`, `KankiMacUITests`, the `Kanki` scheme with coverage, the `Kanki macOS` scheme, Swift 6, simulator-only signing off, generated Info.plist. |
| `.swiftlint.yml`, `.markdownlint-cli2.jsonc` | Linter configuration; rules are explicit and changes need an issue. |
| `scripts/`, `.github/workflows/ci.yml` | Local and CI quality gates. |
| `docs/quality-gates.md` | Single source of truth for thresholds, commands and tool versions. |
| `tasks/plan.md`, `tasks/todo.md` | Eight-stage plan and current stage acceptance ledger; cross-check stage issues. |
| `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` | Review/verification process and participant/agent conduct. |
| `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/task.yml` | PR evidence and structured task requests. |

## Runtime/Tooling Preferences

macOS with Xcode 27.2 (Xcode 26.3 or newer also supported), XcodeGen 2.46.0, SwiftLint 0.65.1+, markdownlint-cli2 0.24.0 (Node 22), Python 3. `project.yml` generates the committed `.xcodeproj` (objectVersion 77; Xcode 16+) and the shared schemes. The app target declares `supportedDestinations: [iOS, macOS]`: iOS 17+ and macOS 14+ (macOS gets `LSApplicationCategoryType`, bundle ID `app.kanki.macos` and `CODE_SIGN_IDENTITY = "-"`; iOS-only `TARGETED_DEVICE_FAMILY`, `UIApplicationSceneManifest` and `UILaunchScreen` keys are scoped to `sdk=iphone*`). The app has no SwiftPM dependencies in this branch; `Kanki/Info.plist` is generated by XcodeGen from `project.yml` and committed. The Python server uses `uv` with `server/uv.lock`; it has no Node, Docker or resource-catalog requirement. Set Info.plist keys in `project.yml`; regenerate when adding resources. `CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]: NO` keeps simulator builds and UI tests signing-free while device builds keep normal signing: running from Xcode on a connected iPhone needs a Team selected on the Signing page, and `xcodegen generate` rewrites `project.pbxproj`, so re-select it or pass `DEVELOPMENT_TEAM=<id>` on the `xcodebuild` command line as `scripts/personal_team.py` does. Never commit team IDs, UDIDs or provisioning profiles.

## Testing & QA

Two test targets and two linters, all wired through `scripts/` and CI:

- `KankiTests` (XCTest, `@testable import Kanki`) covers `Kanki/Domain`; `scripts/test.sh` enforces **95 % line coverage** over that directory via `scripts/coverage_gate.py` and `xcrun xccov`. Views are excluded from the number on purpose and covered by UI tests instead.
- `KankiUITests` covers tabs, placeholder navigation, empty states, adding and rating a session card, card search, persistence of cards and ratings across relaunch, the review queue with summary, server settings and the appearance setting. `KankiTests/Server/ServerClientIntegrationTests` performs a real HTTP push/pull only when `KANKI_TEST_SERVER_URL` and `KANKI_TEST_TOKEN` are provided and is skipped otherwise.
- `KankiMacUITests` covers the macOS build via `./scripts/macos-ui-test.sh`: the window opens and ⌘1–⌘4 switch all four sections. The macOS app is signed ad-hoc (`Sign to Run Locally`), so it needs no Team ID; iOS-only `CODE_SIGNING_ALLOWED[sdk=iphonesimulator*]: NO` does not affect it.
- `.swiftlint.yml` runs with `--strict`; `.markdownlint-cli2.jsonc` lints every `.md`.
- `server/`: `./scripts/server-test.sh` runs `pytest` for FastAPI, SQLite WAL, token auth, revision conflicts and MCP tools; CI has a separate `Server and MCP tests` job.
- `.github/workflows/ci.yml` runs Markdown, SwiftLint, server tests, build/unit/coverage and the macOS job. iOS UI tests stay out of per-PR CI for speed; run `./scripts/ui-test.sh` locally for user-facing changes and before a release. `scripts/ci.sh` remains the full local contour including UI tests.

Gates for a change: `xcodegen generate` when sources/resources move, `./scripts/lint.sh`, `./scripts/server-test.sh`, `./scripts/test.sh`; add `./scripts/ui-test.sh` for user-facing changes and before release (or run `./scripts/ci.sh` once locally). Verify changed user paths on the simulator; report actual commands/results and blockers, never equate typecheck with a successful build or test. Keep test directories siblings of `Kanki/` in `project.yml` (the whole `Kanki/` path belongs to the app target) and regenerate. Update both `tasks/todo.md` and the relevant stage issue when acceptance criteria actually land; leave blocked work unchecked with the reason.
