# Chat 会话渲染性能/体验彻底优化（SwiftUI→可观测→Windowing→TextKit→兜底 AppKit）

> Status: Archived (2026-02-21)

## TL;DR

> **目标**：彻底解决 Hush 的 Chat 会话渲染性能与体验问题（A+B+C+D 全覆盖）：
> - A 流式输出时滚动/布局抖动
> - B 会话切换首屏变慢（layout-ready / rich-ready）
> - C 长 assistant（含表格/数学）渲染卡顿（TextKit spike）
> - D 滚动历史时 CPU 飙高（几何观测/可见性计算/布局链路）
>
> **核心策略（大改动允许）**：
> 1) 先建立 Debug-only 可观测性与可脚本化证据采集（相对基线验收）
> 2) 从根上切断 `PreferenceKey + per-message GeometryReader` 的高频 churn
> 3) 引入 windowing：只渲染“可见 + buffer + 尾部 N 条”，并保证滚动/选择/查找/无障碍边界
> 4) TextKit 渲染收敛：减少 `ensureLayout` 触发、缓存测量、附件 reconcile 做差量
> 5) 若 SwiftUI 路线仍达不到指标 → 兜底升级为 AppKit 虚拟化时间线（NSCollectionView/NSTableView）
>
> **交付物**：
> - Debug-only 性能观测（OSLog/signpost + counters + 报告导出）
> - Windowing + 可见性/优先级新机制（移除 per-message frame PreferenceKey）
> - 会话切换首帧路径优化（两阶段：先快后精）
> - TextKit/附件链路优化（减少主线程 spike）
> - 回归测试（Swift Testing，按“实现后补”策略）
> - 兜底路线（条件触发）：AppKit 虚拟化时间线方案
>
> **预估工作量**：XL（涉及 UI/状态/渲染/可观测/回归/兜底）
> **并行执行**：YES（2–3 波）
> **关键路径**：可观测性基线 → windowing 纯函数+测试 → ChatScrollStage 集成 → TextKit 收敛 → 证据对比 →（必要时）AppKit 兜底

---

## Context

### 原始请求
检查并深入研究 chat-rendering-performance：审计并彻底解决 `ChatScrollStage.swift` 与 `MessageBubble.swift` 相关的性能/兼容性/UX 问题，输出可执行优化计划（不在本阶段直接实现）。

### 已确认的事实（关键证据）

**渲染/滚动架构**
- `Hush/Views/Chat/ChatScrollStage.swift`
  - `ScrollViewReader + ScrollView + LazyVStack + ForEach(container.messages)`
  - streaming 期间 `.onChange(of: container.messages.last?.content)` 触发 scroll-to-bottom（`RenderConstants.streamingScrollCoalesceInterval = 0.1s`）
  - 可见性：`MessageFramePreferenceKey`（每条 assistant message 一个 GeometryReader）+ `ViewportFramePreferenceKey` → `recomputeVisibleMessages()`（高频 O(n) 风险）
- `Hush/Views/Chat/MessageBubble.swift`
  - assistant：`RenderController`（streaming coalesce 50ms）+ `AttributedTextView`（NSTextView/TextKit）
  - `MessageBubble: Equatable` 排除 `renderHint.rankFromLatest/isVisible`，仅纳入 `switchGeneration`（避免滚动导致 bubble 重渲染）

**Streaming 更新频率与现有护栏**
- `Hush/RequestCoordinator.swift`
  - streaming delta → `throttledUIFlush`，使用 `RenderConstants.streamingUIFlushInterval = 100ms` 节流对 `messages` 的更新
- 现有测试：`HushTests/RequestCoordinatorStreamingUIFlushTests.swift`
  - 证明最终内容正确；UI flush 版本数显著小于 delta 数（示例断言：200 deltas 下 observed content versions < 80）

**TextKit/附件**
- `Hush/Views/Chat/AttributedTextView.swift`
  - `updateNSView` 与 `sizeThatFits` 都可能调用 `layoutManager.ensureLayout(for:)`（主线程 spike 风险）
  - `TableAttachmentHost.reconcile(in:)` 会扫描 `.attachment`（全量 enumerate）并管理子视图；`restoreHorizontalOffset()` 调 `layoutSubtreeIfNeeded()`
- `Hush/HushRendering/MarkdownToAttributed.swift`
  - Table attachment 渲染仅在 **non-streaming** 生效（`if !isStreaming ... tryTableAttachment(...)`）

**会话切换链路（会话渲染）**
- `Hush/AppContainer.swift`：`activateConversation → beginConversationActivation`
  - `activeConversationRenderGeneration` 每次切换递增，驱动 UI latch
  - `messageRenderRuntime.setActiveConversation(conversationID:generation:)` 使 `ConversationRenderScheduler` 丢弃 stale work
  - `activeConversationSwitchTrace` 记录 startedAt/snapshotAppliedAt/layoutReadyAt，并在 `HUSH_SWITCH_DEBUG=1` 下输出日志
- `Hush/Views/Chat/ChatScrollStage.swift`
  - `.id(container.activeConversationRenderGeneration)` 强制重建
  - `.task(id: container.activeConversationRenderGeneration)` 调 `resetForConversationSwitch` 并 `container.markConversationSwitchLayoutReady()`

