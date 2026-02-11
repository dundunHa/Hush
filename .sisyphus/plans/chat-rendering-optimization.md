# Plan: Chat Rendering Optimization

> Status: Archived (2026-02-21)

## Executive Summary

优化 Hush 聊天消息渲染管线，**彻底**解决流式响应期间的滚动风暴、布局抖动、冗余计算，以及“每个 delta 都触发 SwiftUI 失效”的根因问题。

目标：
- 流式输出期间 UI 更新频率有上限（bounded），避免频繁触发整棵视图树重新求值
- 自动滚动稳定：用户上滚时不会被拉回；Pinned 状态切换不抖动
- 现有富文本（Markdown / 表格 / 数学）行为保持不变

策略：**同时覆盖源头（RequestCoordinator 流式 UI flush）+ 视图层（ChatScrollStage 节流/缓存/去抖）**。不引入新渲染引擎，不做大规模架构重写。

## Prioritized Optimization Items

### P0 — ✅ 已完成：从源头限制流式 UI 更新频率（RequestCoordinator / AppContainer）

**问题定位**: `Hush/RequestCoordinator.swift:390-423`

当前 `handleDelta` 在每个 `.delta` 都执行：
- `activeRequest.appendDelta` + `flushText()`
- **替换** `container.messages[index] = ChatMessage(...)`

这会导致 SwiftUI 在流式期间频繁 invalidation，进而放大：
- `ChatScrollStage` 的 `.onChange(of: container.messages.last?.content)` 触发频率
- 各种 PreferenceKey/GeometryReader 的反馈环

**修复方案（推荐：最小侵入）**:
1. 在 `RequestCoordinator` 增加“**流式 UI flush 节流/合并**”（类似已存在的 `throttledStreamingFlush` 持久化节流）
2. `appendDelta` 仍每次执行，但 `container.messages[index]` 更新频率限制为例如 100ms 一次（并在 request 完成时强制 flush 最终内容）
3. 需要确保：
   - UI flush 任务取消/超时/stop 时不泄漏
   - “最终消息内容”与持久化 finalize 一致

**修改文件**:
- `Hush/RequestCoordinator.swift`
- （如有必要）`Hush/AppContainer.swift`（仅限增加一个用于测试/观测的计数器或 hook；避免改动消息数据结构）

**测试（必须）**:
- 新增一个针对“bounded UI flush”的测试套件（示例：`HushTests/RequestCoordinatorStreamingUIFlushTests.swift`）：
  - 构造 200 次 `.delta` 在短时间内输入
  - 断言 `container.messages` 最终内容正确
  - 断言 UI flush 次数 ≤ 预期上限（比如 20 次 / 2 秒）

---

### P0 — 流式滚动风暴 (Streaming Scroll Storm)

**问题定位**: `ChatScrollStage.swift` 第 121-126 行

```swift
.onChange(of: container.messages.last?.content) { _, _ in
    guard container.isSending else { return }
    guard container.messages.last?.role == .assistant else { return }
    guard !userHasScrolledUp, !container.isLoadingOlderMessages else { return }
    requestScrollToBottom(proxy: proxy, animated: false, reason: "streaming-content")
}
```

每个 streaming delta（约 50ms 一次）都触发 `requestScrollToBottom`，导致滚动请求风暴。

**修复方案**:
1. 引入滚动节流机制（与“P0 源头 UI flush”配合：源头减少更新频率，视图层再兜底节流）
2. 使用 `@State private var lastScrollTime: Date?` 跟踪上次滚动时间
3. 仅当距上次滚动超过阈值时才执行滚动

**修改文件**: `Hush/Views/Chat/ChatScrollStage.swift`

**新增常量** (在 `RenderConstants.swift`):
```swift
static let streamingScrollCoalesceInterval: TimeInterval = 0.1  // 100ms
```

