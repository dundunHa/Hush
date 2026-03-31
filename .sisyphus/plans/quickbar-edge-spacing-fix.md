# Quick Bar 外边距对称性修复计划

## TL;DR

> **Quick Summary**: 修复 Quick Bar 中 assistant 消息相对左侧 transcript 边界、user 消息相对右侧 transcript 边界的视觉距离不一致问题。先补“outer-edge 对称性”自动化验证，再根据首次出现偏差的层级做最小范围修复。
>
> **Deliverables**:
> - 新增/更新 Quick Bar outer-edge 对称性测试
> - 定位偏差首次出现的层级（container / body / visible text / mode split）
> - 只在命中的层级做最小修复
> - 全量 build/test/fmt 通过
>
> **Estimated Effort**: Short
> **Parallel Execution**: YES - 3 waves
> **Critical Path**: Task 1 → Task 2/3/4 → Task 5/6/7 → Task 8 → Task 9 → F1-F4

---

## Context

### Original Request
用户指出 Quick Bar 中 assistant 消息距离左侧边框、user 消息距离右侧边框看起来不一致，并在前一轮修复后继续反馈“还是存在问题,仔细梳理,然后思考怎么修复”。

### Interview Summary
**Key Discussions**:
- 之前的修复主要调整了 readable width 与 compact lane sizing，但未命中用户看到的 outer-edge 视觉问题。
- 当前更可能的问题不是单纯 `maxWidth`，而是“验证边界选错”或“visible text 边界与容器几何不一致”。
- 用户确认本次采用 **先补测试，再围绕测试设计修复方案**。

**Research Findings**:
- Quick Bar 路径：`QuickBarPanelView` → `QuickConversationSurface` → `ConversationViewController` → `MessageTableView` → `QuickBarMessageCellView`
- 现有测试主要验证 AppKit cell 内部几何，没有验证 visible text 相对 transcript shell 外边界的镜像关系。
- `QuickBarMessageCellView` 中 assistant / user 的模式分流不同：user 多为 `.trailingColumn`，assistant 可能是 `.leadingColumn` 或 `.fullWidth` / waiting。
- 用户截图已证明 waiting-state assistant 也在问题范围内。

### Metis Review
**Identified Gaps** (addressed):
- 必须显式锁定“外边界参照系”，不能继续只测 cell 内部几何。
- 必须覆盖 waiting-state、compact plain text、fullWidth/rich assistant 三类模式，否则容易误判根因。
- 不应先改 `QuickBarPanelView` padding；只有在 inner layers 全对称时才允许动 panel 层。
- 不应盲调 `sideInset`/`contentMaxWidth`；要先用 RED 测试判断首次出现偏差的层级。

---

## Work Objectives

### Core Objective
建立 Quick Bar transcript outer-edge 对称性的自动化规范，并据此修复 assistant/user 消息的实际视觉边距不一致问题。

### Concrete Deliverables
- `HushTests/QuickBarTranscriptSymmetryTests.swift`（或等价的新/扩展测试文件）
- `HushTests/MessageBodyAlignmentTests.swift` 的 outer-edge 断言更新
- `Hush/Views/Chat/AppKit/MessageTableView.swift` 中 Quick Bar 命中的最小修复
- 如需要，`MessageBodyTextView.visibleTextBounds()` 或 Quick Bar 专用调试访问器的最小修复

### Definition of Done
- [ ] 存在 outer-edge 对称性测试，直接比较 assistant 左可见间距 与 user 右可见间距
- [ ] waiting-state、compact plain text、fullWidth/rich assistant 至少各有一条自动化断言
- [ ] 命中的最小修复通过所有新旧测试
- [ ] `make build` → BUILD SUCCEEDED
- [ ] `make test` → 全部通过
- [ ] `make fmt` → 无额外格式问题

### Must Have
- 使用统一外层参照边界验证对称性
- 先 RED 再 GREEN，再做整理
- 修复范围优先限制在 Quick Bar 渲染路径
- 保留 main chat 行为不变

### Must NOT Have (Guardrails)
- ❌ 在未确认偏差层级前直接改 `QuickBarPanelView` 的 padding 链
- ❌ 盲目调整 `QuickBarTranscriptMetrics.sideInset` 或 `contentMaxWidth`
- ❌ 触碰 `MessageTableCellView` 主聊天路径
- ❌ 使用人工肉眼作为唯一验收标准
- ❌ 引入 snapshot/UI test 基建扩张到本次范围之外

