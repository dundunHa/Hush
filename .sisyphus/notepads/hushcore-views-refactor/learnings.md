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

## Task 3 Notes
- Extracted the OpenAI settings DTOs into `Hush/HushCore/SettingsDTOs.swift` with Foundation-only imports.
- Kept the private AppContainer-only types in place; only the five shared DTO types moved out.
- Xcode project needed a synchronized-folder exception entry plus file reference to make the new HushCore file compile cleanly.
- `make build` completed successfully after the project update.

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

### Task 4 Learnings: Shared Components
- Xcode 16's `PBXFileSystemSynchronizedRootGroup` means we don't need to manually update `project.pbxproj` when adding files to synchronized folders like `Hush/`.
- Creating `SettingsListRow` and `EmptyStateView` helps standardize the UI and reduce duplicated boilerplate in the Settings workspace.
- The `palette` from `@Environment(\.hushThemePalette)` handles light/dark/active state theme colors dynamically, ensuring no hardcoded hex or system colors are needed.

### Task 5 Learnings: ProviderSettingsView Split
- When splitting a SwiftUI struct into extensions across files, all `@State` and `@EnvironmentObject` properties must be `internal` (not `private`) for cross-file extension access.
- `private` types (`ProviderEditorTarget`, `ProviderEditorSnapshot`, etc.) must become `internal` when extracted to separate files, since they're referenced from multiple extension files.
- The `ProviderCatalogDraftSignature` also needed to change from `private struct` to `struct` for the same reason.
- Extensions on a SwiftUI View struct can access all `@State` bindings (`$apiKey`, `$endpoint`, etc.) — SwiftUI property wrappers work across extension boundaries within the same module.
- Split approach: catalog logic types → standalone file (pure logic, no SwiftUI), editor state types → standalone file, detail pane views → extension, action bar + save/load + selection state → extension.
- ProviderSettingsView went from 1735 → 494 lines. Total across 5 files: 1757 lines (slight overhead from imports/extension declarations).
- The existing `swiftlint:disable type_body_length function_body_length file_length` pragma was removed from the main file since it's no longer needed at 494 lines. The `function_body_length` pragma was moved only to `modelsSection` in the DetailPane extension and `saveCustomProviderSettings` in the ActionBar extension where the long functions actually live.
- `ProviderListRowView` (private struct) stays in the main file alongside previews since it's tightly coupled to the list panel.

### Task 9 Learnings: Composer Dedup
- 把 `ComposerDock` 与 `QuickBarComposer` 的共享逻辑下沉到 `ComposerModelService`（helper，不是 ViewModel）后，可在不改变发送/模型选择行为的前提下统一 `enabledProviders`、`selectedProviderName`、`canSendDraft`、`modelsForMenu`、`refreshAvailableModels`、`fallbackModels`。
- 共享菜单 UI 提炼为 `ProviderModelSelector`，通过 `surfaceStyle` + label builder 闭包保留主窗口与 Quick Bar 的视觉差异；避免把两个 Composer 强行合并成一个 View。
- 为满足文件规模目标，Quick Bar 的大段视觉计算拆到 `QuickBarComposerVisuals` 与 `QuickBarComposerLayoutMetrics+Presets`，主文件降到 312 行；`ComposerDock` 降到 396 行。
- `QuickBarComposerSupport.swift` 保持不改动，符合任务约束。

### Task 8 Learnings: ChatConfigPopover Split
- `ChatConfigDrawer` can keep its main drawer layout in the original file while moving parameter row helpers into a sibling file via `extension ChatConfigDrawer`.
- Shared `Binding`/helper methods (`contextLimitValueBinding`, `resetVisibleParameters`, `parameterRow`, `numberField`) work cleanly across files as long as they stay in the same module.
- The config popover shrank from 512 → 310 lines without changing behavior.
- No `project.pbxproj` update was needed because `Hush/Views` is under Xcode 16 synchronized folder management.

### Task 6 Learnings: ThemeChrome Split

### Task 15 Learnings: AppContainer Lint Cleanup
- `AppContainer.swift` now has no `swiftlint:disable file_length` / `type_body_length` pragma pair; the file still stays under the 900-line target at 811 lines.
- `make fmt` does not come back clean yet because unrelated pre-existing SwiftLint violations remain elsewhere; the removal itself did not introduce new diff outside `AppContainer.swift` after restoring incidental formatter churn.
- `make build` still succeeds after the pragma removal.
- ThemeChrome.swift (832 lines, 16 types) cleanly splits into 3 cohesive files by domain:
  - `GlassEffectSurfaces.swift` (465 lines): All Quick Bar glass types — 9 public types + `BehindWindowVibrancyHost` + private View extension for glass transitions.
  - `ChromeMaterials.swift` (319 lines): Sidebar/workspace background types — `SplitPaneSidebarSurface`, `SidebarMaterialBackground`, `SidebarNativeGlassBackground` (private), `WorkspaceChromeBackground`.
  - `ThemeChrome.swift` (51 lines): Border/mask utilities only — `LeadingPaneBorderMask` (private), `LeadingPaneBorder`.