**测试**: 扩展 `HushTests/ChatScrollStageAutoScrollPolicyTests.swift`，添加滚动节流场景测试

---

### P0 — ✅ 已完成：缓存 rankByMessageID 计算

**问题定位**: `ChatScrollStage.swift` 第 58-59 行

```swift
let messages = container.messages
let rankByID = makeRankByMessageID(messages)  // O(n) 每次 body 求值
```

`makeRankByMessageID` 在每次 SwiftUI body 重新求值时执行 O(n) 字典构建。

**修复方案**:
1. 将 `rankByID` 移至 `@State` 或使用 memoization
2. 仅在 `messages.count` 变化时重新计算
3. 使用 `.onChange(of: container.messages.count)` 触发更新

**修改文件**: `Hush/Views/Chat/ChatScrollStage.swift`

**测试**: 现有测试覆盖，无需新增

---

### P1 — 减少 PreferenceKey/GeometryReader 抖动

**问题定位**: `ChatScrollStage.swift`
- 第 427-437 行: `messageFrameTracker` 为每个 assistant 消息添加 GeometryReader
- 第 141-148 行: `onPreferenceChange(MessageFramePreferenceKey)` 触发 `recomputeVisibleMessages()`

每次帧变化都触发 O(n) 的可见消息重计算。

**修复方案**:
1. 对 `recomputeVisibleMessages()` 添加节流（100-200ms 间隔）
2. 或仅跟踪视口附近消息的帧信息
3. 使用 `DispatchWorkItem` 实现 debounce

**修改文件**: `Hush/Views/Chat/ChatScrollStage.swift`

**新增常量** (在 `RenderConstants.swift`):
```swift
static let visibleMessageRecomputeDebounce: TimeInterval = 0.15  // 150ms
```

**测试**: 添加 debounce 行为单元测试

---

### P1 — 批量/节流可见消息 ID 更新

**问题定位**: `ChatScrollStage.swift` 第 439-458 行

```swift
private func recomputeVisibleMessages() {
    let activeMessageIDs = Set(container.messages.map(\.id))  // O(n)
    // ... 与 messageFrames 字典的交集检查
}
```

**修复方案**:
1. 与 P1 PreferenceKey 节流合并处理
2. 使用增量更新而非全量重建 Set
3. 缓存 `activeMessageIDs`，仅在 `messages` 数组变化时更新

**修改文件**: `Hush/Views/Chat/ChatScrollStage.swift`

**测试**: 现有测试覆盖

---

### P2 — TextKit 布局合并

**问题定位**: `AttributedTextView.swift`
- 第 82-89 行 (`updateNSView`): `layoutManager.ensureLayout(for:)`
- 第 119-129 行 (`sizeThatFits`): 再次调用 `layoutManager.ensureLayout(for:)`

可能存在冗余布局计算。

**修复方案**:
1. 在 Coordinator 中跟踪布局是否已有效
2. 使用内容指纹（fingerprint）判断是否需要重新布局
3. 仅在内容实际变化时调用 `ensureLayout`

**修改文件**: `Hush/Views/Chat/AttributedTextView.swift`

**测试**: 现有 `TableAttachmentHostReuseTests` 覆盖部分场景

---

### P2 — 表格附件协调优化

**问题定位**: `TableAttachmentHost.reconcile(in:)` 每次 `updateNSView` 调用时扫描所有附件

**修复方案**:
1. 在 Coordinator 中缓存上次协调的内容标识
2. 内容标识未变化时跳过协调
3. 使用 `RenderController` 的 fingerprint 机制

**修改文件**: `Hush/Views/Chat/AttributedTextView.swift`

**测试**: 扩展 `TableAttachmentHostReuseTests`

---

## Scope & Guardrails

### 允许修改的文件
- `Hush/Views/Chat/ChatScrollStage.swift` — 主要目标
- `Hush/Views/Chat/MessageBubble.swift` — 次要目标
- `Hush/Views/Chat/AttributedTextView.swift` — 次要目标
- `Hush/HushRendering/RenderConstants.swift` — 参数调优

