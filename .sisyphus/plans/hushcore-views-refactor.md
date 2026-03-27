# HushCore + Views 大刀阔斧重构

## TL;DR

> **Quick Summary**: 对 Hush macOS 应用进行全面重构——拆分巨型文件（AppContainer 2833行→<900行, ProviderSettingsView 1735行→多文件）、消除 ~200 行重复代码、矫正职责错位、清理死代码、建立共享组件库。
> 
> **Deliverables**:
> - AppContainer.swift 从 2833 行拆分至 <900 行（通过 extension 分离文件）
> - 6 个大型 View 文件拆分为 20+ 个聚焦文件
> - ComposerDock/QuickBarComposer 共享逻辑统一提取
> - 3 个共享 Settings 组件创建
> - 死代码清理（根目录 HushCore/PerfTrace.swift）
> - DTO 类型从 AppContainer 移至 HushCore
> - 所有 AGENTS.md 更新以反映新结构
> 
> **Estimated Effort**: Large (16 atomic commits)
> **Parallel Execution**: YES - 4 waves
> **Critical Path**: Task 1 → Task 2 → Task 3 → Tasks 4-9 (parallel) → Tasks 10-14 (parallel) → Task 15 → Task 16 → F1-F4

---

## Context

### Original Request
重构 HushCore 和 Views 两个目录的代码，并顺带整理涉及的上下游代码。范围：大刀阔斧——可重新设计模块结构、改接口、统一模式。

### Interview Summary
**Key Discussions**:
- 五大重构目标：大文件拆分、职责错位、根目录清理、重复消除、模块边界
- 范围覆盖：HushCore, Views, AppContainer, RequestCoordinator 及其上下游

**Research Findings**:
- 项目是单 Xcode target（非 SPM），目录只是组织结构，文件移动无 import 影响
- 测试覆盖率高：77 个测试文件，600+ 测试用例，~90% HushCore / ~85% Views
- Build 当前成功通过
- AppContainer 已有 extension-in-separate-file 模式（PreviewSupport.swift）
- 根 HushCore/PerfTrace.swift 是死代码（与 Hush/HushCore/PerfTrace.swift 完全不同）

### Metis Review
**Identified Gaps** (addressed):
- 根 PerfTrace.swift 应删除而非移动（已修正计划）
- 不应引入 ViewModel 模式（已锁定为 extension + service 提取）
- OpenAISettingsSaveError 容易遗漏（已纳入 DTO 迁移）
- @Published 属性必须留在 AppContainer（已设为 guardrail）
- Xcode project.pbxproj 需同步更新（已纳入每个任务）
- PreviewSupport.swift extension 需跟随更新（已关注）

---

## Work Objectives

### Core Objective
将 Hush 应用的核心代码从"能跑"重构为"好维护"——通过拆分巨型文件、消除重复、矫正职责边界，使每个文件聚焦单一职责，每个模块边界清晰。

### Concrete Deliverables
- AppContainer.swift: 2833行 → <900行（主体） + 5个 extension 文件
- ProviderSettingsView.swift: 1735行 → 4个聚焦文件
- ThemeChrome.swift: 832行 → 3个主题文件
- AgentSettingsView.swift: 718行 → 3个文件
- ComposerDock + QuickBarComposer: 提取共享组件 + 逻辑层
- ChatConfigPopover.swift: 拆分参数控件
- 新增共享组件: SettingsListRow, EmptyStateView
- 根 HushCore/ 目录清理
- 所有 AGENTS.md 更新

### Definition of Done
- [ ] `make build` → BUILD SUCCEEDED
- [ ] `make test` → 所有测试通过，测试数量不变
- [ ] `make fmt` → 零格式变更
- [ ] `wc -l Hush/AppContainer.swift` < 900
- [ ] 无 View 文件超过 600 行
- [ ] `grep -r "swiftlint:disable file_length" Hush/` → 零结果

### Must Have
- 所有现有测试通过，测试逻辑不变
- 每次 commit 后 build + test + fmt 全部通过
- @Published 属性保留在 AppContainer 上
- HushCore 保持 Foundation-only 纯度
- RequestCoordinator 内部结构不动

### Must NOT Have (Guardrails)
- ❌ 引入 ViewModel 模式（新架构层 — 这是重构不是重写）
- ❌ 修改 RequestCoordinator.swift 内部结构（只调整其与 AppContainer 的接口）
- ❌ 触碰 HushStorage / HushProviders / HushNetworking / HushRendering 内部
- ❌ 改变任何 test assertion 或 test logic（只允许调整引用路径）
- ❌ 引入新的 `swiftlint:disable` pragma
- ❌ 改变任何用户可见行为
- ❌ 在 AppContainer 之外放置 @Published 属性
- ❌ 修改 RequestCoordinator 的 `weak var container: AppContainer?` 模式

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: YES — Swift Testing framework, 77 test files, 600+ tests
- **Automated tests**: Existing tests as specification (pure refactoring — no new tests needed)
- **Framework**: Swift Testing (`make test` via xcodebuild)
- **Strategy**: 每次 commit 后运行完整测试套件；任何测试失败 → 立即回退

### QA Policy
Every task MUST verify:
1. `make build 2>&1 | tail -1` → `** BUILD SUCCEEDED **`
2. `make test` → 所有测试通过
3. `make fmt` → 零变更
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — zero-risk foundation):
├── Task 1: Formatting baseline (make fmt commit) [quick]
├── Task 2: Delete orphan root HushCore/PerfTrace.swift [quick]
├── Task 3: Extract DTOs from AppContainer to HushCore [quick]
└── Task 4: Create shared Settings components [quick]

Wave 2 (After Wave 1 — View file splits, MAX PARALLEL):
├── Task 5: Split ProviderSettingsView.swift (depends: 3, 4) [unspecified-high]
├── Task 6: Split ThemeChrome.swift (depends: 1) [unspecified-high]
├── Task 7: Split AgentSettingsView.swift (depends: 4) [unspecified-high]
├── Task 8: Split ChatConfigPopover.swift (depends: 1) [quick]
└── Task 9: Consolidate Composer duplication (depends: 1) [deep]

Wave 3 (After Wave 2 — AppContainer decomposition, sequential due to coupling):
├── Task 10: Extract AppContainer+MessageBuckets.swift (depends: 9) [unspecified-high]
├── Task 11: Extract AppContainer+ProviderManagement.swift (depends: 5, 10) [unspecified-high]
├── Task 12: Extract AppContainer+Catalog.swift (depends: 11) [unspecified-high]
├── Task 13: Extract AppContainer+ConversationLifecycle.swift (depends: 10) [deep]
└── Task 14: Extract AppContainer+SendPipeline.swift (depends: 13) [deep]

Wave 4 (After Wave 3 — cleanup):
├── Task 15: Remove swiftlint:disable + verify file sizes [quick]
└── Task 16: Update all AGENTS.md files [writing]

Wave FINAL (After ALL tasks — 4 parallel reviews, then user okay):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real manual QA (unspecified-high)
└── Task F4: Scope fidelity check (deep)
-> Present results -> Get explicit user okay