- `BehindWindowVibrancyHost` is used by both glass surfaces (QuickBarLiquidGlassSurface) and sidebar materials (SidebarMaterialBackground fallback), but since it's `internal` in the same module, placing it in `GlassEffectSurfaces.swift` works fine — no cross-file visibility issues.
- ThemeChrome.swift only needs `import SwiftUI` (no AppKit) since the remaining types are pure SwiftUI views. The two new files need `import AppKit` + `import SwiftUI` because they use `NSVisualEffectView.Material` and `Glass`.
- No `project.pbxproj` update needed — Xcode 16 synchronized folder management picks up new files automatically.

### Task 7 Learnings: AgentSettingsView Split
- AgentSettingsView.swift went from 718 → 136 lines. Total across 3 files: 608 lines (net reduction from removing `AgentPresetRow` duplication).
- `AgentPresetRow` (private struct, 75 lines) was replaced entirely by `SettingsListRow` shared component — no custom row needed.
- The "Default" badge trailing view was extracted as a `defaultBadge` computed property and passed via `SettingsListRow(trailingView: AnyView(defaultBadge))`.
- Inline empty state (14 lines) replaced with `EmptyStateView(icon:title:description:)` — 3 lines.
- Same extension-across-files pattern as Task 5: `@State`/`@EnvironmentObject` changed from `private` to `internal`.
- The original `swiftlint:disable type_body_length file_length` pragma was removed since the main file is now only 136 lines.
- Previews for `AgentPresetRow` were removed since the type no longer exists; `AgentSettingsView` previews stay in the main file.

### Task 10 Learnings: AppContainer+MessageBuckets Extraction
- Extracted 13 methods from `// MARK: - Message Bucket Interface` section into `Hush/AppContainer+MessageBuckets.swift` as `extension AppContainer`.
- AppContainer.swift went from 2787 → 2678 lines (-109). New file: 112 lines.
- **Critical Swift access control insight**: `private` in Swift means "this file only". Moving methods to a separate extension file requires changing `private` → `internal` for both the methods and any properties they access.
- Properties that needed access level widening: `messagesByConversationId` (private→internal), `hotScenePool` (private→internal), `messageAssetStore` (private→internal), `quickBarState`/`runningConversationIds`/`queuedConversationCounts`/`unreadCompletions` (private(set)→internal setter).
- `mutateQuickBarState` was `private` but used in 9+ places across AppContainer.swift outside the Message Bucket section — must become `internal` when moved.
- `sidebarThreadsLoadApplyDelayOverride` is a **stored property** (`var Duration?`) — cannot be in an extension, must stay in main class body.
- No `project.pbxproj` update needed — Xcode 16 synchronized folder management.

## Task 11: AppContainer+ProviderManagement extraction

- **private(set) struct properties**: When a stored property is `private(set)` and holds a `struct` with `mutating` methods, calling those methods from a different file requires changing to `internal(set)`. This is because calling a mutating method on a struct property implicitly requires setting the property.
- **private extension → internal**: The `private extension AppContainer` pattern makes all members file-private. When moving to a separate file, must use plain `extension AppContainer` (internal access).
- **Bottom-up removal**: When removing multiple sections from a file, always remove from bottom to top to preserve line numbers of earlier sections.
- **Partial match hazard**: When using Edit tool with large oldString blocks containing `#if DEBUG` / `#endif`, be careful that the pattern doesn't partially match across conditional compilation boundaries. The first removal attempt left behind a fragment because the oldString cut through a `#if DEBUG` block.
- **Sections extracted**: Settings Workspace, Multi-Provider Profile Management, Catalog Refresh Triggers, Agent Preset Management, Prompt Template Management, and private helper functions (normalizeEndpoint, fallbackProviderConfiguration, etc.)
- **Result**: AppContainer.swift reduced from ~2678 to 2289 lines. New file is 388 lines.

### Task 12 Learnings: AppContainer+Catalog Extraction
- Catalog methods were already in `AppContainer+ProviderManagement.swift` (extracted in Task 11), not in `AppContainer.swift`. Plan line numbers were pre-Task-11 references.
- Extracted 8 methods into `AppContainer+Catalog.swift` (100 lines): `refreshCatalog`, `ensureProviderRegistered`, `selectDeterministicFallback`, `resolveProvider`, `previewProvider`, `makeProviderRuntime`, `triggerCatalogRefreshIfNeeded`, `selectDeterministicFallbackProvider`.
- Kept `fallbackProviderConfiguration`, `normalizeEndpoint`, `normalizedEndpoint` in ProviderManagement since they're used by `saveOpenAISettings` and `previewModels`.
- ProviderManagement went from 388 → 295 lines. No changes to AppContainer.swift (still 2289 lines).
- All methods were already `internal` (not `private`) from Task 11 extraction, so no access control changes needed.
- Build succeeded on first try — clean extraction with no syntax issues.

### Task 14 Learnings: AppContainer+SendPipeline Extraction
- `SendDraftDestination` moved from main file private scope to file-level internal enum in `AppContainer+SendPipeline.swift`, enabling cross-file extension access without behavior changes.
- Send pipeline extraction required widening access for moved members from `private` to `internal` (`sendDraft(_:destination:)`, route/type helpers, Quick Bar send helpers) because Swift `private` is file-scoped.
- `quickBarGeneration` had to become internal stored state in `AppContainer.swift` so the extracted Quick Bar route/session methods can mutate generation across files.
- `AppContainer.swift` line count dropped to 815 (< 900 target) after removing the `// MARK: - Send Pipeline` block.
- Build and LSP diagnostics stayed clean after extraction; Quick Bar submit/send/stop call sites continued to compile against the new extension file.