---

## Verification Strategy (MANDATORY)

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed.

### Test Decision
- **Infrastructure exists**: YES
- **Automated tests**: YES（TDD）
- **Framework**: Swift Testing
- **Strategy**: 先补 outer-edge 对称性 RED 测试，再做最小修复，再跑 targeted + full suite

### QA Policy
每个任务都必须包含 agent-executed QA 场景，并保存证据到 `.sisyphus/evidence/`。

- **Layout/Test verification**: `xcodebuild test` / `make test`
- **Build verification**: `make build`
- **Formatting verification**: `make fmt`
- **Evidence**: 测试输出、关键 gap 数值、build/fmt 结果

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — verification foundation):
├── Task 1: 建立 outer-edge 对称性测量辅助 [quick]
├── Task 2: 补 compact plain-text 对称性 RED 测试 [quick]
├── Task 3: 补 waiting-state / fullWidth 对称性 RED 测试 [quick]
└── Task 4: 如有缺口，补 Quick Bar debug-only 投影访问器 [quick]

Wave 2 (After Wave 1 — smallest-scope fix):
├── Task 5: 收敛 Quick Bar readable rect / container 几何来源 [unspecified-high]
├── Task 6: 修正 Quick Bar body lane 镜像约束 [unspecified-high]
└── Task 7: 修正 visible text / mode-specific 偏差 [unspecified-high]

Wave 3 (After Wave 2 — harden + regression):
├── Task 8: 更新旧有对齐测试与复用场景回归 [quick]
└── Task 9: 全量验证与证据收集 [quick]

Wave FINAL (After ALL tasks — 4 parallel reviews):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real manual QA (unspecified-high)
└── Task F4: Scope fidelity check (deep)

Critical Path: 1 → 2/3/4 → 5/6/7 → 8 → 9 → F1-F4
Parallel Speedup: ~45%
Max Concurrent: 4
```

### Dependency Matrix

- **1**: — → 2, 3, 4, 5, 6, 7
- **2**: 1 → 5, 6, 7, 8
- **3**: 1 → 5, 6, 7, 8
- **4**: 1 → 5, 6, 7
- **5**: 1, 2, 3, 4 → 8, 9
- **6**: 1, 2, 3, 4 → 8, 9
- **7**: 1, 2, 3, 4 → 8, 9
- **8**: 2, 3, 5, 6, 7 → 9
- **9**: 5, 6, 7, 8 → F1, F2, F3, F4

### Agent Dispatch Summary

- **Wave 1**: 4 × `quick`
- **Wave 2**: 3 × `unspecified-high`
- **Wave 3**: 2 × `quick`
- **FINAL**: `oracle` + `unspecified-high` + `unspecified-high` + `deep`

---

## TODOs

- [x] 1. 建立 Quick Bar outer-edge 对称性测量辅助

  **What to do**:
  - 在测试侧定义统一外层参照边界，使用 `QuickBarPanelReleaseMetrics.width`、`QuickBarPanelView` transcript padding 推导真实 transcript 可读区域。
  - 增加将 `contentContainerFrameForTesting` / `bodyFrameForTesting` / `visibleTextFrameForTesting` 投影到共享外层坐标系的辅助方法。
  - 统一容差（建议 `<= 1.0px`）。

  **Must NOT do**:
  - 不要先改生产代码几何常量。
  - 不要把 panel 阴影当成主修复手段。

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 测试辅助与坐标投影属于低风险、单一关注点工作。
  - **Skills**: `[]`
  - **Skills Evaluated but Omitted**:
    - `playwright`: 本任务不是浏览器 UI 自动化。

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4)
  - **Blocks**: 2, 3, 4, 5, 6, 7
  - **Blocked By**: None

  **References**:
  - `Hush/Views/Chat/QuickBar/QuickBarPanelView.swift:66-82` - transcript shell padding 链与 outer visible region 来源。
  - `Hush/Views/Chat/QuickBar/QuickBarComposerSupport.swift:3-6` - Quick Bar 固定面板宽度来源。
  - `HushTests/MessageBodyAlignmentTests.swift:61-98` - 现有 `hostCell()` 测试承载方式。
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:4876-4952` - Quick Bar debug testing getters。

  **Acceptance Criteria**:
  - [ ] 新测试辅助能在同一坐标系下得到 assistant left gap / user right gap。
  - [ ] 所有 gap 比较使用统一容差，且不硬编码重复几何常量。

  **QA Scenarios**:
  ```
  Scenario: Outer-edge helper computes shared reference bounds
    Tool: Bash (xcodebuild test)
    Preconditions: New/updated test helper compiled into Swift Testing target
    Steps:
      1. Run xcodebuild test for the symmetry-focused suite/file.
      2. Assert the helper-based tests compile and execute.
      3. Capture any printed/measured gap values in test output.
    Expected Result: Test target builds; helper-backed assertions run.
    Failure Indicators: Compile error, missing accessor, coordinate conversion mismatch.
    Evidence: .sisyphus/evidence/task-1-outer-edge-helper.txt

  Scenario: Helper does not require production geometry changes
    Tool: Bash (xcodebuild test)
    Preconditions: Only test/debug code changed for this task.
    Steps:
      1. Run the same targeted suite.
      2. Verify no production-file fix is required yet for helper compilation.
    Expected Result: RED/GREEN may vary, but test infrastructure executes without forcing unrelated production edits.
    Evidence: .sisyphus/evidence/task-1-helper-no-prod-change.txt
  ```

  **Commit**: YES
  - Message: `test(quickbar): add transcript symmetry helpers`
  - Files: `HushTests/MessageBodyAlignmentTests.swift` or new helper file
  - Pre-commit: targeted `xcodebuild test`