### 本次明确纳入范围（用户已确认）
- `Hush/RequestCoordinator.swift` — **流式 UI 更新节流/合并（根因级优化）**
- （尽量避免，但必要时允许）`Hush/AppContainer.swift` — 为可测性/观测性提供最小 hook

### 不在本次范围内
- 新的消息数据结构替换（例如把 `messages` 拆成多源 store）——除非 Wave 1 评审认为非做不可
- 新渲染引擎或架构重写
- Provider/网络协议变更

### 行为保持
- Markdown/表格/数学公式渲染功能不变
- 自动滚动语义不变（用户上滚时暂停跟随）
- 现有测试全部通过

---

## Acceptance Criteria

### 每项优化的验收标准

| 优化项 | 验收标准 |
|--------|----------|
| P0 滚动节流 | **自动化可验证**：新增/更新单元测试，断言在 N 次 streaming 内容变化内，`requestScrollToBottom` 被触发次数 ≤ 上限（例如 ≤ ⌈总时长/0.1s⌉ + 2）。并断言 `userHasScrolledUp == true` 时不会触发滚动请求。 |
| P0 rankByID 缓存 | `make test` 通过；body 求值不再每次构建字典 |
| P1 PreferenceKey 节流 | **自动化可验证**：为 `recomputeVisibleMessages()` 触发点添加可测计数/钩子（仅 Debug/测试构建可用），测试断言在高频 PreferenceKey 更新下，重计算频率被 debounce 限制（例如 ≤ 10Hz）。 |
| P1 可见消息批量更新 | 与 P1 PreferenceKey 合并验收 |
| P2 TextKit 布局 | 无冗余 `ensureLayout` 调用；现有测试通过 |
| P2 表格附件 | `TableAttachmentHostReuseTests` 通过；内容不变时跳过协调 |

### 全局验收
- `make test` 全部通过
- `make build` 成功
- （新增）RequestCoordinator 流式 UI flush 有上限：相关测试断言通过（见 P0 “bounded UI flush” 测试）
- （新增）滚动节流生效：相关测试/逻辑断言通过（不依赖人工肉眼观察）

> 说明：本计划的“完成”以 **可由 agent 执行的命令与自动化断言** 为准，不以人工肉眼观测为验收门槛。

---

## Work Breakdown (Waves)

### Wave 1 (~0.5-1 天) — P0 项目（根因 + 兜底）— ✅ 已完成
1. ~~**先建立基线**：运行 `make fmt` + `make test`~~ ✅
2. ~~在 `RequestCoordinator` 实现"流式 UI flush 节流/合并"（bounded UI updates）~~ ✅ throttledUIFlush/applyUIFlush/flushPendingUIUpdate 已实现
3. ~~在 `ChatScrollStage` 实现流式滚动节流（兜底）~~ ✅ `lastStreamingScrollTime` + `streamingScrollCoalesceInterval` (100ms) 已实现
4. ~~缓存 `rankByMessageID` 计算~~ ✅ @State 缓存已实现
5. ~~添加/更新测试（包含 RequestCoordinator UI flush 上限测试 + 滚动策略测试）~~ ✅
6. ~~运行 `make fmt` + `make test` + `make build`~~ ✅

### Wave 2 (~1 天) — P1 项目 — ✅ 已完成
1. ~~实现 `recomputeVisibleMessages` debounce~~ ✅ `scheduleVisibleMessagesRecompute()` + Task cancellation 已实现
2. ~~优化可见消息 ID 集合更新~~ ✅ `@State private var activeMessageIDs` 缓存已实现
3. ~~添加 debounce 行为测试~~ ✅ 生命周期清理（onDisappear + resetForConversationSwitch）已添加
4. ~~运行 `make test` 验证~~ ✅ `make fmt` + `make build` 通过