### 用户已确认的策略/验收前提

**优先级**：A+B+C+D 全部都要彻底解决。

**允许大改动**：允许 windowing、替换滚动/几何观测策略、拆 streaming 状态通路。

**验收负载（硬验收）**：标准负载
- 会话切换首屏：最近 9 条（`RuntimeConstants.conversationMessagePageSize = 9`）
- 流式：单次 200 deltas
- 滚动历史：加载到 300 条消息

**允许策略**：windowing（仅渲染可见 + buffer + 尾部 N 条）。

**成功标准**：相对基线（先采 baseline，再要求显著下降 X%），并且 **不允许回归**。

**兜底**：允许 SwiftUI 路线未达标时升级为 AppKit 虚拟化时间线（NSCollectionView/NSTableView）。

**windowing 体验边界必须保证**：
- 滚动定位稳定（不跳动/不闪白/快速滚动不抖）
- 复制/选择稳定（不要求跨消息连续选择；当前 `HushTextView` 也阻止跨消息选择）
- 查找/定位消息能力不被阻断（未来“会话内查找→跳转”仍可实现）
- 无障碍/VoiceOver 阅读顺序与焦点不应明显破坏

---

## Work Objectives

### 核心目标
把“会话渲染”从当前的 **高频几何 churn + 全量列表依赖 + TextKit 主线程峰值**，升级为 **可观测、可回归、可窗口化、可渐进渲染、可兜底的工程化体系**。

### 具体交付
- Debug-only 可观测性：signpost/counters + 可脚本导出报告（baseline vs after）
- ChatScrollStage windowing：只渲染窗口，消除 per-message frame PreferenceKey 链路
- 滚动策略：粘底/用户上滑保护/流式输出不抢滚动，减少 scrollTo 频率
- 会话切换：首帧更快 + rich-ready 更可控（先快后精）
- TextKit：减少 `ensureLayout` 触发与附件 reconcile 全量扫描频率（并提供证据）
- 回归测试：新增/补齐针对 windowing、切换链路、渲染调度、附件行为的 Swift Testing 用例
- 条件兜底：AppKit 虚拟化时间线方案（只在 fail criteria 触发时执行）

### Definition of Done（总体）
- [ ] `make test` 通过
- [ ] 在标准负载场景下，导出的 perf 报告显示关键指标相对 baseline 有显著改善（见“验收指标”）
- [ ] windowing 体验边界全部满足（通过自动化可验证信号 + 约束测试/日志证明）
- [ ] 若 SwiftUI 路线仍未达标：AppKit 兜底路线实现并通过同一套证据采集

### Must NOT（硬护栏）
- 不改变 `RequestCoordinator` 的 streaming flush 时序与语义（`RenderConstants.streamingUIFlushInterval`）
- 不破坏 `MessageBubble` 的 Equatable 语义（避免滚动触发 bubble 重渲染的防线）
- observability 必须 Debug-only / 运行时开关，Release 0 开销
- 不引入新的第三方依赖

---

## Verification Strategy（MANDATORY：零人工）

### 测试决策
- **测试基础设施**：YES（Swift Testing，`HushTests/`）
- **自动化测试策略**：Tests-after（实现后补测试，但每个阶段都必须有 agent 可执行的 QA/证据采集）

### 证据采集（agent 可执行，无需手动 Instruments）
采用两类证据：
1) **单元/集成测试**：`xcodebuild test` / `make test`
2) **Debug-only 性能报告**：运行指定测试/脚本后，用 `log show`（按 subsystem/category）导出统计，生成 baseline 与 after 对比。

### 关键验收指标（相对 baseline，默认阈值）
> 说明：先采 baseline，然后对比 after；以下阈值是“默认门槛”，执行阶段可按 baseline 的噪声调整，但不得变成空口。

- **D（滚动/几何 churn）**
  - `visible.recompute.count`：降低 ≥ 70%
  - `visible.recompute.p95_ms`：降低 ≥ 50%
- **A（流式抖动/滚动抢夺）**
  - `scroll.adjustToBottom.count_during_streaming`：降低 ≥ 60%
  - `scroll.adjustToBottom.suppressed_due_to_user_scroll`：有明确计数与日志（证明保护生效）
- **B（会话切换）**
  - `switch.snapshot_to_layoutReady.p95_ms`：降低 ≥ 30%
  - `switch.snapshot_to_richReady.p95_ms`：降低 ≥ 30%
- **C（TextKit/附件）**
  - `text.ensureLayout.p95_ms`：降低 ≥ 30%
  - `attachments.reconcile.count`：降低 ≥ 50%（在滚动/切换/流式场景中）

---

## Execution Strategy

### Parallel Execution Waves

Wave 1（打地基，必须先完成）：
├── Task 1: Debug-only 可观测性与报告导出（baseline/after）
└── Task 2: windowing 纯函数设计 + 单测（不触 UI）

Wave 2（核心改动）：
├── Task 3: ChatScrollStage 集成 windowing（替换 ForEach 数据源）
├── Task 4: 去除 per-message frame PreferenceKey 链路（用更便宜的可见性/窗口机制驱动 renderHint）
└── Task 5: older-load + pinned/auto-scroll 与 windowing 的交互修复