- [x] 2. 补 compact plain-text 对称性 RED 测试

  **What to do**:
  - 为短文本与长文本各增加至少一组 mirror 测试。
  - 直接比较 assistant 左 visible gap 与 user 右 visible gap，而不是只比较 body 相对 contentContainer。
  - 使用相近长度样本文本，避免内容长度差异污染几何判断。

  **Must NOT do**:
  - 不要继续仅验证 `contentContainer` 内部贴边关系。

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 纯测试补充，关注 Quick Bar compact plain-text 场景。
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3, 4)
  - **Blocks**: 5, 6, 7, 8
  - **Blocked By**: 1

  **References**:
  - `HushTests/MessageBodyAlignmentTests.swift:180-379` - 现有 quick bar user/assistant compact 场景。
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:4090-4160` - `.leadingColumn` / `.trailingColumn` 与 `preferredSideColumnWidth`。

  **Acceptance Criteria**:
  - [ ] 至少 2 条 compact plain-text symmetry 测试先 RED，再为后续修复提供定位信号。
  - [ ] 测试断言直接比较 outer-edge visible gap 差值。

  **QA Scenarios**:
  ```
  Scenario: Compact plain-text symmetry tests fail before fix
    Tool: Bash (xcodebuild test)
    Preconditions: Task 1 helper available
    Steps:
      1. Run the targeted symmetry tests for short and long compact rows.
      2. Observe the numeric gap delta reported by the new assertions.
    Expected Result: At least one symmetry assertion fails on current code, proving the bug is measurable.
    Failure Indicators: Tests pass unexpectedly without measuring outer-edge gaps, or compare wrong frames.
    Evidence: .sisyphus/evidence/task-2-compact-red.txt

  Scenario: Mirror cases use comparable sample lengths
    Tool: Bash (xcodebuild test)
    Preconditions: Compact tests use deliberate sample strings.
    Steps:
      1. Run targeted suite.
      2. Confirm no test relies on unrelated markdown/rich rendering branches.
    Expected Result: Failures isolate compact lane geometry only.
    Evidence: .sisyphus/evidence/task-2-compact-samples.txt
  ```

  **Commit**: YES
  - Message: `test(quickbar): add compact symmetry coverage`
  - Files: `HushTests/MessageBodyAlignmentTests.swift` or new symmetry suite
  - Pre-commit: targeted `xcodebuild test`

- [x] 3. 补 waiting-state / fullWidth 对称性 RED 测试

  **What to do**:
  - 覆盖用户截图已证明的 waiting-state assistant 对 user trailing message 场景。
  - 覆盖 rich/fullWidth assistant 对 user trailing message 场景，避免只修 compact leadingColumn。
  - 让测试输出明确标识首次出现偏差的模式类别。

  **Must NOT do**:
  - 不要把 waiting-state 当作 compact plain text 的等价替代。

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 模式覆盖扩展，仍属于测试侧工作。
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 4)
  - **Blocks**: 5, 6, 7, 8
  - **Blocked By**: 1

  **References**:
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:4078-4098` - assistant waiting/fullWidth 分流条件。
  - `HushTests/MessageBodyAlignmentTests.swift:475-512` - 现有 waiting-state 覆盖但缺 outer-edge 比较。
  - `HushTests/MessageBodyAlignmentTests.swift:418-473` - rich→plain reuse 场景。

  **Acceptance Criteria**:
  - [ ] waiting-state 场景有 outer-edge 对称性断言。
  - [ ] fullWidth/rich assistant 场景有 outer-edge 对称性断言。

  **QA Scenarios**:
  ```
  Scenario: Waiting-state asymmetry becomes numerically measurable
    Tool: Bash (xcodebuild test)
    Preconditions: New waiting-state symmetry test added
    Steps:
      1. Run targeted symmetry suite.
      2. Record assistant waiting left gap and user right gap.
    Expected Result: The bug is measurable in waiting-state if that is the offending branch.
    Failure Indicators: Test only checks alignment style, not outer-edge gaps.
    Evidence: .sisyphus/evidence/task-3-waiting-red.txt

  Scenario: FullWidth assistant branch is separately validated
    Tool: Bash (xcodebuild test)
    Preconditions: Rich/fullWidth assistant sample included
    Steps:
      1. Run targeted symmetry suite.
      2. Verify the fullWidth-specific test path executes.
    Expected Result: The suite reports whether fullWidth contributes to asymmetry.
    Evidence: .sisyphus/evidence/task-3-fullwidth-red.txt
  ```

  **Commit**: YES
  - Message: `test(quickbar): cover waiting and fullwidth symmetry`
  - Files: `HushTests/MessageBodyAlignmentTests.swift` or new symmetry suite
  - Pre-commit: targeted `xcodebuild test`

