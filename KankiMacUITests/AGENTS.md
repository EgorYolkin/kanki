# macOS UI Tests — `KankiMacUITests/`

XCUITest target for the native macOS build of `Kanki`. The iOS target is `KankiUITests/`;
these tests run a real window on the Mac, not a simulator.

## Rules

- Run with `./scripts/macos-ui-test.sh` (scheme `Kanki macOS`, `-destination 'platform=macOS'`).
- Assert user-visible Russian copy and keyboard behaviour, never view internals: the shell
  opens a window, the hidden placeholder sections ignore ⌘2/⌘3 until the Settings toggles
  enable them, and ⌘1–⌘4 switch the visible sections from `SectionCommands`.
- Section shortcuts come from `AppSection.rawValue`. If those numbers change, this target
  and `AppSectionTests` must change in the same PR.
- Keep the number of macOS tests small: each launch costs tens of seconds and the value is
  in proving the app actually runs natively.
- macOS-only concerns belong here (window size, menu commands); shared shell behaviour stays
  in `KankiUITests` so it is verified on iOS too.

## Verify

```bash
./scripts/macos-ui-test.sh
```