### Wave 3 (可选, ~0.5 天) — P2 项目 — ✅ 已完成
1. ~~优化 TextKit 布局调用~~ ✅ LayoutFingerprint 缓存 + sizeThatFits 高度缓存已实现
2. ~~优化表格附件协调~~ ✅ lastReconcileFingerprint 指纹守卫已实现
3. ~~扩展相关测试~~ ✅ 现有 TableAttachmentHostReuseTests 覆盖
4. ~~运行 `make test` 验证~~ ✅ `make fmt` + `make build` 通过

---

## Verification Strategy

> **零人工介入规则**：本计划中所有验收标准必须能通过命令执行与测试断言完成；不得要求“用户手动确认/肉眼观察”。

### 自动化验证
- 每个 Wave 完成后运行：
  - `make fmt`（格式化 + SwiftLint）
  - `make test`
  - `make build`
- 新增测试覆盖：
  - RequestCoordinator bounded UI flush（核心）
  - ChatScrollStage streaming scroll coalesce / pinned 语义
  - PreferenceKey/viewport 触发下的 visible recompute debounce

### Agent-Executed QA Scenarios（以测试为载体）

由于这是 **macOS SwiftUI 原生应用**，计划采用“测试驱动的可观测性/计数器”来实现 agent 可执行的端到端验证：

Scenario: 流式 delta 高频输入下 UI 更新次数有上限且最终内容一致
  Tool: Bash（执行 make/xcodebuild）
  Steps:
    1. 运行 `make test`（或单测命令仅跑新增 suite）
    2. 断言：bounded UI flush 测试通过
    3. 断言：最终 assistant 消息 content == 拼接后的完整文本
  Expected: 测试通过，UI flush 次数计数不超过阈值

Scenario: 用户上滚(pinned)时 streaming 不触发自动滚动
  Tool: Bash（执行 make/xcodebuild）
  Steps:
    1. 运行包含 scroll throttle 的测试 suite
    2. 断言：`userHasScrolledUp == true` 时滚动请求计数为 0
  Expected: pinned 语义不被破坏

### 非阻塞验证（可选，不作为验收门槛）
- Instruments Time Profiler 检查 CPU 热点（如果执行环境允许）

---

## Risk Mitigation

### 可逆性设计
- 所有新增节流间隔作为 `RenderConstants` 常量，可快速调整
- 每项优化独立，可单独回滚
- 不改动核心数据流（`RequestCoordinator`/`AppContainer`）

### 回滚策略
- Git commit 按 Wave 划分，便于 cherry-pick 回滚
- 保留原有逻辑注释，便于对比

---

## Decisions (已确认)

1. **本次要彻底解决**：因此将 `RequestCoordinator` 的流式 UI 更新机制纳入范围
2. **Wave 1 完成后设立严格审查 Gate**：通过后才进入 Wave 2

---

## References

### 关键代码位置
- 滚动触发: `ChatScrollStage.swift:121-126`
- rankByID 计算: `ChatScrollStage.swift:58-59, 399-415`
- PreferenceKey 处理: `ChatScrollStage.swift:141-148, 427-437`
- 可见消息重计算: `ChatScrollStage.swift:439-458`
- TextKit 布局: `AttributedTextView.swift:82-89, 119-129`
- 流式 delta 处理: `RequestCoordinator.swift:390-422`

### 相关常量
- `RenderConstants.streamingCoalesceInterval = 0.05` (50ms)
- `ChatScrollStage.pinnedDistanceThreshold = 80`
- `ChatScrollStage.streamingBreakawayThreshold = 260`
- `ChatScrollStage.postStreamingPinnedGraceInterval = 0.6`

### 测试文件
- `HushTests/ChatScrollStageAutoScrollPolicyTests.swift`
- `HushTests/StreamingCoalescingTests.swift`
- `HushTests/TableAttachmentHostReuseTests.swift`
