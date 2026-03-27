# Learnings — hushcore-views-refactor

## Project Structure
- Single Xcode target (not SPM packages) — file moves don't affect imports
- 77 test files, 600+ test cases via Swift Testing framework
- Build via: `make build`, test via: `make test`, format via: `make fmt`
- DerivedData at `/tmp/hush-dd`, SPM at `/tmp/hush-spm`

## Key Patterns
- AppContainer already has `extension AppContainer` in separate file (PreviewSupport.swift)
- @Published properties MUST stay in AppContainer main file
- HushCore must remain Foundation-only (no SwiftUI imports)
- Dark mode only, use HushColors/HushSpacing/HushTypography theme tokens

## File Locations
- AppContainer: `Hush/AppContainer.swift` (2833 lines)
- ThemeChrome: `Hush/Views/ThemeChrome.swift` (832 lines)
- ProviderSettingsView: `Hush/Views/Settings/ProviderSettingsView.swift` (1735 lines)
- AgentSettingsView: `Hush/Views/Settings/AgentSettingsView.swift` (718 lines)
- ComposerDock: `Hush/Views/Chat/ComposerDock.swift` (519 lines)
- QuickBarComposer: `Hush/Views/Chat/QuickBar/QuickBarComposer.swift` (604 lines)
- ChatConfigPopover: `Hush/Views/Chat/ChatConfigPopover.swift` (512 lines)
- Orphan (to delete): `HushCore/PerfTrace.swift` (16 lines stub)
- Real PerfTrace: `Hush/HushCore/PerfTrace.swift` (135 lines, keep untouched)

## Task 2 Notes
- Root-level orphan `HushCore/PerfTrace.swift` was deleted successfully.
- No `HushCore/PerfTrace` reference remained in `Hush.xcodeproj/project.pbxproj` (`grep -c` returned `0`).
- `make build` succeeded after deletion; real `Hush/HushCore/PerfTrace.swift` remained present and unchanged.

## Xcode Project File
- `Hush.xcodeproj/project.pbxproj` MUST be updated for every new/deleted file
- Use `PBXBuildFile` + `PBXFileReference` + group membership pattern

## Guardrails
- NO ViewModel pattern
- NO changes to RequestCoordinator.swift internals
- NO changes to HushStorage/HushProviders/HushNetworking/HushRendering internals
- NO new `swiftlint:disable` pragmas
- NO changed test assertions or test logic

## Formatting Baseline (2026-03-28)
- `make fmt` only touched `Hush/Views/Chat/AppKit/MessageTableView.swift` and `Hush/Views/Chat/QuickBar/QuickBarPanelView.swift`.
- Build succeeded after formatting baseline commit `e8d8d00`.
- `make test` still fails in `TailPrewarmTests` (`Cold conversation streaming completion uses one-shot final-message prewarm (no tail prewarm)`), so the failure is pre-existing and unrelated to formatting.