Wave 3（收敛主线程峰值 + 会话切换）：
├── Task 6: TextKit `ensureLayout` 与 `TableAttachmentHost.reconcile` 收敛/缓存/节流
└── Task 7: 会话切换“先快后精”与 rich-ready 路径优化（并产出证据）

Wave 4（补测试 + 可访问性 + 兜底门槛）：
├── Task 8: Tests-after 回归补齐（windowing/switch/scroll/textkit）
├── Task 9: Accessibility/VoiceOver 基线与 windowing 兼容性修复
└── Task 10（条件）: 若 SwiftUI 路线未达标 → AppKit 虚拟化时间线兜底

### Dependency Matrix（简化）

| Task | Depends On | Blocks |
|------|------------|--------|
| 1 | None | 3–10 |
| 2 | None | 3–5 |
| 3 | 1,2 | 4,5,8 |
| 4 | 1,3 | 5,8 |
| 5 | 1,3,4 | 8 |
| 6 | 1 | 8 |
| 7 | 1 | 8 |
| 8 | 3–7 | 10 |
| 9 | 3–7 | 10 |
| 10 | 1,8,9（且 fail criteria 触发） | None |

---

## TODOs

> 约定：每个任务都必须包含“References + Acceptance Criteria + Agent-Executed QA Scenarios”。

### 1) Debug-only 可观测性（signpost + counters + 报告导出）+ baseline

**What to do**
- 新增 Debug-only 的 perf tracing 工具层：
  - counters（计数器）+ durations（计时）+ 统一的 log category
  - 能在测试或脚本场景结束时输出结构化汇总（JSON 行格式，见下方 Metrics Emission Format）
- 在关键热路径埋点（至少这些）：
  - `ChatScrollStage.requestScrollToBottom/scrollToBottom`
  - `ChatScrollStage.recomputeVisibleMessages`（现状高频）
  - `AttributedTextView.updateNSView`/`sizeThatFits` 中 `ensureLayout`
  - `TableAttachmentHost.reconcile` 与 descriptor scan
  - `AppContainer` 的会话切换 trace：started/snapshotApplied/layoutReady/richReady（已有日志，补齐结构化汇总）
- 提供 agent 可执行的"baseline 采集"命令路径，并将输出保存到 `.sisyphus/evidence/`

**必须创建的交付物（新文件）**：
- `Hush/HushCore/PerfTrace.swift`：Debug-only perf tracing 工具（counters/durations/汇总输出）
  - `#if DEBUG` guard，Release 编译完全剔除
  - 使用 `Logger(subsystem: "com.hush.app", category: "PerfTrace")` 输出结构化 JSON 行
- `HushTests/ChatRenderingPerfHarnessTests.swift`：perf harness 测试 suite
  - `@Suite("Chat Rendering Perf Harness")` + `@Test` 方法
  - 使用 mock provider / 已有测试夹具驱动标准负载场景（切换/streaming/滚动），触发 PerfTrace 埋点
  - 测试结束时调用 `PerfTrace.summary()` 输出 JSON 汇总到 stdout（或写入文件）
- `scripts/perf-report.swift`：Swift 脚本，解析 `log show` 输出或测试 stdout 中的 PerfTrace JSON 行，生成 summary JSON
  - 运行方式：`swift scripts/perf-report.swift < .sisyphus/evidence/perf-baseline-log.json > .sisyphus/evidence/perf-baseline-summary.json`
  - 不引入第三方依赖（纯 Foundation JSON 解析）

**Metrics Emission Format（固定规范）**：
- subsystem: `com.hush.app`
- category: `PerfTrace`
- 每条事件为一行 JSON，格式：`{"event":"<name>","type":"count"|"duration_ms","value":<number>,"ts":<unix_ms>}`
- 事件名命名规范（与验收指标对齐）：
  - `visible.recompute`（count + duration_ms）
  - `scroll.adjustToBottom`（count，附加字段 `"during_streaming":true|false`，`"suppressed":true|false`）
  - `text.ensureLayout`（duration_ms）
  - `attachments.reconcile`（count + duration_ms）
  - `switch.snapshotApplied`（duration_ms，从 startedAt 到 snapshotAppliedAt）
  - `switch.layoutReady`（duration_ms，从 startedAt 到 layoutReadyAt）
  - `switch.richReady`（duration_ms，从 startedAt 到 richReadyAt）
- Summary JSON 最小 schema（由 `scripts/perf-report.swift` 输出）：
  ```json
  {
    "visible.recompute.count": <int>,
    "visible.recompute.p95_ms": <float>,
    "scroll.adjustToBottom.count_during_streaming": <int>,
    "scroll.adjustToBottom.suppressed_count": <int>,
    "text.ensureLayout.p95_ms": <float>,
    "attachments.reconcile.count": <int>,
    "attachments.reconcile.p95_ms": <float>,
    "switch.snapshot_to_layoutReady.p95_ms": <float>,
    "switch.snapshot_to_richReady.p95_ms": <float>
  }
  ```

**Must NOT do**
- 不得让 Release 构建有任何 perf tracing 的运行时成本（`#if DEBUG` guard）
- 不得依赖人工打开 Instruments

**Recommended Agent Profile**
- Category: `unspecified-high`
  - Reason: 横跨 SwiftUI/AppContainer/TextKit 的系统性改动，需要谨慎与全局一致性
