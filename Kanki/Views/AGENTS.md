# SwiftUI Views — `Kanki/Views/`

Presentation only. Behaviour lives in `Kanki/Domain/`; these rules keep the boundary.

## Rules

- No business rules here: no validation, filtering, ordering, counting or date maths.
  Extract it to `Domain` and test it instead.
- `@State` may hold only presentation state: sheet flags, selected item, revealed answer,
  transient submit guard. Derived values come from a domain model
  (for example `ReviewSessionState`, `CardDraft`, `SessionLog`).
- Keep Russian copy and `accessibilityIdentifier` values byte-stable: `KankiUITests`
  asserts exact strings, and changing a string requires updating the test in the same PR.
- Every tab keeps its own `NavigationStack`; destinations are registered with
  `.navigationDestination(for: Destination.self)`. Graph has no registration yet — add
  one before linking to a `Destination` from the graph tab.
- Do not add `#if DEBUG` fakes, placeholder success states or test-only branches.
- Empty states use `SectionIntro`; pushed screens use
  `.toolbarTitleDisplayMode(.inline)` (works on iOS 17+ and macOS 14+; the iOS-only
  `.navigationBarTitleDisplayMode` does not compile for macOS).
- Long Russian literals are the main reason for the 160-character lint limit; wrap the
  call arguments instead of shortening the copy.

## Verify

```bash
./scripts/lint.sh swift
./scripts/ui-test.sh
```