Critical Path: T1 → T3 → T5 → T10 → T11 → T13 → T14 → T15 → T16 → F1-F4
Parallel Speedup: ~60% faster than sequential
Max Concurrent: 5 (Wave 2)
```

### Dependency Matrix

| Task | Depends On | Blocks |
|------|-----------|--------|
| 1 | — | 2-16 |
| 2 | 1 | — |
| 3 | 1 | 5, 11 |
| 4 | 1 | 5, 7 |
| 5 | 3, 4 | 11 |
| 6 | 1 | — |
| 7 | 4 | — |
| 8 | 1 | — |
| 9 | 1 | 10 |
| 10 | 9 | 11, 13 |
| 11 | 5, 10 | 12 |
| 12 | 11 | — |
| 13 | 10 | 14 |
| 14 | 13 | 15 |
| 15 | 14 | 16 |
| 16 | 15 | F1-F4 |

### Agent Dispatch Summary

- **Wave 1**: 4 tasks — T1-T2 → `quick`, T3 → `quick`, T4 → `quick`
- **Wave 2**: 5 tasks — T5 → `unspecified-high`, T6 → `unspecified-high`, T7 → `unspecified-high`, T8 → `quick`, T9 → `deep`
- **Wave 3**: 5 tasks — T10-T12 → `unspecified-high`, T13-T14 → `deep`
- **Wave 4**: 2 tasks — T15 → `quick`, T16 → `writing`
- **FINAL**: 4 tasks — F1 → `oracle`, F2 → `unspecified-high`, F3 → `unspecified-high`, F4 → `deep`

---

## TODOs

- [x] 1. Formatting Baseline

  **What to do**:
  - Run `make fmt` to apply SwiftFormat + SwiftLint across entire codebase
  - Commit the formatting changes as a clean baseline
  - This ensures subsequent refactoring diffs contain ONLY structural changes, not formatting noise

  **Must NOT do**:
  - Do not change any code logic
  - Do not add or remove files

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 1 (first task, must complete before anything else)
  - **Blocks**: Tasks 2-16
  - **Blocked By**: None

  **References**:
  - `Makefile` — `fmt` target runs `swiftformat . --config .swiftformat` then `swiftlint lint --fix`
  - `.swiftformat` — SwiftFormat configuration
  - `.swiftlint.yml` — SwiftLint rules (line length 140/180, function body 80/120, file length 600/900)

  **Acceptance Criteria**:

  ```
  Scenario: Formatting produces clean baseline
    Tool: Bash
    Steps:
      1. Run `make fmt`
      2. Run `git diff --stat` to see formatting changes
      3. Run `git add -A && git commit -m "chore: format codebase for clean refactoring baseline"`
      4. Run `make build 2>&1 | tail -1`
      5. Run `make test 2>&1 | grep -E "Test Suite|passed|failed"`
    Expected Result: BUILD SUCCEEDED, all tests pass
    Evidence: .sisyphus/evidence/task-1-fmt-baseline.txt
  ```

  **Commit**: YES
  - Message: `chore: format codebase for clean refactoring baseline`
  - Files: all formatted files
  - Pre-commit: `make build && make test`

- [ ] 2. Delete Orphan Root HushCore/PerfTrace.swift

  **What to do**:
  - Delete `HushCore/PerfTrace.swift` (root-level, 16 lines, dead code)
  - This is NOT the real PerfTrace — the real one is `Hush/HushCore/PerfTrace.swift` (135 lines with os.Logger, JSON, ContinuousClock)
  - Verify the root file is NOT referenced in `Hush.xcodeproj/project.pbxproj`
  - If it IS referenced in pbxproj, remove the reference too
  - Delete the root `HushCore/` directory if it becomes empty

  **Must NOT do**:
  - Do NOT touch `Hush/HushCore/PerfTrace.swift` (the real one)
  - Do NOT modify any other files

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 3, 4 after Task 1)
  - **Parallel Group**: Wave 1
  - **Blocks**: None
  - **Blocked By**: Task 1

  **References**:
  - `HushCore/PerfTrace.swift` (root) — 16-line stub: `public enum PerfTrace { static var counters... }`
  - `Hush/HushCore/PerfTrace.swift` — Real 135-line version with `os.Logger`, `TestRecorder`, `ContinuousClock`
  - `Hush.xcodeproj/project.pbxproj` — Xcode project file, verify no reference to root HushCore

  **Acceptance Criteria**:

  ```
  Scenario: Orphan file deleted, real file untouched
    Tool: Bash
    Steps:
      1. Run `grep -c "HushCore/PerfTrace" Hush.xcodeproj/project.pbxproj` to check references
      2. Run `rm HushCore/PerfTrace.swift && rmdir HushCore/ 2>/dev/null`
      3. Run `test -f Hush/HushCore/PerfTrace.swift && echo "Real file exists"`
      4. Run `test ! -f HushCore/PerfTrace.swift && echo "Orphan deleted"`
      5. Run `make build && make test`
    Expected Result: BUILD SUCCEEDED, all tests pass, orphan gone, real file intact
    Evidence: .sisyphus/evidence/task-2-orphan-deleted.txt
  ```

  **Commit**: YES
  - Message: `chore: delete orphan root HushCore/PerfTrace.swift`
  - Files: `HushCore/PerfTrace.swift` (deleted)
  - Pre-commit: `make build && make test`

- [ ] 3. Extract DTOs from AppContainer to HushCore

  **What to do**:
  - Create `Hush/HushCore/SettingsDTOs.swift` containing types extracted from `Hush/AppContainer.swift` lines 9-53:
    - `OpenAISettingsSnapshot` (struct, lines 9-14)
    - `OpenAISettingsInput` (struct, lines 16-23)
    - `ProviderCatalogDraftInput` (struct, lines 25-31)
    - `OpenAISettingsSaveError` (enum + LocalizedError extension, lines 33-47)
    - `DataStats` (struct, lines 49-53)
  - Add new file to Xcode project (update `project.pbxproj`)
  - Remove these types from AppContainer.swift
  - Ensure the new file only imports Foundation (HushCore convention)
  - Keep private types in AppContainer.swift: `ConversationPageSnapshot`, `ConversationMessageStats`, `ConversationSwitchTrace`, `ConversationSwitchDebug`, `makeConversationMessageStats`, `SendDraftDestination`

  **Must NOT do**:
  - Do not move private types (they're implementation details of AppContainer)
  - Do not change any type signatures or add/remove properties
  - Do not import anything other than Foundation in the new file

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 2, 4 after Task 1)
  - **Parallel Group**: Wave 1
  - **Blocks**: Tasks 5, 11
  - **Blocked By**: Task 1

  **References**:
  - `Hush/AppContainer.swift:9-53` — Source types to extract
  - `Hush/HushCore/AGENTS.md` — Convention: Foundation-only, pure value types, Sendable+Equatable+Codable
  - `Hush/HushCore/ProviderConfiguration.swift` — Similar DTO pattern already in HushCore
  - `HushTests/AppContainerProviderSettingsTests.swift` — Tests using these types, must still compile

  **Acceptance Criteria**:

  ```
  Scenario: DTOs extracted to HushCore, builds and tests pass
    Tool: Bash
    Steps:
      1. Verify `Hush/HushCore/SettingsDTOs.swift` exists
      2. Run `grep "import " Hush/HushCore/SettingsDTOs.swift` — only `import Foundation`
      3. Run `grep "struct OpenAISettingsSnapshot" Hush/AppContainer.swift` — must NOT find it
      4. Run `grep "struct OpenAISettingsSnapshot" Hush/HushCore/SettingsDTOs.swift` — must find it
      5. Run `make build && make test`
    Expected Result: All types accessible from new location, BUILD SUCCEEDED, all tests pass
    Evidence: .sisyphus/evidence/task-3-dto-extraction.txt

  Scenario: Private types remain in AppContainer
    Tool: Bash
    Steps:
      1. Run `grep "private struct ConversationPageSnapshot" Hush/AppContainer.swift` — must find it
      2. Run `grep "private enum SendDraftDestination" Hush/AppContainer.swift` — must find it
    Expected Result: Private types not moved
    Evidence: .sisyphus/evidence/task-3-private-types-check.txt
  ```

  **Commit**: YES
  - Message: `refactor(core): extract DTOs from AppContainer to HushCore`
  - Files: `Hush/HushCore/SettingsDTOs.swift` (new), `Hush/AppContainer.swift` (modified), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 4. Create Shared Settings Components

  **What to do**:
  - Create `Hush/Views/Settings/Components/` directory
  - Create `SettingsListRow.swift` — generic reusable list row view with:
    - Configurable icon (SF Symbol name + color)
    - Title + optional subtitle
    - Hover effect with `palette.hoverFill` / `palette.cardBackground`
    - Chevron indicator
    - `onTap` action callback
    - Pattern extracted from AgentPresetRow, PromptTemplateRow, ArchivedThreadRow
  - Create `EmptyStateView.swift` — generic empty state view with:
    - Configurable icon (SF Symbol name)
    - Title + description text
    - Same layout used in AgentSettingsView, PromptLibraryView, ArchivedThreadsSettingsView
  - Add new files to Xcode project
  - Do NOT update consumers yet (Tasks 5, 7 will do that)

  **Must NOT do**:
  - Do not modify existing Settings views yet
  - Do not over-abstract — simple init parameters, no protocols/generics beyond what's needed

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 2, 3 after Task 1)
  - **Parallel Group**: Wave 1
  - **Blocks**: Tasks 5, 7
  - **Blocked By**: Task 1

  **References**:
  - `Hush/Views/Settings/AgentSettingsView.swift` — `AgentPresetRow` (icon circle + title + subtitle + chevron + hover)
  - `Hush/Views/Settings/PromptLibraryView.swift` — Similar row pattern
  - `Hush/Views/Settings/ArchivedThreadsSettingsView.swift` — Similar row + empty state patterns
  - `Hush/HushTheme/` — `HushColors`, `HushSpacing`, `HushTypography` theme tokens
  - `Hush/Views/AGENTS.md` — Convention: theme tokens only, dark mode only, no hardcoded colors

  **Acceptance Criteria**:

  ```
  Scenario: Shared components compile and follow conventions
    Tool: Bash
    Steps:
      1. Verify `Hush/Views/Settings/Components/SettingsListRow.swift` exists
      2. Verify `Hush/Views/Settings/Components/EmptyStateView.swift` exists
      3. Run `grep "HushSpacing\|HushTypography" Hush/Views/Settings/Components/SettingsListRow.swift` — finds theme tokens
      4. Run `make build && make test`
    Expected Result: Components compile, follow theme conventions, all tests pass
    Evidence: .sisyphus/evidence/task-4-shared-components.txt
  ```

  **Commit**: YES
  - Message: `refactor(views): create shared Settings components (SettingsListRow, EmptyStateView)`
  - Files: `Hush/Views/Settings/Components/*.swift` (new), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 5. Split ProviderSettingsView.swift (1735 lines → 4+ files)

  **What to do**:
  - Extract from `Hush/Views/Settings/ProviderSettingsView.swift`:
    1. `ProviderCatalogLogic.swift` — Move `ProviderCatalogRefreshGate`, `ProviderCatalogDraftSignature`, `ProviderCatalogSelectionLogic` (lines 1-118, catalog refresh/model selection logic)
    2. `ProviderEditorState.swift` — Move `ProviderEditorTarget`, `ProviderEditorSelectionRequest`, `ProviderEditorSnapshot`, `ProviderEditorBaseline` (lines 119-168, editor state types)
    3. `ProviderSettingsDetailPane.swift` — Extract the detail/form pane portion (provider config form, model section, credential entry)
    4. `ProviderSettingsActionBar.swift` — Extract action bar (save/delete/set-default buttons)
  - Keep `ProviderSettingsView.swift` as the coordinator view (list + layout + state wiring)
  - Replace `AgentPresetRow`-like patterns with `SettingsListRow` from Task 4 where applicable
  - Update Xcode project with new files
  - All new files stay in `Hush/Views/Settings/`

  **Must NOT do**:
  - Do not change behavior of any provider setting flow
  - Do not change how credential persistence works
  - Do not introduce ViewModels

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 6, 7, 8)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 11
  - **Blocked By**: Tasks 3, 4

  **References**:
  - `Hush/Views/Settings/ProviderSettingsView.swift` — Full source, 1735 lines, 9 type definitions
  - `Hush/Views/Settings/Components/SettingsListRow.swift` — Shared row component (from Task 4)
  - `HushTests/ProviderSettingsViewTests.swift` — 12 test cases covering catalog refresh gates, model filtering
  - `Hush/AppContainer.swift:791-1026` — `saveProviderProfile`, `setDefaultProvider`, `removeProviderProfile` methods called by this view

  **Acceptance Criteria**:

  ```
  Scenario: ProviderSettingsView split into focused files
    Tool: Bash
    Steps:
      1. Run `wc -l Hush/Views/Settings/ProviderSettingsView.swift` — must be < 600
      2. Run `ls Hush/Views/Settings/Provider*.swift` — should show 3+ files
      3. Run `make build && make test`
    Expected Result: All files < 600 lines, BUILD SUCCEEDED, all 12 ProviderSettings tests pass
    Evidence: .sisyphus/evidence/task-5-provider-split.txt
  ```

  **Commit**: YES
  - Message: `refactor(views): split ProviderSettingsView into focused files`
  - Files: `Hush/Views/Settings/ProviderCatalogLogic.swift`, `ProviderEditorState.swift`, `ProviderSettingsDetailPane.swift`, `ProviderSettingsActionBar.swift` (new), `ProviderSettingsView.swift` (trimmed), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 6. Split ThemeChrome.swift (832 lines → 3 files)

  **What to do**:
  - Extract from `Hush/Views/ThemeChrome.swift`:
    1. `GlassEffectSurfaces.swift` — Move all Quick Bar glass-related types (lines ~1-465):
       `QuickBarNativeGlassID`, `QuickBarNativeGlassTransitionKind`, `QuickBarNativeGlassRegistration`,
       `QuickBarNativeGlassStyle`, `QuickBarNativeGlassSurface`, `QuickBarLiquidGlassStyle`,
       `QuickBarLiquidGlassSurface`, `QuickBarMinimalSurface`, `QuickBarGlassSurface`
    2. `ChromeMaterials.swift` — Move sidebar/workspace backgrounds (lines ~517-832):
       `SplitPaneSidebarSurface`, `SidebarMaterialBackground`, `SidebarNativeGlassBackground`,
       `WorkspaceChromeBackground`
  - Keep `ThemeChrome.swift` with border/mask utilities:
    `BehindWindowVibrancyHost`, `LeadingPaneBorderMask`, `LeadingPaneBorder`
  - Update Xcode project

  **Must NOT do**:
  - Do not change any visual appearance
  - Do not rename any public types

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 5, 7, 8, 9)
  - **Parallel Group**: Wave 2
  - **Blocks**: None
  - **Blocked By**: Task 1

  **References**:
  - `Hush/Views/ThemeChrome.swift` — Full source, 832 lines, 16 type definitions
  - `Hush/Views/Chat/QuickBar/QuickBarPanelView.swift` — Consumes glass surface types
  - `Hush/Views/RootView.swift` — Consumes chrome background types
  - `Hush/Views/Sidebar/ConversationSidebarView.swift` — Consumes sidebar surface

  **Acceptance Criteria**:

  ```
  Scenario: ThemeChrome split by concern
    Tool: Bash
    Steps:
      1. Run `wc -l Hush/Views/ThemeChrome.swift` — must be < 200
      2. Run `wc -l Hush/Views/GlassEffectSurfaces.swift` — must exist
      3. Run `wc -l Hush/Views/ChromeMaterials.swift` — must exist
      4. Run `make build && make test`
    Expected Result: All theme files under limit, BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-6-theme-split.txt
  ```

  **Commit**: YES
  - Message: `refactor(views): split ThemeChrome into glass/materials/utilities`
  - Files: `GlassEffectSurfaces.swift`, `ChromeMaterials.swift` (new), `ThemeChrome.swift` (trimmed), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 7. Split AgentSettingsView.swift (718 lines → 3 files)

  **What to do**:
  - Extract from `Hush/Views/Settings/AgentSettingsView.swift`:
    1. `AgentPresetDetailSheet.swift` — The detail/edit form (left column: provider/model, right column: parameters, system prompt editor, ~lines 120-443)
    2. `AgentPresetActions.swift` — Action bar + CRUD operations (save/delete/set-default, ~lines 475-584)
  - Keep `AgentSettingsView.swift` as coordinator (preset list + state wiring + sheet presentation)
  - Replace `AgentPresetRow` with `SettingsListRow` from Task 4
  - Replace inline empty state with `EmptyStateView` from Task 4
  - Update Xcode project

  **Must NOT do**:
  - Do not change preset management behavior
  - Do not introduce ViewModels

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 5, 6, 8, 9)
  - **Parallel Group**: Wave 2
  - **Blocks**: None
  - **Blocked By**: Task 4

  **References**:
  - `Hush/Views/Settings/AgentSettingsView.swift` — Full source, 718 lines, MARK sections: Preset List, Detail Sheet, Left/Right Column, Action Bar, Actions
  - `Hush/Views/Settings/Components/SettingsListRow.swift` — Replacement for AgentPresetRow
  - `Hush/Views/Settings/Components/EmptyStateView.swift` — Replacement for inline empty state
  - `Hush/HushCore/AgentPreset.swift` — Domain model consumed by this view

  **Acceptance Criteria**:

  ```
  Scenario: AgentSettingsView split and uses shared components
    Tool: Bash
    Steps:
      1. Run `wc -l Hush/Views/Settings/AgentSettingsView.swift` — must be < 300
      2. Run `grep "SettingsListRow" Hush/Views/Settings/AgentSettingsView.swift` — must find usage
      3. Run `grep "EmptyStateView" Hush/Views/Settings/AgentSettingsView.swift` — must find usage
      4. Run `make build && make test`
    Expected Result: Main file < 300 lines, shared components used, BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-7-agent-split.txt
  ```

  **Commit**: YES
  - Message: `refactor(views): split AgentSettingsView into list/detail/actions`
  - Files: `AgentPresetDetailSheet.swift`, `AgentPresetActions.swift` (new), `AgentSettingsView.swift` (trimmed), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 8. Split ChatConfigPopover.swift (512 lines → 2 files)

  **What to do**:
  - Extract from `Hush/Views/Chat/ChatConfigPopover.swift`:
    1. `ChatParameterControls.swift` — Parameter row views, value badges, number fields (~lines 419-512)
  - Keep `ChatConfigPopover.swift` with the main drawer view (header, summary strip, config sections)

  **Must NOT do**:
  - Do not change parameter editing behavior
  - Do not rename ChatConfigDrawer

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 5, 6, 7, 9)
  - **Parallel Group**: Wave 2
  - **Blocks**: None
  - **Blocked By**: Task 1

  **References**:
  - `Hush/Views/Chat/ChatConfigPopover.swift` — Full source, 512 lines
  - `Hush/HushCore/ModelParameters.swift` — `ModelParameters` type bound in this view

  **Acceptance Criteria**:

  ```
  Scenario: ChatConfigPopover split with parameter controls extracted
    Tool: Bash
    Steps:
      1. Run `wc -l Hush/Views/Chat/ChatConfigPopover.swift` — must be < 420
      2. Verify `Hush/Views/Chat/ChatParameterControls.swift` exists
      3. Run `make build && make test`
    Expected Result: Files within limits, BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-8-config-split.txt
  ```

  **Commit**: YES
  - Message: `refactor(views): split ChatConfigPopover into header and parameter controls`
  - Files: `ChatParameterControls.swift` (new), `ChatConfigPopover.swift` (trimmed), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 9. Consolidate Composer Duplication

  **What to do**:
  This is the most impactful deduplication task. ComposerDock.swift and QuickBarComposer.swift share ~200 lines of nearly identical code.

  Step 1 — Extract shared logic:
  - Create `Hush/Views/Chat/ComposerModelService.swift`:
    - `enabledProviders` computed property
    - `selectedProviderName` computed property
    - `canSendDraft` validation logic
    - `refreshAvailableModels()` async method
    - `fallbackModels()` method
    - This is a helper object/struct that takes AppContainer reference, not a ViewModel

  Step 2 — Extract shared UI components:
  - Create `Hush/Views/Chat/ProviderModelSelector.swift`:
    - Shared provider menu
    - Shared model menu
    - Parameterized by `ConversationSurfaceStyle` for style differences between main/quickbar

  Step 3 — Simplify both composers:
  - Update `ComposerDock.swift` to use `ComposerModelService` + `ProviderModelSelector`
  - Update `QuickBarComposer.swift` to use `ComposerModelService` + `ProviderModelSelector`
  - Each composer retains its unique UI layout and surface-specific behavior

  **Must NOT do**:
  - Do not unify the two composers into one view (they have intentionally different layouts)
  - Do not introduce ViewModel pattern
  - Do not change send behavior or model selection behavior
  - Do not modify QuickBarComposerSupport.swift (it's already a separate support file)

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
    - Reason: Complex deduplication requiring careful understanding of subtle differences between two composers

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 5, 6, 7, 8)
  - **Parallel Group**: Wave 2
  - **Blocks**: Task 10
  - **Blocked By**: Task 1

  **References**:
  - `Hush/Views/Chat/ComposerDock.swift` — Main composer, 519 lines
  - `Hush/Views/Chat/QuickBar/QuickBarComposer.swift` — Quick Bar composer, 604 lines
  - `Hush/Views/Chat/QuickBar/QuickBarComposerSupport.swift` — Existing support types
  - `Hush/HushCore/ModelDescriptor.swift` — `ModelDescriptor` type used by both
  - `Hush/HushCore/ProviderConfiguration.swift` — `ProviderConfiguration` used by both
  - Duplicate patterns found: `enabledProviders`, `selectedProviderName`, `canSendDraft`, `refreshAvailableModels()`, `fallbackModels()`, `providerMenu`, `modelMenu`, `modelsForMenu`

  **Acceptance Criteria**:

  ```
  Scenario: Composer duplication eliminated
    Tool: Bash
    Steps:
      1. Verify `Hush/Views/Chat/ComposerModelService.swift` exists
      2. Verify `Hush/Views/Chat/ProviderModelSelector.swift` exists
      3. Run `grep "enabledProviders" Hush/Views/Chat/ComposerDock.swift` — should NOT find local definition (uses shared)
      4. Run `grep "enabledProviders" Hush/Views/Chat/QuickBar/QuickBarComposer.swift` — should NOT find local definition
      5. Run `grep "enabledProviders" Hush/Views/Chat/ComposerModelService.swift` — MUST find it
      6. Run `wc -l Hush/Views/Chat/ComposerDock.swift` — should be < 400 (from 519)
      7. Run `wc -l Hush/Views/Chat/QuickBar/QuickBarComposer.swift` — should be < 450 (from 604)
      8. Run `make build && make test`
    Expected Result: Shared logic extracted, both composers simplified, BUILD SUCCEEDED, all tests pass
    Evidence: .sisyphus/evidence/task-9-composer-dedup.txt

  Scenario: Composer behavior preserved — both composers reference shared service
    Tool: Bash
    Steps:
      1. Run `grep "ComposerModelService" Hush/Views/Chat/ComposerDock.swift` — MUST find usage
      2. Run `grep "ComposerModelService" Hush/Views/Chat/QuickBar/QuickBarComposer.swift` — MUST find usage
      3. Run `grep "ProviderModelSelector" Hush/Views/Chat/ComposerDock.swift` — MUST find usage
      4. Run `grep "ProviderModelSelector" Hush/Views/Chat/QuickBar/QuickBarComposer.swift` — MUST find usage
      5. Run `grep -c "private var enabledProviders" Hush/Views/Chat/ComposerDock.swift` — must be 0 (no local copy)
      6. Run `grep -c "private var enabledProviders" Hush/Views/Chat/QuickBar/QuickBarComposer.swift` — must be 0
      7. Run `make build && make test` — all tests pass (behavioral equivalence via test suite)
    Expected Result: Both composers use shared ComposerModelService + ProviderModelSelector, no local duplicate definitions, BUILD SUCCEEDED, all tests pass
    Evidence: .sisyphus/evidence/task-9-composer-behavior.txt
  ```

  **Commit**: YES
  - Message: `refactor(views): consolidate composer duplication with shared components`
  - Files: `ComposerModelService.swift`, `ProviderModelSelector.swift` (new), `ComposerDock.swift`, `QuickBarComposer.swift` (simplified), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 10. Extract AppContainer+MessageBuckets.swift

  **What to do**:
  - Create `Hush/AppContainer+MessageBuckets.swift`
  - Move the entire `// MARK: - Message Bucket Interface` section (~lines 271-380) as `extension AppContainer`:
    - `registerHotScenePool(_:)`, `messagesForConversation(_:)`, `appendMessage(_:toConversation:)`,
      `updateMessage(at:inConversation:content:)`, `updateMessagesDebugInfo(_:inConversation:debugInfoJSON:)`,
      `resolveURL(for:)`, `pushStreamingContent(conversationId:messageID:content:)`,
      `markUnreadCompletion(forConversation:)`, `clearUnreadCompletion(forConversation:)`,
      `clearActiveConversationUnreadIfAtTail()`, `syncPublishedSchedulerState()`,
      `mutateQuickBarState(_:)`, `syncQuickBarMessagesIfNeeded(conversationId:)`
  - Also move `sidebarThreadsLoadApplyDelayOverride` property
  - Follow existing extension pattern from `PreviewSupport.swift`
  - Properties (`messagesByConversationId`, `hotScenePool`, etc.) stay in main AppContainer — only methods move
  - Update Xcode project

  **Must NOT do**:
  - Do not move @Published properties out of AppContainer
  - Do not change method signatures
  - Do not change access control levels

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential in Wave 3)
  - **Parallel Group**: Wave 3 (first)
  - **Blocks**: Tasks 11, 13
  - **Blocked By**: Task 9

  **References**:
  - `Hush/AppContainer.swift:271-380` — Message Bucket Interface section
  - `Hush/Views/Previews/PreviewSupport.swift` — Existing `extension AppContainer` pattern
  - `HushTests/AppContainerStreamingFastTrackTests.swift` — Tests calling these methods
  - `Hush/RequestCoordinator.swift` — Calls `pushStreamingContent`, `appendMessage`, etc. via `container` reference

  **Acceptance Criteria**:

  ```
  Scenario: Message bucket methods extracted as extension
    Tool: Bash
    Steps:
      1. Verify `Hush/AppContainer+MessageBuckets.swift` exists
      2. Run `grep "extension AppContainer" Hush/AppContainer+MessageBuckets.swift` — must find it
      3. Run `grep "func registerHotScenePool" Hush/AppContainer.swift` — must NOT find it (moved)
      4. Run `grep "func registerHotScenePool" Hush/AppContainer+MessageBuckets.swift` — must find it
      5. Run `make build && make test`
    Expected Result: Methods accessible via extension, BUILD SUCCEEDED, all tests pass
    Evidence: .sisyphus/evidence/task-10-message-buckets.txt
  ```

  **Commit**: YES
  - Message: `refactor(container): extract AppContainer+MessageBuckets`
  - Files: `AppContainer+MessageBuckets.swift` (new), `AppContainer.swift` (trimmed), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 11. Extract AppContainer+ProviderManagement.swift

  **What to do**:
  - Create `Hush/AppContainer+ProviderManagement.swift`
  - Move these sections as `extension AppContainer`:
    - `// MARK: - Settings Workspace` (~lines 791-867): `openAISettingsSnapshot()`, `saveOpenAISettings(_:)`
    - `// MARK: - Multi-Provider Profile Management` (~lines 869-1026): `saveProviderProfile(_:)`, `setDefaultProvider(id:)`, `removeProviderProfile(id:)`, `selectProvider(id:)`, `cachedModels(forProviderID:)`, `catalogRefreshStatus(forProviderID:)`, `availableModels(forProviderID:)`, `previewModels(for:)`
  - Also move the bottom sections:
    - `// MARK: - Agent Preset Management` (~lines 2748-2763)
    - `// MARK: - Prompt Template Management` (~lines 2764-2833)
  - Update Xcode project

  **Must NOT do**:
  - Do not move @Published properties
  - Do not change how ProviderSettingsView interacts with these methods

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential in Wave 3)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 12
  - **Blocked By**: Tasks 5, 10

  **References**:
  - `Hush/AppContainer.swift:791-1026` — Settings Workspace + Multi-Provider sections
  - `Hush/AppContainer.swift:2748-2833` — Agent Preset + Prompt Template sections
  - `HushTests/AppContainerProviderSettingsTests.swift` — Tests calling these methods
  - `HushTests/AppContainerCatalogTests.swift` — Tests for catalog-adjacent methods
  - `Hush/Views/Settings/ProviderSettingsView.swift` — Primary consumer of provider management

  **Acceptance Criteria**:

  ```
  Scenario: Provider management extracted
    Tool: Bash
    Steps:
      1. Verify `Hush/AppContainer+ProviderManagement.swift` exists
      2. Run `grep "func saveProviderProfile" Hush/AppContainer+ProviderManagement.swift` — must find it
      3. Run `grep "func fetchAgentPresets" Hush/AppContainer+ProviderManagement.swift` — must find it
      4. Run `make build && make test`
    Expected Result: BUILD SUCCEEDED, all provider/agent/prompt tests pass
    Evidence: .sisyphus/evidence/task-11-provider-mgmt.txt
  ```

  **Commit**: YES
  - Message: `refactor(container): extract AppContainer+ProviderManagement`
  - Files: `AppContainer+ProviderManagement.swift` (new), `AppContainer.swift` (trimmed), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 12. Extract AppContainer+Catalog.swift

  **What to do**:
  - Create `Hush/AppContainer+Catalog.swift`
  - Move `// MARK: - Catalog Refresh Triggers` section (~lines 1027-1120) as `extension AppContainer`:
    - `refreshCatalog(forProviderID:)`, `resolveProvider(for:)`, `previewProvider(for:)`,
      `ensureProviderRegistered(for:)`, `makeProviderRuntime(id:type:)`,
      `triggerCatalogRefreshIfNeeded(providerID:)`, `selectDeterministicFallback()`,
      `selectDeterministicFallbackProvider()`
  - Update Xcode project

  **Must NOT do**:
  - Do not change catalog refresh behavior
  - Do not move catalog-related @Published properties

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential in Wave 3)
  - **Parallel Group**: Wave 3
  - **Blocks**: None
  - **Blocked By**: Task 11

  **References**:
  - `Hush/AppContainer.swift:1027-1120` — Catalog Refresh Triggers section
  - `HushTests/AppContainerCatalogTests.swift` — Tests for catalog operations
  - `Hush/Views/Settings/ProviderCatalogLogic.swift` — Catalog UI logic (from Task 5)

  **Acceptance Criteria**:

  ```
  Scenario: Catalog methods extracted
    Tool: Bash
    Steps:
      1. Verify `Hush/AppContainer+Catalog.swift` exists
      2. Run `grep "func refreshCatalog" Hush/AppContainer+Catalog.swift` — must find it
      3. Run `make build && make test`
    Expected Result: BUILD SUCCEEDED, all catalog tests pass
    Evidence: .sisyphus/evidence/task-12-catalog.txt
  ```

  **Commit**: YES
  - Message: `refactor(container): extract AppContainer+Catalog`
  - Files: `AppContainer+Catalog.swift` (new), `AppContainer.swift` (trimmed), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 13. Extract AppContainer+ConversationLifecycle.swift

  **What to do**:
  - Create `Hush/AppContainer+ConversationLifecycle.swift`
  - Move these sections as `extension AppContainer`:
    - Conversation activation + loading (~lines 1381-1677): `activateConversation(conversationId:)`, `retryActiveConversationLoad()`, `beginConversationActivation(conversationId:allowSameConversation:)`, `applyCachedConversationSnapshotIfAvailable(conversationId:generation:)`, `resolvedCachedConversationSnapshot(_:conversationId:)`, `makeConversationLoadTask(persistence:conversationId:generation:)`, `loadOlderMessagesIfNeeded()`, `loadMoreSidebarThreadsIfNeeded()`
    - Conversation management (~lines 1678-1928): `resetConversation()`, `deleteConversation(conversationId:)`, `syncStreamingContentForActiveConversationIfNeeded(conversationId:)`, `syncPresentedStreamingMessageIntoBucketsIfNeeded(conversationId:messageID:content:)`, `archiveConversation(conversationId:)`, `unarchiveConversation(conversationId:)`, `fetchArchivedThreads()`, `applyConversationSnapshot(_:conversationId:)`, `activateConversationSnapshot(_:conversationId:status:)`, `cacheCurrentConversationSnapshotIfNeeded()`, `cacheConversationSnapshot(conversationId:snapshot:)`
    - Conversation switch tracing (~lines 1929-2125): `markConversationSwitchLayoutReady()`, `reportActiveConversationRichRenderReadyIfNeeded()`, `reportSwitchPresentedRenderedFromReloadIfNeeded(...)`, `reportHotSceneSwitchPresentedRenderedIfNeeded(...)`
    - Data management (~lines 2627-2681): `fetchDataStats()`, `deleteAllChatHistory()`
    - Settings persistence debounced (~lines 2682-2745): `persistSettingsIfNeeded(previous:)`, `scheduleDebouncedSave()`, `performSave()`, `flushSettings()`
  - This is the LARGEST extraction (~1000+ lines). Be meticulous.
  - Also move the private helper types that ONLY serve these methods:
    - `ConversationPageSnapshot`, `ConversationMessageStats`, `ConversationSwitchTrace`, `ConversationSwitchDebug`, `makeConversationMessageStats()` — move these to the extension file as `private` (file-private in Swift = accessible within file)
  - Update Xcode project

  **Must NOT do**:
  - Do not change conversation loading/switching behavior
  - Do not move @Published conversation state properties
  - Do not break conversation page cache logic
  - Do not change `#if DEBUG` automation methods location (those stay in main file)

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
    - Reason: Largest extraction, many interdependencies between conversation loading/caching/switching

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential in Wave 3)
  - **Parallel Group**: Wave 3
  - **Blocks**: Task 14
  - **Blocked By**: Task 10

  **References**:
  - `Hush/AppContainer.swift:1381-2125, 2627-2745` — All sections being extracted
  - `HushTests/AppContainerPersistenceSemanticsTests.swift` — Tests for persistence
  - `HushTests/AppContainerSettingsPersistenceTests.swift` — Tests for debounced save
  - `HushTests/ConversationWindowingTests.swift` — Tests for conversation loading
  - `HushTests/ConversationSwitchScrollTests.swift` — Tests for conversation switching
  - `Hush/RequestCoordinator.swift` — Calls conversation lifecycle methods via `container`

  **Acceptance Criteria**:

  ```
  Scenario: Conversation lifecycle extracted (largest extraction)
    Tool: Bash
    Steps:
      1. Verify `Hush/AppContainer+ConversationLifecycle.swift` exists
      2. Run `wc -l Hush/AppContainer+ConversationLifecycle.swift` — should be ~1000+ lines
      3. Run `grep "func activateConversation" Hush/AppContainer+ConversationLifecycle.swift` — must find it
      4. Run `grep "func deleteConversation" Hush/AppContainer+ConversationLifecycle.swift` — must find it
      5. Run `grep "func flushSettings" Hush/AppContainer+ConversationLifecycle.swift` — must find it
      6. Run `make build && make test`
    Expected Result: All conversation methods in extension, BUILD SUCCEEDED, all tests pass
    Evidence: .sisyphus/evidence/task-13-conversation-lifecycle.txt
  ```

  **Commit**: YES
  - Message: `refactor(container): extract AppContainer+ConversationLifecycle`
  - Files: `AppContainer+ConversationLifecycle.swift` (new), `AppContainer.swift` (trimmed), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 14. Extract AppContainer+SendPipeline.swift

  **What to do**:
  - Create `Hush/AppContainer+SendPipeline.swift`
  - Move `// MARK: - Send Pipeline` section (~lines 1122-1380) as `extension AppContainer`:
    - `sendDraft(_:)`, `sendDraft(_:destination:)`, `updateSidebarThreadsAfterUserMessage(_:conversationId:)`,
      `upsertSidebarThread(conversationId:title:lastActivityAt:)`, `quickBarSubmit(_:)`,
      `SendRoute` struct, `resolveSendRoute(for:)`, `prepareQuickBarSessionIfNeeded(forceReset:)`,
      `ensureQuickBarConversationId()`, `resolveQuickBarDefaults()`,
      `stopActiveRequest()`, `stopQuickBarRequest()`
  - Move the private `SendDraftDestination` enum with it
  - Update Xcode project
  - This is the MOST COUPLED section — it calls into Message Buckets, Conversation Lifecycle, and RequestCoordinator. Do this LAST in the AppContainer decomposition.

  **Must NOT do**:
  - Do not change send pipeline behavior
  - Do not break Quick Bar send flow
  - Do not modify RequestCoordinator interaction

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
    - Reason: Most coupled section, touches Message Buckets, Conversation Lifecycle, and RequestCoordinator

  **Parallelization**:
  - **Can Run In Parallel**: NO (must be last AppContainer extraction)
  - **Parallel Group**: Wave 3 (last)
  - **Blocks**: Task 15
  - **Blocked By**: Task 13

  **References**:
  - `Hush/AppContainer.swift:1122-1380` — Send Pipeline section
  - `Hush/RequestCoordinator.swift` — `submitRequest()` called from send pipeline
  - `Hush/AppContainer+MessageBuckets.swift` — `appendMessage`, `pushStreamingContent` called from send pipeline
  - `HushTests/QuickBarRoutingTests.swift` — Tests for Quick Bar send flow
  - `HushTests/RoutingInvariantTests.swift` — Tests for send routing invariants
  - `HushTests/SinglePathRoutingTests.swift` — Tests for single-path routing

  **Acceptance Criteria**:

  ```
  Scenario: Send pipeline extracted (most coupled section)
    Tool: Bash
    Steps:
      1. Verify `Hush/AppContainer+SendPipeline.swift` exists
      2. Run `grep "func sendDraft" Hush/AppContainer+SendPipeline.swift` — must find it
      3. Run `grep "func quickBarSubmit" Hush/AppContainer+SendPipeline.swift` — must find it
      4. Run `wc -l Hush/AppContainer.swift` — should now be < 900
      5. Run `make build && make test`
    Expected Result: Send pipeline in extension, main AppContainer < 900 lines, BUILD SUCCEEDED, all tests pass
    Evidence: .sisyphus/evidence/task-14-send-pipeline.txt
  ```

  **Commit**: YES
  - Message: `refactor(container): extract AppContainer+SendPipeline`
  - Files: `AppContainer+SendPipeline.swift` (new), `AppContainer.swift` (trimmed), `Hush.xcodeproj/project.pbxproj`
  - Pre-commit: `make build && make test`

- [ ] 15. Remove SwiftLint Disables + Verify File Sizes

  **What to do**:
  - Remove `// swiftlint:disable file_length type_body_length` from `Hush/AppContainer.swift` (line 7)
  - Remove matching `// swiftlint:enable file_length type_body_length` from end of file
  - Verify ALL files meet SwiftLint thresholds:
    - No file exceeds 600 lines (warning) in newly created files
    - No file exceeds 900 lines (error) in any file
    - AppContainer.swift specifically < 900 lines
  - Run `make fmt` to verify SwiftLint passes clean without the disables
  - If any file still exceeds limits, split further before removing the disable

  **Must NOT do**:
  - Do not remove disables from files that still exceed limits (split first)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4
  - **Blocks**: Task 16
  - **Blocked By**: Task 14

  **References**:
  - `Hush/AppContainer.swift:7` — `// swiftlint:disable file_length type_body_length`
  - `.swiftlint.yml` — File length warning 600, error 900; type body warning 250, error 350

  **Acceptance Criteria**:

  ```
  Scenario: SwiftLint disables removed, all files within limits
    Tool: Bash
    Steps:
      1. Run `grep -r "swiftlint:disable file_length" Hush/` — must return empty
      2. Run `wc -l Hush/AppContainer.swift` — must be < 900
      3. Run `find Hush/Views -name "*.swift" -exec wc -l {} + | sort -rn | head -5` — all < 600
      4. Run `make fmt` — must produce zero changes
      5. Run `make build && make test`
    Expected Result: No SwiftLint disables, all files within limits, BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-15-lint-clean.txt
  ```

  **Commit**: YES
  - Message: `refactor: remove swiftlint file_length disables, verify size targets`
  - Files: `AppContainer.swift` (modified)
  - Pre-commit: `make build && make test && make fmt`

- [ ] 16. Update All AGENTS.md Files

  **What to do**:
  - Update `Hush/HushCore/AGENTS.md`:
    - Add `SettingsDTOs.swift` to structure listing
    - Update "Where to Look" table
  - Update `Hush/Views/AGENTS.md`:
    - Add new files to structure: `GlassEffectSurfaces.swift`, `ChromeMaterials.swift`, `ChatParameterControls.swift`, `ComposerModelService.swift`, `ProviderModelSelector.swift`
    - Add `Settings/Components/` directory with `SettingsListRow.swift`, `EmptyStateView.swift`
    - Update split files: `ProviderCatalogLogic.swift`, `ProviderEditorState.swift`, `ProviderSettingsDetailPane.swift`, `ProviderSettingsActionBar.swift`, `AgentPresetDetailSheet.swift`, `AgentPresetActions.swift`
  - Update root `AGENTS.md`:
    - Update Architecture section to reflect AppContainer extension files
    - Add `AppContainer+MessageBuckets.swift`, `AppContainer+ProviderManagement.swift`, `AppContainer+Catalog.swift`, `AppContainer+ConversationLifecycle.swift`, `AppContainer+SendPipeline.swift`
    - Note that root `HushCore/` directory has been removed
  - Verify doc accuracy by running `find` against actual file structure

  **Must NOT do**:
  - Do not change any code
  - Do not create new documentation files beyond updating existing AGENTS.md

  **Recommended Agent Profile**:
  - **Category**: `writing`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (last implementation task)
  - **Blocks**: F1-F4
  - **Blocked By**: Task 15

  **References**:
  - `AGENTS.md` (root) — Global architecture map
  - `Hush/HushCore/AGENTS.md` — HushCore module docs
  - `Hush/Views/AGENTS.md` — Views module docs
  - `Hush/Views/Chat/AppKit/AGENTS.md` — AppKit views docs (may need minor update)

  **Acceptance Criteria**:

  ```
  Scenario: All AGENTS.md files reflect new structure
    Tool: Bash
    Steps:
      1. Run `grep "AppContainer+MessageBuckets" AGENTS.md` — must find reference
      2. Run `grep "SettingsDTOs" Hush/HushCore/AGENTS.md` — must find reference
      3. Run `grep "GlassEffectSurfaces" Hush/Views/AGENTS.md` — must find reference
      4. Run `grep "ComposerModelService" Hush/Views/AGENTS.md` — must find reference
      5. Run `grep "SettingsListRow" Hush/Views/AGENTS.md` — must find reference
      6. Run `make build && make test`
    Expected Result: All docs accurate, BUILD SUCCEEDED
    Evidence: .sisyphus/evidence/task-16-docs-updated.txt
  ```

  **Commit**: YES
  - Message: `docs: update AGENTS.md hierarchy to reflect new structure`
  - Files: `AGENTS.md`, `Hush/HushCore/AGENTS.md`, `Hush/Views/AGENTS.md`
  - Pre-commit: `make build && make test`

---

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.

- [ ] F1. **Plan Compliance Audit** — `oracle`

  **What to do**: Read the plan end-to-end. Verify every "Must Have" and "Must NOT Have". Check evidence files.

  **Recommended Agent Profile**:
  - **Dispatch**: `subagent_type="oracle"` (read-only consultation agent, not a category)
  - **Skills**: []

  **QA Scenarios**:

  ```
  Scenario: All "Must Have" criteria met
    Tool: Bash
    Steps:
      1. Run `make build 2>&1 | tail -1` — expect `** BUILD SUCCEEDED **`
      2. Run `make test 2>&1 | grep -c "failed"` — expect 0
      3. Run `make fmt && git diff --stat` — expect no changes
      4. Run `wc -l Hush/AppContainer.swift` — expect < 900
      5. Run `find Hush/Views -name "*.swift" -exec wc -l {} + | awk '$1 > 600 {print}'` — expect empty
      6. Run `grep -r "swiftlint:disable file_length" Hush/` — expect empty
      7. Run `grep "import " Hush/HushCore/SettingsDTOs.swift` — expect only `import Foundation`
    Expected Result: All 7 checks pass
    Evidence: .sisyphus/evidence/f1-must-have-audit.txt

  Scenario: All "Must NOT Have" guardrails enforced
    Tool: Bash
    Steps:
      1. Run `grep -rn "ViewModel" Hush/Views/ --include="*.swift" | grep -v "AGENTS.md"` — expect empty (no ViewModel introduced)
      2. Run `git diff HEAD~16..HEAD -- Hush/RequestCoordinator.swift | head -5` — expect empty or minimal (internal structure untouched)
      3. Run `git diff HEAD~16..HEAD -- Hush/HushStorage/ Hush/HushProviders/ Hush/HushNetworking/ Hush/HushRendering/ | wc -l` — expect 0 (internals untouched)
      4. Run `grep -rn "swiftlint:disable" Hush/ --include="*.swift" | grep "file_length\|type_body_length"` — expect empty
    Expected Result: All 4 checks pass — no forbidden patterns found
    Evidence: .sisyphus/evidence/f1-must-not-have-audit.txt
  ```

  Output: `Must Have [7/7] | Must NOT Have [4/4] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`

  **What to do**: Run build + test + lint. Review changed files for code smells.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **QA Scenarios**:

  ```
  Scenario: Build, test, lint all pass clean
    Tool: Bash
    Steps:
      1. Run `make build 2>&1 | tail -1` — expect `** BUILD SUCCEEDED **`
      2. Run `make test 2>&1 | grep -E "passed|failed"` — expect all passed, 0 failed
      3. Run `make fmt && git diff --stat` — expect no changes (already formatted)
      4. Run `swiftlint lint --reporter json Hush/ 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'violations: {len(d)}')"` — expect violations: 0
    Expected Result: Build PASS, Tests PASS (600+ pass, 0 fail), Lint PASS (0 violations)
    Evidence: .sisyphus/evidence/f2-build-test-lint.txt

  Scenario: No code quality anti-patterns in new/changed files
    Tool: Bash
    Steps:
      1. Run `git diff HEAD~16..HEAD --name-only | xargs grep -l "as! \|as any\|@ts-ignore\|TODO.*hack\|FIXME.*hack" 2>/dev/null` — expect empty
      2. Run `git diff HEAD~16..HEAD --name-only | xargs grep -l "// swiftlint:disable" 2>/dev/null` — expect empty
      3. Run `git diff HEAD~16..HEAD --name-only --diff-filter=A` — list new files, verify each < 600 lines via `wc -l`
    Expected Result: No unsafe casts, no new lint disables, all new files < 600 lines
    Evidence: .sisyphus/evidence/f2-code-quality.txt
  ```

  Output: `Build [PASS/FAIL] | Tests [N pass/N fail] | Lint [PASS/FAIL] | Quality [CLEAN/N issues] | VERDICT`

- [ ] F3. **Runtime Smoke Test** — `unspecified-high` (+ `screenshot` skill)

  **What to do**: Build app, launch it, capture screenshot to verify it starts without crash. Run key functional tests.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: [`screenshot`]

  **QA Scenarios**:

  ```
  Scenario: App launches without crash
    Tool: Bash + screenshot skill
    Steps:
      1. Run `make build` — expect BUILD SUCCEEDED
      2. Run `open /tmp/hush-dd/Build/Products/Debug/Hush.app` — launch the app
      3. Wait 5 seconds for app to start
      4. Use screenshot skill to capture full desktop screenshot
      5. Run `pgrep -f "Hush.app" | head -1` — expect a PID (app is running)
      6. Run `killall Hush 2>/dev/null` — cleanup
    Expected Result: App PID exists (not crashed), screenshot shows Hush window
    Evidence: .sisyphus/evidence/f3-app-launch.png

  Scenario: Key test suites pass (functional verification)
    Tool: Bash
    Steps:
      1. Run `xcodebuild test -project Hush.xcodeproj -scheme Hush -configuration Debug -derivedDataPath /tmp/hush-dd -clonedSourcePackagesDirPath /tmp/hush-spm -only-testing:"HushTests/RequestSchedulerTests" 2>&1 | grep -E "passed|failed"` — expect all passed
      2. Run `xcodebuild test -project Hush.xcodeproj -scheme Hush -configuration Debug -derivedDataPath /tmp/hush-dd -clonedSourcePackagesDirPath /tmp/hush-spm -only-testing:"HushTests/ProviderSettingsViewTests" 2>&1 | grep -E "passed|failed"` — expect all passed
      3. Run `xcodebuild test -project Hush.xcodeproj -scheme Hush -configuration Debug -derivedDataPath /tmp/hush-dd -clonedSourcePackagesDirPath /tmp/hush-spm -only-testing:"HushTests/QuickBarRoutingTests" 2>&1 | grep -E "passed|failed"` — expect all passed
    Expected Result: RequestScheduler (8 tests), ProviderSettings (12 tests), QuickBarRouting tests all pass
    Evidence: .sisyphus/evidence/f3-key-tests.txt
  ```

  Output: `App Launch [PASS/FAIL] | Key Tests [N/N pass] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`

  **What to do**: Compare git diff against plan spec. Verify nothing extra, nothing missing.

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []

  **QA Scenarios**:

  ```
  Scenario: All planned file operations completed
    Tool: Bash
    Steps:
      1. Run `test -f Hush/HushCore/SettingsDTOs.swift && echo "EXISTS"` — expect EXISTS
      2. Run `test -f Hush/Views/Settings/Components/SettingsListRow.swift && echo "EXISTS"` — expect EXISTS
      3. Run `test -f Hush/Views/Settings/Components/EmptyStateView.swift && echo "EXISTS"` — expect EXISTS
      4. Run `test -f Hush/AppContainer+MessageBuckets.swift && echo "EXISTS"` — expect EXISTS
      5. Run `test -f Hush/AppContainer+ProviderManagement.swift && echo "EXISTS"` — expect EXISTS
      6. Run `test -f Hush/AppContainer+Catalog.swift && echo "EXISTS"` — expect EXISTS
      7. Run `test -f Hush/AppContainer+ConversationLifecycle.swift && echo "EXISTS"` — expect EXISTS
      8. Run `test -f Hush/AppContainer+SendPipeline.swift && echo "EXISTS"` — expect EXISTS
      9. Run `test -f Hush/Views/GlassEffectSurfaces.swift && echo "EXISTS"` — expect EXISTS
      10. Run `test -f Hush/Views/ChromeMaterials.swift && echo "EXISTS"` — expect EXISTS
      11. Run `test -f Hush/Views/Chat/ComposerModelService.swift && echo "EXISTS"` — expect EXISTS
      12. Run `test -f Hush/Views/Chat/ProviderModelSelector.swift && echo "EXISTS"` — expect EXISTS
      13. Run `test ! -f HushCore/PerfTrace.swift && echo "DELETED"` — expect DELETED
    Expected Result: All 12 new files exist, 1 orphan deleted
    Evidence: .sisyphus/evidence/f4-file-operations.txt

  Scenario: No unplanned files changed
    Tool: Bash
    Steps:
      1. Run `git diff HEAD~16..HEAD --name-only --diff-filter=M | sort` — list modified files
      2. Verify modified files are ONLY: `AppContainer.swift`, `project.pbxproj`, View files being split, `AGENTS.md` files, `ComposerDock.swift`, `QuickBarComposer.swift`
      3. Run `git diff HEAD~16..HEAD -- Hush/HushStorage/ | wc -l` — expect 0
      4. Run `git diff HEAD~16..HEAD -- Hush/HushProviders/ | wc -l` — expect 0
      5. Run `git diff HEAD~16..HEAD -- Hush/HushNetworking/ | wc -l` — expect 0
      6. Run `git diff HEAD~16..HEAD -- Hush/HushRendering/ | wc -l` — expect 0
    Expected Result: No changes to out-of-scope modules (Storage, Providers, Networking, Rendering)
    Evidence: .sisyphus/evidence/f4-scope-fidelity.txt

  Scenario: Test count unchanged — no tests deleted or broken
    Tool: Bash
    Steps:
      1. Run `grep -r "@Test" HushTests/ --include="*.swift" | wc -l` — count all @Test declarations in source files
      2. Verify the count is >= 600 (known baseline: 77 test files, 600+ test cases)
      3. Run `grep -r "@Suite" HushTests/ --include="*.swift" | wc -l` — count all test suites
      4. Run `make test 2>&1 | tail -20` — verify test run completes with 0 failures
      5. Run `git log --oneline HEAD~16..HEAD | wc -l` — verify exactly 16 commits (one per task)
    Expected Result: @Test count >= 600, @Suite count matches test file count, 0 test failures, 16 commits
    Evidence: .sisyphus/evidence/f4-test-count.txt
  ```

  Output: `Files [13/13 created, 1/1 deleted] | Scope [CLEAN/N issues] | Tests [same count] | VERDICT`

---

## Commit Strategy

| Commit | Message | Pre-commit Check |
|--------|---------|------------------|
| 1 | `chore: format codebase for clean refactoring baseline` | `make fmt` |
| 2 | `chore: delete orphan root HushCore/PerfTrace.swift` | `make build && make test` |
| 3 | `refactor(core): extract DTOs from AppContainer to HushCore` | `make build && make test` |
| 4 | `refactor(views): create shared Settings components (SettingsListRow, EmptyStateView)` | `make build && make test` |
| 5 | `refactor(views): split ProviderSettingsView into focused files` | `make build && make test` |
| 6 | `refactor(views): split ThemeChrome into glass/materials/utilities` | `make build && make test` |
| 7 | `refactor(views): split AgentSettingsView into list/detail/actions` | `make build && make test` |
| 8 | `refactor(views): split ChatConfigPopover into header and parameter controls` | `make build && make test` |
| 9 | `refactor(views): consolidate composer duplication with shared components` | `make build && make test` |
| 10 | `refactor(container): extract AppContainer+MessageBuckets` | `make build && make test` |
| 11 | `refactor(container): extract AppContainer+ProviderManagement` | `make build && make test` |
| 12 | `refactor(container): extract AppContainer+Catalog` | `make build && make test` |
| 13 | `refactor(container): extract AppContainer+ConversationLifecycle` | `make build && make test` |
| 14 | `refactor(container): extract AppContainer+SendPipeline` | `make build && make test` |
| 15 | `refactor: remove swiftlint file_length disables, verify size targets` | `make build && make test && make fmt` |
| 16 | `docs: update AGENTS.md hierarchy to reflect new structure` | `make build && make test` |

---

## Success Criteria

### Verification Commands
```bash
make build    # Expected: ** BUILD SUCCEEDED **
make test     # Expected: All 600+ tests pass, 0 failures
make fmt      # Expected: zero changes
wc -l Hush/AppContainer.swift  # Expected: < 900
find Hush/Views -name "*.swift" -exec wc -l {} + | sort -rn | head -5  # Expected: all < 600
grep -r "swiftlint:disable file_length" Hush/  # Expected: no results
```

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] All tests pass (same count as before refactoring)
- [ ] No file exceeds SwiftLint thresholds
- [ ] All AGENTS.md files updated