- Skills: （无特定技能）
- Skills Evaluated but Omitted:
  - `playwright`: macOS 原生 UI 不适用

**Parallelization**
- Can Run In Parallel: YES（可与 Task 2 并行）
- Parallel Group: Wave 1

**References**
- `Hush/Views/Chat/ChatScrollStage.swift`
  - `requestScrollToBottom` / `scrollToBottom`：scroll 频率与 jitter 的核心证据点
  - `recomputeVisibleMessages`：当前 O(n) 可见性计算热点
- `Hush/Views/Chat/AttributedTextView.swift`
  - `ensureLayout(for:)`：TextKit 主线程峰值证据点
  - `TableAttachmentHost.reconcile` / `scanDescriptors`：附件扫描与子视图操作证据点
- `Hush/AppContainer.swift`
  - `beginConversationActivation` / `ConversationSwitchTrace` / `markConversationSwitchLayoutReady` / `reportActiveConversationRichRenderReadyIfNeeded`
- Debug 开关模式参考：
  - `Hush/HushRendering/RenderConstants.swift`（`HUSH_RENDER_DEBUG`）
  - `Hush/Views/Chat/ChatDetailPane.swift`（`HUSH_SWITCH_DEBUG` overlay）

**Acceptance Criteria**
- [ ] `make build` 通过
- [ ] `make test` 通过
- [ ] `Hush/HushCore/PerfTrace.swift` 存在且被 `#if DEBUG` 包裹
- [ ] `HushTests/ChatRenderingPerfHarnessTests.swift` 存在且可独立运行
- [ ] `scripts/perf-report.swift` 存在且可运行（`swift scripts/perf-report.swift --help` 输出用法）
- [ ] 在 DEBUG 模式下运行 harness 后，stdout/日志中可见 PerfTrace JSON 行（包含至少：visible.recompute、scroll.adjustToBottom、text.ensureLayout、attachments.reconcile、switch.*）
- [ ] 在 Release 构建下（`xcodebuild -project Hush.xcodeproj -scheme Hush -configuration Release -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages build CODE_SIGNING_ALLOWED=NO`），PerfTrace 完全被编译剔除（无符号）

**Agent-Executed QA Scenarios**
Scenario: 采集 baseline（标准负载）
  Tool: Bash
  Preconditions: 可观测性已实现；使用 mock provider/已有测试夹具
  Steps:
    1. 运行 harness：`xcodebuild test -project Hush.xcodeproj -scheme Hush -configuration Debug -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages -only-testing:"HushTests/ChatRenderingPerfHarnessTests" CODE_SIGNING_ALLOWED=NO 2>&1 | tee .sisyphus/evidence/perf-baseline-raw.txt`
    2. 导出系统日志：`log show --style json --predicate 'subsystem == "com.hush.app" AND category == "PerfTrace"' --last 2m > .sisyphus/evidence/perf-baseline-log.json`
    3. 生成汇总：`swift scripts/perf-report.swift < .sisyphus/evidence/perf-baseline-log.json > .sisyphus/evidence/perf-baseline-summary.json`
  Expected Result: `.sisyphus/evidence/perf-baseline-summary.json` 存在且包含上述最小 schema 的所有字段
  Evidence: `.sisyphus/evidence/perf-baseline-summary.json`

---

### 2) windowing 纯函数：窗口范围计算 + 单测（不碰 UI）

**What to do**
- 设计并实现一个纯函数 windowing 模块（独立于 SwiftUI），输入包含：
  - message 列表长度、尾部 N、buffer 大小、当前 anchor（或 top-visible/last-visible 的近似）
  - pinned 状态（是否在尾部）
  - streaming 状态（是否需要强制包含 last message）
- 输出：要渲染的 window range（或 messageID 集合）
- 添加 Swift Testing：覆盖
  - messages < windowSize 的 no-op
  - pinned=true 时窗口始终包含尾部 N
  - pinned=false 时围绕 anchor 稳定移动（避免频繁 shift）
  - streaming 时 last message 永远在窗口内
  - prepend older messages 时窗口策略稳定

**必须创建的交付物（新文件）**：
- `Hush/HushCore/ChatWindowing.swift`：windowing 纯函数模块
  - `struct ChatWindowingInput` / `struct ChatWindowingOutput`
  - `static func computeWindow(...)` — 纯函数，无 SwiftUI 依赖
- `HushTests/ChatWindowingTests.swift`：windowing 算法测试 suite
  - `@Suite("Chat Windowing")` + `@Test` 方法
  - 覆盖上述 5 个边界场景

**Must NOT do**
- 不触碰 `AppContainer.messages` 语义

**Recommended Agent Profile**
- Category: `ultrabrain`
  - Reason: 需要把 windowing 设计成稳定、可验证、不会造成滚动跳动的算法

**Parallelization**
- Can Run In Parallel: YES（与 Task 1 并行）
- Parallel Group: Wave 1

**References**
- `Hush/Views/Chat/ChatScrollStage.swift`
  - 现状没有 windowing；ForEach 遍历全量 `container.messages`
- `HushTests/ConversationSwitchScrollTests.swift`
  - 快速切换与 generation latch 的稳定性测试思路