- [x] 4. 补 Quick Bar debug-only 投影访问器（如现有 getter 不足）

  **What to do**:
  - 若现有 testing getter 无法直接表达 table/transcript 共享坐标系，则仅在 DEBUG/testing 路径补最小访问器。
  - 访问器只暴露测量必需信息，不泄漏无关内部实现。

  **Must NOT do**:
  - 不要给生产逻辑添加仅为运行期 UI 服务的复杂分支。

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: debug-only accessor 是低风险小改动。
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3)
  - **Blocks**: 5, 6, 7
  - **Blocked By**: 1

  **References**:
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:4712-4952` - 当前 testing row view 工具链。
  - `HushTests/MessageTableViewSurfaceStyleTests.swift:85-131` - 现有 contentContainer 投影到 table 的例子。

  **Acceptance Criteria**:
  - [ ] 如需新 getter，其作用域为 DEBUG/testing only。
  - [ ] 测试可无需复制生产坐标计算逻辑也能比较 outer-edge gap。

  **QA Scenarios**:
  ```
  Scenario: Debug-only accessor supports outer-edge assertions
    Tool: Bash (xcodebuild test)
    Preconditions: New getter added only if necessary
    Steps:
      1. Run targeted symmetry tests.
      2. Confirm the new tests can access required projected frames/gaps.
    Expected Result: Tests compile and use the accessor without touching release behavior.
    Failure Indicators: Accessor leaks into non-DEBUG paths or still cannot measure outer-edge gaps.
    Evidence: .sisyphus/evidence/task-4-debug-accessor.txt

  Scenario: No release-surface behavior changes
    Tool: Bash (xcodebuild test)
    Preconditions: Accessor changes are debug-gated.
    Steps:
      1. Run existing surface-style tests.
      2. Confirm Quick Bar row presentation behavior remains unchanged before the actual fix.
    Expected Result: Existing tests continue to reflect current production behavior.
    Evidence: .sisyphus/evidence/task-4-no-release-change.txt
  ```

  **Commit**: YES
  - Message: `test(quickbar): expose symmetry debug geometry`
  - Files: `Hush/Views/Chat/AppKit/MessageTableView.swift`
  - Pre-commit: targeted `xcodebuild test`

- [ ] 5. 收敛 Quick Bar readable rect / container 几何来源

  **What to do**:
  - 基于 RED 测试结果，若首次偏差出现在 `contentContainer` / body rect 之前，统一 Quick Bar readable rect 的真实来源。
  - 优先让 Quick Bar row 使用单一可推导的 outer readable rect，而不是多处重复推导宽度。
  - 保持修复最小化，仅触及命中的几何层。

  **Must NOT do**:
  - 不要在证据表明 inner layers 对称时去改 panel padding。

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: 需要结合约束、坐标与 Quick Bar 几何来源做小范围修复。
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 6, 7)
  - **Blocks**: 8, 9
  - **Blocked By**: 1, 2, 3, 4

  **References**:
  - `Hush/Views/Chat/QuickBar/QuickBarPanelView.swift:66-82` - transcript shell padding 真相源。
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:81-90` - `QuickBarTranscriptMetrics` 常量。
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:3634-3653` - `contentContainer` 宽度与居中约束。
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:328-334` - `maxContentWidth(for: .quickBar)`。

  **Acceptance Criteria**:
  - [ ] 若几何层是根因，readable rect 来源被收敛到单一逻辑源。
  - [ ] compact / waiting / fullWidth 模式共用一致 outer reference。

  **QA Scenarios**:
  ```
  Scenario: Geometry-source fix turns RED symmetry tests GREEN
    Tool: Bash (xcodebuild test)
    Preconditions: Wave 1 RED tests in place
    Steps:
      1. Apply the minimal geometry-source fix.
      2. Run targeted symmetry suite.
      3. Compare assistant/user outer-edge gap deltas.
    Expected Result: Targeted symmetry tests pass within tolerance.
    Failure Indicators: Gaps still diverge, or unrelated layout tests regress.
    Evidence: .sisyphus/evidence/task-5-geometry-green.txt

  Scenario: Quick Bar readable column remains centered
    Tool: Bash (xcodebuild test)
    Preconditions: Existing surface-style tests available
    Steps:
      1. Run `MessageTableViewSurfaceStyleTests`.
      2. Verify centered readable-column invariants still hold unless intentionally superseded by updated tests.
    Expected Result: No accidental drift of the readable region.
    Evidence: .sisyphus/evidence/task-5-readable-center.txt
  ```

  **Commit**: YES
  - Message: `fix(quickbar): unify transcript readable geometry`
  - Files: `Hush/Views/Chat/AppKit/MessageTableView.swift` (+ tests if needed)
  - Pre-commit: targeted `xcodebuild test`