**Acceptance Criteria**
- [ ] 新增 windowing 纯函数模块 + Swift Testing 用例
- [ ] `make test` 通过（新用例稳定不 flaky）

**Agent-Executed QA Scenarios**
Scenario: windowing 算法边界测试
  Tool: Bash
  Steps:
    1. 运行：`xcodebuild test -project Hush.xcodeproj -scheme Hush -configuration Debug -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages -only-testing:"HushTests/ChatWindowingTests" CODE_SIGNING_ALLOWED=NO`
  Expected Result: 0 failures
  Evidence: xcodebuild 输出（保存到 `.sisyphus/evidence/task-2-windowing-tests.txt`）

---

### 3) ChatScrollStage 集成 windowing（替换 ForEach 数据源）

**What to do**
- 在 `ChatScrollStage` 内将 `ForEach(container.messages)` 改为 `ForEach(windowedMessages)`（windowed slice）
- 保证 windowing 体验边界：
  - 滚动定位稳定：window shift 不应造成明显跳动/白屏
  - pinned（尾部）状态下，窗口应"跟随尾部"并包含最后消息 + loading indicator
- 引入/调整锚点策略：
  - 优先使用轻量级信号（例如 onAppear/onDisappear 记录 top-visible messageID）来驱动 window anchor
  - 避免重新引入 per-message frame PreferenceKey

**必须创建/修改的文件**：
- 修改 `Hush/Views/Chat/ChatScrollStage.swift`：集成 `ChatWindowing.computeWindow(...)`
- 新增 `HushTests/ChatScrollPerfHarnessTests.swift`：
  - `@Suite("Chat Scroll Perf Harness")`
  - 构造 300 条消息场景（使用 `AppContainer.forTesting`），触发滚动/streaming，采集 PerfTrace 指标

**Must NOT do**
- 不破坏 `.id(container.activeConversationRenderGeneration)` 的 conversation switch latch 语义
- 不让 windowing 抢夺用户上滑（保持现有 pinned 保护窗口概念）

**Recommended Agent Profile**
- Category: `visual-engineering`
  - Reason: 直接影响滚动/布局/UX，需要 UI 直觉与 SwiftUI 经验

**Parallelization**
- Can Run In Parallel: NO（依赖 Task 1+2）
- Parallel Group: Wave 2

**References**
- `Hush/Views/Chat/ChatScrollStage.swift`
  - `ForEach(messages, id: \.id)`：替换点
  - `userHasScrolledUp` / `updatePinnedState`：pin 逻辑与流式保护
  - `scrollAnchorID`：尾部锚
- `Hush/HushCore/RuntimeConstants.swift`（`conversationMessagePageSize = 9`）

**Acceptance Criteria**
- [ ] `make build` 通过
- [ ] `make test` 通过
- [ ] perf tracing 显示：`visible.recompute.count`（或替代指标）在 300 条消息滚动场景下降 ≥ 70%（相对 baseline）
- [ ] pinned 状态下 streaming 期间窗口始终包含最后一条 assistant（不出现“尾部消息被 window out”）

**Agent-Executed QA Scenarios**
Scenario: 300 条消息 + 快速滚动性能证据采集
  Tool: Bash
  Preconditions: Task 1 的 perf tracing + 报告导出可用
  Steps:
    1. 运行性能场景测试/脚本：`xcodebuild test -project Hush.xcodeproj -scheme Hush -configuration Debug -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages -only-testing:"HushTests/ChatScrollPerfHarnessTests" CODE_SIGNING_ALLOWED=NO`
    2. 导出 after 日志与汇总：写入 `.sisyphus/evidence/perf-after-windowing-*.json`
    3. 对比 baseline：断言关键字段下降满足阈值
  Expected Result: 对比断言通过
  Evidence: baseline+after summary JSON

---

### 4) 去除 per-message frame PreferenceKey：可见性与 renderHint 新驱动

**What to do**
- 移除/停用 `MessageFramePreferenceKey` 与 `ViewportFramePreferenceKey` 链路（避免滚动时 dict merge + intersection 的高频主线程开销）
- 用更廉价的信号驱动 `MessageRenderHint.isVisible`：
  - 优先：window membership（窗口内视为"可见/近可见"）
  - 辅助：onAppear/onDisappear 建立一个轻量 `visibleMessageIDs`（仅用于非 streaming render priority）
- 明确：`MessageBubble` 的 Equatable 语义保持不变（仍排除 isVisible/rankFromLatest），避免滚动驱动 bubble 重算。

**必须创建/修改的文件**：
- 修改 `Hush/Views/Chat/ChatScrollStage.swift`：移除 `MessageFramePreferenceKey`/`ViewportFramePreferenceKey`/`recomputeVisibleMessages()`
- 修改 `Hush/HushRendering/RenderController.swift`：`resolvePriority` 适配新的可见性信号
- 新增 `HushTests/ConversationSwitchPerfHarnessTests.swift`：
  - `@Suite("Conversation Switch Perf Harness")`
  - 构造会话切换场景，验证窗口内 assistant 被优先 rich render（通过 PerfTrace 事件断言）

**Recommended Agent Profile**
- Category: `ultrabrain`
  - Reason: 需要在不破坏现有 Equatable/RenderScheduler 的前提下改动“可见性→优先级”的数据通路

**Parallelization**
- Can Run In Parallel: NO（依赖 Task 3）
- Parallel Group: Wave 2

**References**
- `Hush/Views/Chat/ChatScrollStage.swift`
  - `MessageFramePreferenceKey` / `ViewportFramePreferenceKey` / `recomputeVisibleMessages()`
- `Hush/HushRendering/RenderController.swift`
  - `resolvePriority(for hint:)`：`hint.isVisible` 影响 non-streaming render priority
- `Hush/HushRendering/MessageRenderHint.swift`
  - hint 字段定义
- `HushTests/MessageBubbleEqualityTests.swift`
  - Equatable 合约（排除 isVisible/rankFromLatest）

**Acceptance Criteria**
- [ ] `make test` 通过
- [ ] perf tracing 显示：`visible.recompute.*` 指标显著下降（count ≥ 70%，p95_ms ≥ 50%）
- [ ] non-streaming render priority 仍能优先渲染窗口内与尾部 N 条（通过新增 scheduler 相关测试或 trace 证明）

**Agent-Executed QA Scenarios**
Scenario: 会话切换后窗口内 assistant 优先 rich render
  Tool: Bash
  Steps:
    1. 开启 `HUSH_SWITCH_DEBUG=1`
    2. 运行：`xcodebuild test -project Hush.xcodeproj -scheme Hush -configuration Debug -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages -only-testing:"HushTests/ConversationSwitchPerfHarnessTests" CODE_SIGNING_ALLOWED=NO`
    3. 从日志中断言：高优先级 render enqueue/dequeue 发生在窗口内消息（通过 messageID 前缀匹配/计数）
  Evidence: `.sisyphus/evidence/task-4-switch-render-priority.log`

---

### 5) older-load + auto-scroll + windowing 交互修复（避免抖动与误触发）

**What to do**
- 重新设计“加载更旧消息”的触发条件：
  - 不能依赖 windowing 后的“顶部 sentinel onAppear”直接触发，否则可能反复触发
  - 引入更稳定的触发：例如基于“接近顶部阈值”的轻量信号（可通过单个 PreferenceKey 追踪顶部 anchor，而不是每条 message 的 frame）
- 校验 pinned/streaming 保护窗口：
  - 流式期间用户上滑不会被强行拉回
  - 只有在 near-bottom 且用户未上滑时才触发滚动到底部

**Recommended Agent Profile**
- Category: `visual-engineering`
  - Reason: 这是最易产生“抖动/抢滚动/误加载”的 UX 风险区

**Parallelization**
- Can Run In Parallel: NO（依赖 Task 3+4）
- Parallel Group: Wave 2

**References**
- `Hush/Views/Chat/ChatScrollStage.swift`
  - `topPaginationSection` / `triggerOlderMessagesLoadIfNeeded`（现状 onAppear 触发）
  - `updatePinnedState`（距离阈值 pinnedDistanceThreshold/streamingBreakawayThreshold）
  - `.onChange(of: container.messages.last?.content)`（现状 streaming 滚动触发）
- `HushTests/ChatScrollStageAutoScrollPolicyTests.swift`（已有分类策略单测）

**Acceptance Criteria**
- [ ] `make test` 通过
- [ ] perf tracing：`scroll.adjustToBottom.count_during_streaming` 相对 baseline 降低 ≥ 60%
- [ ] older-load 在 windowing 下不会在短时间内重复触发（通过计数器 + throttle 断言）

**Agent-Executed QA Scenarios**
Scenario: streaming 时用户上滑不被抢滚动
  Tool: Bash
  Steps:
    1. 运行 harness：模拟 streaming 200 deltas + 同时模拟“用户已滚动上移”状态切换
    2. 断言：scrollToBottom 被 suppress（计数器增长），且 pinned 状态保持 userHasScrolledUp=true
  Evidence: `.sisyphus/evidence/task-5-streaming-scroll-policy.json`

---

### 6) TextKit 峰值收敛：ensureLayout 缓存/节流 + 附件 reconcile 差量化

**What to do**
- `AttributedTextView`：减少 `ensureLayout` 触发频率
  - 对同一 attributedString identity + 宽度的测量/高度做缓存（避免 `sizeThatFits` 与 `updateNSView` 重复布局）
  - 宽度阈值（已有 `widthChangeThreshold`）进一步用于决定是否必须 layout
- `TableAttachmentHost.reconcile`：避免每次都 enumerate 全串 attachment
  - 引入“渲染产物驱动”的 attachment descriptor 列表（renderer 输出 tables 清单/签名），host 按 diff 增删
  - 或至少引入 reconcile 的节流/触发条件（例如 attachment count 或 attributed identity 变化才 reconcile）

**Must NOT do**
- 不改变 streaming 时 table attachment 被禁用的策略（`MarkdownToAttributed` 已禁用）

**Recommended Agent Profile**
- Category: `unspecified-high`
  - Reason: AppKit/TextKit 细节多，错误会直接导致渲染错乱/选区问题

**Parallelization**
- Can Run In Parallel: YES（可与 Task 7 并行，均依赖 Task 1）
- Parallel Group: Wave 3

**References**
- `Hush/Views/Chat/AttributedTextView.swift`
  - `updateNSView` / `sizeThatFits` / `TableAttachmentHost.reconcile` / `scanDescriptors`