- [ ] 6. 修正 Quick Bar body lane 镜像约束

  **What to do**:
  - 若 RED 测试显示偏差首次出现在 `bodyFrame` 层，统一 `.leadingColumn` / `.trailingColumn` / `.fullWidth` / waiting 的 lane helper 或约束激活方式。
  - 保证 assistant 与 user 在镜像模式下使用等价的 body 边距语义。

  **Must NOT do**:
  - 不要顺手重写 `preferredSideColumnWidth` 整体算法，除非测试证明它是根因。

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: 约束层修复需要谨慎避免 reuse / mode transition 回归。
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 7)
  - **Blocks**: 8, 9
  - **Blocked By**: 1, 2, 3, 4

  **References**:
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:3674-3715` - body / meta / preview 约束定义。
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:4100-4139` - `applyPresentation(for:maxBodyWidth:)`。
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:4141-4160` - `preferredSideColumnWidth(maxBodyWidth:)`。

  **Acceptance Criteria**:
  - [ ] 若 bodyFrame 是首个偏差层，修复后 compact / waiting / fullWidth 的 body-level symmetry 通过。
  - [ ] rich→plain reuse 与 waiting transition 无回归。

  **QA Scenarios**:
  ```
  Scenario: Body-lane fix resolves mirrored compact/waiting gaps
    Tool: Bash (xcodebuild test)
    Preconditions: Body-level asymmetry confirmed by RED tests
    Steps:
      1. Apply the minimal lane-constraint fix.
      2. Run targeted compact + waiting symmetry tests.
      3. Verify gap delta is within tolerance.
    Expected Result: Mirrored lane scenarios pass.
    Failure Indicators: One side remains farther in body-level measurements.
    Evidence: .sisyphus/evidence/task-6-lane-green.txt

  Scenario: Mode transitions keep correct lane geometry
    Tool: Bash (xcodebuild test)
    Preconditions: Existing rich→plain reuse test retained
    Steps:
      1. Run targeted reuse regression tests.
      2. Confirm quick bar cells reapply trailing/leading geometry after branch switches.
    Expected Result: No stale fullWidth/column geometry on reused cells.
    Evidence: .sisyphus/evidence/task-6-reuse.txt
  ```

  **Commit**: YES
  - Message: `fix(quickbar): mirror body lane constraints`
  - Files: `Hush/Views/Chat/AppKit/MessageTableView.swift`
  - Pre-commit: targeted `xcodebuild test`

- [ ] 7. 修正 visible text / mode-specific 偏差

  **What to do**:
  - 若 bodyFrame 对称但 `visibleTextBounds()` 不对称，则仅在文本测量层做最小修复。
  - 检查 waiting-state、rich/fullWidth、plain-text 三类模式下 visible text 的真实起止边界。
  - 必要时微调 Quick Bar 专用文本边界计算，而非放大全局 NSTextView 变更范围。

  **Must NOT do**:
  - 不要把全局主聊天文本测量一起改动。
  - 不要在没有证据的情况下修改段落样式生成逻辑。

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: 需要判断 glyph/visible bounds 与模式分流的交互。
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6)
  - **Blocks**: 8, 9
  - **Blocked By**: 1, 2, 3, 4

  **References**:
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:1696-1827` - `MessageBodyTextView`、`prepareMeasurementWidth`、`visibleTextBounds()`。
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:4061-4071` - plain text attributes and alignment generation.
  - `Hush/Views/Chat/AppKit/MessageTableView.swift:4078-4098` - mode split conditions。

  **Acceptance Criteria**:
  - [ ] 若可见文本边界是首个偏差层，修复后 outer-edge visible gap 对称性测试通过。
  - [ ] main chat 文本渲染与 Quick Bar rich rendering 无回归。

  **QA Scenarios**:
  ```
  Scenario: Visible-text fix resolves asymmetry without changing body geometry
    Tool: Bash (xcodebuild test)
    Preconditions: RED tests show bodyFrame symmetric but visibleText gaps diverge
    Steps:
      1. Apply the minimal visible-text fix.
      2. Run targeted symmetry suite.
      3. Confirm visible-gap assertions pass while body-level regression tests still pass.
    Expected Result: Only the visible-text-level mismatch is corrected.
    Failure Indicators: Needlessly altered body/container geometry or new rendering regressions.
    Evidence: .sisyphus/evidence/task-7-visible-green.txt

  Scenario: Rich/plain rendering remains stable
    Tool: Bash (xcodebuild test)
    Preconditions: Existing rich markdown alignment tests available
    Steps:
      1. Run MessageBodyAlignment-related suites.
      2. Verify rich markdown, waiting state, and plain text all remain valid.
    Expected Result: No regression in alignment or rendering caches.
    Evidence: .sisyphus/evidence/task-7-render-stability.txt
  ```

  **Commit**: YES
  - Message: `fix(quickbar): align visible text bounds`
  - Files: `Hush/Views/Chat/AppKit/MessageTableView.swift`
  - Pre-commit: targeted `xcodebuild test`

- [ ] 8. 更新旧有对齐测试与复用场景回归

  **What to do**:
  - 把旧测试中只关注 `contentContainer` 内部对齐的断言，补充或替换为 outer-edge 不变量。
  - 保留 rich→plain reuse、waiting-state、surface-style 这些已有回归价值的场景。
  - 清理已被新不变量替代的脆弱断言。

  **Must NOT do**:
  - 不要删除仍然有价值的 Quick Bar / surface-style 回归覆盖。

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 以测试整理和回归加固为主。
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: 9
  - **Blocked By**: 2, 3, 5, 6, 7

  **References**:
  - `HushTests/MessageBodyAlignmentTests.swift:263-473` - 现有 compact / reuse 回归。
  - `HushTests/MessageTableViewSurfaceStyleTests.swift:85-131` - centered readable column 断言。

  **Acceptance Criteria**:
  - [ ] 旧测试不再只停留于内部容器对齐，而能支持 outer-edge 视觉不变量。
  - [ ] 复用与 surface-style 回归仍被保留。

  **QA Scenarios**:
  ```
  Scenario: Updated regression tests remain focused and stable
    Tool: Bash (xcodebuild test)
    Preconditions: Fix tasks completed
    Steps:
      1. Run MessageBodyAlignment and MessageTableViewSurfaceStyle suites.
      2. Verify both new symmetry assertions and old regression scenarios pass.
    Expected Result: Regression coverage is stronger without becoming brittle.
    Failure Indicators: Overfitted assertions or loss of reuse/surface-style protection.
    Evidence: .sisyphus/evidence/task-8-regressions.txt

  Scenario: Waiting/rich/reuse scenarios all remain covered
    Tool: Bash (xcodebuild test)
    Preconditions: Existing regression cases retained or updated
    Steps:
      1. Run the targeted suites.
      2. Confirm coverage spans compact, waiting, fullWidth, and reuse paths.
    Expected Result: No important branch from the bug investigation is dropped.
    Evidence: .sisyphus/evidence/task-8-coverage.txt
  ```

  **Commit**: YES
  - Message: `test(quickbar): align regression assertions`
  - Files: `HushTests/MessageBodyAlignmentTests.swift`, `HushTests/MessageTableViewSurfaceStyleTests.swift`
  - Pre-commit: targeted `xcodebuild test`

- [ ] 9. 全量验证与证据收集

  **What to do**:
  - 跑 targeted suites、`make build`、`make test`、`make fmt`。
  - 保存关键输出，尤其是对称性 suite、全量测试、构建与格式化证据。
  - 若 targeted 绿但 full suite 红，先修回归再进入 Final Verification。

  **Must NOT do**:
  - 不要只跑 targeted tests 就宣布完成。

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: 验证与证据收集为主。
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential
  - **Blocks**: F1, F2, F3, F4
  - **Blocked By**: 5, 6, 7, 8

  **References**:
  - `README.md` - `make build`, `make test`, `make fmt` usage。
  - `HushTests/AGENTS.md` - Swift Testing conventions。

  **Acceptance Criteria**:
  - [ ] targeted symmetry suite PASS
  - [ ] `make build` PASS
  - [ ] `make test` PASS
  - [ ] `make fmt` clean
  - [ ] 所有证据文件写入 `.sisyphus/evidence/`

  **QA Scenarios**:
  ```
  Scenario: Targeted symmetry and regression suites pass
    Tool: Bash (xcodebuild test)
    Preconditions: All fix tasks completed
    Steps:
      1. Run targeted quick bar symmetry/alignment suites.
      2. Capture PASS output and any measured gaps.
    Expected Result: All targeted suites pass.
    Failure Indicators: Any remaining asymmetry failure or reuse/surface-style regression.
    Evidence: .sisyphus/evidence/task-9-targeted-pass.txt

  Scenario: Full repo verification passes
    Tool: Bash
    Preconditions: Code ready for full verification
    Steps:
      1. Run `make build`.
      2. Run `make test`.
      3. Run `make fmt`.
    Expected Result: Build succeeds, all tests pass, format/lint clean.
    Failure Indicators: Build break, failing suite, formatting drift.
    Evidence: .sisyphus/evidence/task-9-full-verification.txt
  ```

  **Commit**: NO
  - Message: `n/a`
  - Files: evidence only
  - Pre-commit: `make build && make test && make fmt`

---

## Final Verification Wave

> 4 review agents run in PARALLEL. ALL must APPROVE.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Verify the implemented fix matches this plan: outer-edge tests added, smallest-scope fix applied, main chat untouched, and evidence files present.

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run build/lint/tests, inspect changed Quick Bar / test files for overreach, dead code, or broad geometry changes outside scope.

- [ ] F3. **Real Manual QA** — `unspecified-high`
  Execute every QA scenario from Tasks 1-9, capture outputs and any screenshots/evidence needed to prove the numeric symmetry matches behavior.

- [ ] F4. **Scope Fidelity Check** — `deep`
  Confirm only Quick Bar alignment verification and minimal fix layers were changed; no unrelated UI redesign or main-chat regressions.

---

## Commit Strategy

- **1**: `test(quickbar): add transcript symmetry assertions`
- **2**: `fix(quickbar): correct transcript edge alignment`
- **3**: `test(quickbar): align regression coverage`

---

## Success Criteria

### Verification Commands
```bash
make build
make test
make fmt
```

### Final Checklist
- [ ] assistant 左 outer-edge visible gap 与 user 右 outer-edge visible gap 在容差内
- [ ] waiting-state 与 fullWidth 模式都被覆盖
- [ ] 无 main chat 回归
- [ ] 所有测试、构建、格式化通过