- `Hush/HushRendering/MarkdownToAttributed.swift`
  - `renderTable`：`if !isStreaming ... tryTableAttachment`
- `HushTests/TableAttachmentHostReuseTests.swift`（复用/横向滚动 offset 保持）

**Acceptance Criteria**
- [ ] `make test` 通过（特别是 TableAttachmentHost 相关测试）
- [ ] perf tracing：`text.ensureLayout.p95_ms` 相对 baseline 降低 ≥ 30%
- [ ] perf tracing：`attachments.reconcile.count` 相对 baseline 降低 ≥ 50%
- [ ] 复制/选择稳定不回归（至少通过现有选择行为不崩溃、text view 仍 selectable 的测试/日志证明）

**Agent-Executed QA Scenarios**
Scenario: 富文本（含表格）渲染峰值对比
  Tool: Bash
  Steps:
    1. 运行 table rendering harness（复用 `RenderingFixtures.Tables.*`）
    2. 导出 signpost/counter 汇总
    3. 对比 baseline：ensureLayout/reconcile 指标满足阈值
  Evidence: `.sisyphus/evidence/task-6-textkit-before-after.json`

---

### 7) 会话切换“先快后精”：首帧/富文本就绪优化 + 证据

**What to do**
- 利用现有 `ConversationSwitchTrace`（startedAt/snapshotAppliedAt/layoutReadyAt/richReady）进一步工程化：
  - 首帧策略：先让列表快速可见（轻量/纯文本或已缓存输出），然后在 idle/预算内升级富文本
  - 对 `ChatScrollStage.resetForConversationSwitch` 的 scroll 行为做优化：减少不必要动画/重复 scrollTo
- 让 rich-ready 更可控：
  - 只对窗口内 + 尾部 N 条进行优先 rich render（结合 Task 4 的可见性驱动）
  - 若有 cache 命中（`MessageContentRenderer.cachedOutput`），优先直接应用

**Recommended Agent Profile**
- Category: `ultrabrain`
  - Reason: 需要同时理解 AppContainer 的切换时序、RenderScheduler 的 generation、防止 stale work

**Parallelization**
- Can Run In Parallel: YES（与 Task 6 并行）
- Parallel Group: Wave 3

**References**
- `Hush/AppContainer.swift`
  - `beginConversationActivation`（generation、cache hit/miss、db fetch、trace）
  - `markConversationSwitchLayoutReady` / `reportActiveConversationRichRenderReadyIfNeeded`
- `Hush/Views/Chat/ChatScrollStage.swift`
  - `.id(activeConversationRenderGeneration)` + `.task(id:) resetForConversationSwitch`
- `Hush/HushRendering/MessageContentRenderer.swift`
  - `cachedOutput(for:)` / `render(_:)`（cache 行为）
- 现有测试：`HushTests/ConversationSwitchScrollTests.swift`

**Acceptance Criteria**
- [ ] `make test` 通过
- [ ] perf tracing：
  - `switch.snapshot_to_layoutReady.p95_ms` 降低 ≥ 30%
  - `switch.snapshot_to_richReady.p95_ms` 降低 ≥ 30%
- [ ] 快速连续切换（A→B→C）不会出现 stale 覆盖（复用/增强现有 tests）

**Agent-Executed QA Scenarios**
Scenario: 连续快速切换稳定性 + 证据采集
  Tool: Bash
  Steps:
    1. 运行：`xcodebuild test ... -only-testing:"HushTests/ConversationSwitchScrollTests"`
    2. 运行 perf harness：连续切换 50 次（同一套 fixture），导出 p95/p99
    3. 断言：layoutReady/richReady 相对 baseline 达标
  Evidence: `.sisyphus/evidence/task-7-switch-perf.json`

---

### 8) Tests-after：补齐 windowing/滚动/切换/TextKit 的回归测试

**What to do**
- 新增/补齐测试 suite（Swift Testing）：
  - windowing 纯函数（已在 Task 2）
  - scroll policy：pinned/streaming/user scroll protection（扩展 `ChatScrollStageAutoScrollPolicyTests.swift` 或新增 suite）
  - conversation switch：trace 时序断言（扩展 `ConversationSwitchScrollTests.swift`）
  - TextKit/attachment：复用 `TableAttachmentHostReuseTests` 并新增“reconcile 触发条件”断言（避免回退到每次扫描）

**Recommended Agent Profile**
- Category: `quick`
  - Reason: 在实现稳定后补测试，主要是覆盖与断言补齐

**Parallelization**
- Can Run In Parallel: YES（可与 Task 9 并行）
- Parallel Group: Wave 4

**References**
- `HushTests/RequestCoordinatorStreamingUIFlushTests.swift`
- `HushTests/StreamingCoalescingTests.swift`
- `HushTests/ConversationSwitchScrollTests.swift`
- `HushTests/MessageBubbleEqualityTests.swift`
- `HushTests/TableAttachmentHostReuseTests.swift`

**Acceptance Criteria**
- [ ] `make test` 通过
- [ ] 新增测试覆盖关键回归点：windowing correctness、scroll policy、切换稳定、TextKit reconcile 不回退

**Agent-Executed QA Scenarios**
Scenario: 全量测试回归
  Tool: Bash
  Steps:
    1. 运行：`make test`
  Expected Result: 0 failures
  Evidence: `.sisyphus/evidence/task-8-make-test.txt`

---

### 9) Accessibility/VoiceOver：windowing 不破坏阅读顺序/焦点

**What to do**
- 评估并补齐 chat 消息区域的可访问性语义：
  - MessageBubble 作为可访问元素（role/label/value）
  - windowing shift 时焦点不应跳到不可预测位置
  - 未来"查找→跳转"需要可定位到具体 messageID（这也服务于 accessibility）

**必须创建的交付物（新文件）**：
- `HushTests/ChatAccessibilitySmokeTests.swift`：
  - `@Suite("Chat Accessibility Smoke")`
  - 使用 `NSHostingView` 包裹 `MessageBubble`，验证 accessibility element 存在且 label/role 正确
  - 验证 windowing 后焦点不指向被 window-out 的元素

**Recommended Agent Profile**
- Category: `visual-engineering`
  - Reason: 需要 UI/UX + accessibility 经验

**Parallelization**
- Can Run In Parallel: YES（与 Task 8 并行）
- Parallel Group: Wave 4

**References**
- `Hush/Views/Chat/MessageBubble.swift`
- `Hush/Views/Chat/ChatScrollStage.swift`

**Acceptance Criteria**
- [ ] `make test` 通过
- [ ] `HushTests/ChatAccessibilitySmokeTests.swift` 存在且可独立运行
- [ ] 至少有可自动验证的 accessibility 标识存在（通过 `NSHostingView` 遍历 accessibility children 断言 element 存在）

**Agent-Executed QA Scenarios**
Scenario: Accessibility 元数据存在性检查
  Tool: Bash
  Steps:
    1. 运行：`xcodebuild test -project Hush.xcodeproj -scheme Hush -configuration Debug -derivedDataPath .build/DerivedData -clonedSourcePackagesDirPath .build/SourcePackages -only-testing:"HushTests/ChatAccessibilitySmokeTests" CODE_SIGNING_ALLOWED=NO`
  Expected Result: PASS
  Evidence: `.sisyphus/evidence/task-9-accessibility.txt`

---

### 10) 条件兜底：AppKit 虚拟化时间线（NSCollectionView/NSTableView）

> **触发条件（fail criteria）**：完成 Task 1–9 后，perf 报告仍无法达到关键阈值（A/B/C/D 任一关键指标未达标）。

**What to do**
- 用 AppKit 组件实现时间线虚拟化（推荐 NSCollectionView）：
  - cell 复用承载 `NSTextView`（避免 SwiftUI ScrollView 的几何/偏好 key churn）
  - last message 的 streaming 更新只刷新一个 cell
  - 保持与 SwiftUI 外壳（顶部栏/输入框/侧边栏）桥接
- 复用同一套可观测性与 perf harness，确保达标。

**Recommended Agent Profile**
- Category: `unspecified-high`
  - Reason: AppKit/SwiftUI bridging 难度高，容易引入新 bug

**Parallelization**
- Can Run In Parallel: NO（必须在 SwiftUI 路线评估后决定）

**References**
- `Hush/Views/Chat/ChatDetailPane.swift`（时间线容器）
- `Hush/Views/Chat/ChatScrollStage.swift`（被替换/旁路的现有实现）
- `Hush/Views/Chat/AttributedTextView.swift`（NSTextView/附件宿主可复用）

**Acceptance Criteria**
- [ ] `make test` 通过
- [ ] 标准负载下 perf 报告全部指标达标（相对 baseline）
- [ ] windowing 体验边界在 AppKit 虚拟化下同样满足（滚动稳定、选择复制稳定、可定位、无障碍不明显破坏）

**Agent-Executed QA Scenarios**
Scenario: AppKit 时间线 perf 对比
  Tool: Bash
  Steps:
    1. 运行 perf harness
    2. 导出 after 报告并对比 baseline
  Evidence: `.sisyphus/evidence/task-10-appkit-perf.json`

---

## Commit Strategy（建议）

| After Task | Commit Message | Verification |
|------------|----------------|--------------|
| 1 | `perf(chat): add debug-only tracing and baseline harness` | `make test` |
| 2 | `perf(chat): add windowing core algorithm` | `make test` |
| 3–5 | `perf(chat): window chat timeline and reduce geometry churn` | `make test` + perf harness |
| 6 | `perf(render): reduce TextKit layout spikes and attachment churn` | `make test` + perf harness |
| 7 | `perf(chat): improve conversation switch first paint and rich-ready` | `make test` + perf harness |
| 8–9 | `test(a11y): add regression coverage for windowing and accessibility` | `make test` |
| 10（条件） | `perf(chat): appkit virtualized timeline fallback` | `make test` + perf harness |

---

## Success Criteria（最终验收）

### 必跑命令
```bash
make test
```

### 证据文件
- [ ] `.sisyphus/evidence/perf-baseline-summary.json`
- [ ] `.sisyphus/evidence/perf-after-summary.json`
- [ ] 对比结果满足“关键验收指标（相对 baseline）”

### 最终检查
- [ ] A/B/C/D 指标均达标
- [ ] windowing 体验边界均未破坏
- [ ] 若 SwiftUI 路线未达标：AppKit 兜底实现达标
