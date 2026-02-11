# Plan: 彻底重构聊天滚动与 Tail-Follow 状态机（SwiftUI + AppKit 路线对齐）

## TL;DR

> **目标**：彻底解决 `ChatScrollStage` 中“发送消息不滚到底、streaming 不跟随最新消息”的不稳定问题，并将 SwiftUI（默认）与 AppKit fallback 两条渲染路线的滚动语义统一到同一套**显式 Tail-Follow 状态机 + 纯策略（policy）**。
>
> **关键约束**：
> - **用户只要离开底部就立刻停止跟随**（unpinned 时不自动拉回）。
> - **用户自己发送消息必须强制滚到底部**（即使当前在上滑阅读）。
> - **不引入 time.sleep/固定延时门闩**（OpenSpec 也禁止）。
> - 保留既有稳定性护栏：`requestScrollToBottom` 的 **合并/去重 + `Task.yield()`**（见 `doc/chat-rendering/04-scroll-stability.md`）。
> - **TDD**：先写状态机/策略单测，再接入 UI。
> - 阈值 **沿用现有**：80pt / 260pt / 0.6s（先稳定后再调参）。

**交付物（Deliverables）**
- 新增：共享的纯值类型状态机（放在 `Hush/Hush/HushCore/`，模式参考 `ChatWindowing`）
  - `TailFollowStateMachine`（命名可调整）+ `TailFollowPolicy` + `TailFollowConfig`
- 新增：SwiftUI 路线的 AppKit bridge/telemetry（捕获真实 scroll bounds 变化，区分用户滚动 vs programmatic scroll）
- 重构：
  - `Hush/Views/Chat/ChatScrollStage.swift`：移除“几何推导=用户意图”的耦合，改为状态机驱动；保留 scrollTo 合并与 yield。
  - `Hush/Views/Chat/AppKit/MessageTableView.swift`：补齐缺失语义（用户消息强制滚底、streaming breakaway/grace），并与 SwiftUI 共用状态机。
- 测试：新增状态机转换表测试 + 关键竞态回归测试；保持既有测试全部通过。
- 文档：更新 `doc/chat-rendering/04-scroll-stability.md`（与新架构一致），补充“为什么不需要 sleep、如何区分用户意图/布局抖动”。

**预估工作量**：Large

---

## Context

### 原始问题（用户反馈）
- 发送消息后不会自动定位到最新消息。
- LLM streaming 返回过程中不会持续展示最新消息（不跟随向下滚动）。

### 证据与既有约束（必须遵守）
- 工程文档：`doc/chat-rendering/04-scroll-stability.md`
  - `requestScrollToBottom` 采用 `pendingScrollTask` 合并 + `await Task.yield()`，用于规避 SwiftUI `scrollTo` 在同一事务内连发导致的空白/定位异常。
- OpenSpec：`openspec/specs/conversation-switch-scroll-state-machine/spec.md`
  - 切换会话滚动必须事件门闩驱动（不得 sleep）；切换到 streaming 会话必须动画到底并继续 tail-follow。
- 单测语义：`HushTests/ChatScrollStageAutoScrollPolicyTests.swift`
  - userHasScrolledUp=true 时 assistant append / streaming 更新必须抑制自动滚底。
  - 用户消息必须强制滚底。

### 根因假设（以代码结构为证，不靠臆测业务）
- 当前 SwiftUI 路线将 `userHasScrolledUp` 直接绑定到几何推导（`BottomAnchorPreferenceKey` 的 distanceFromBottom）。
- 与 `requestScrollToBottom` 的 `Task.yield()` 组合时存在竞态窗口：内容增长/布局反馈可能先将 `userHasScrolledUp` 误置为 true，导致随后滚动被抑制。
- “彻底重构(B)”的核心思想：将“用户意图（我是否上滑）”从“布局瞬时测量”中解耦，引入真实滚动事件（AppKit `NSScrollView` bounds change）作为 **用户滚动信号**，并把所有滚动决策收敛到可测试的纯状态机。

### 关键风险（来自历史文档 + Metis review，必须提前锁护栏）
- **两条路线当前语义不一致**（SwiftUI vs AppKit fallback）：
  - SwiftUI：有 streaming breakaway/grace、用户消息强制滚底、scrollTo 合并 + yield。
  - AppKit：目前缺少用户消息强制滚底；pinned 判定也不包含 breakaway/grace。
  - 本计划要求最终对齐到同一套状态机/配置。
- **SwiftUI 路线获取真实 NSScrollView 可能存在实现不确定性**：
  - 风险：SwiftUI 的 ScrollView 内部结构变动可能导致“找不到 enclosingScrollView / 找错 scroll view”。
  - 缓解：
    1) 先做纯状态机 + policy（Wave 1）锁语义，不依赖 bridge。
    2) bridge 任务在 Wave 2 独立实现，并提供“找不到时降级策略”：
       - 仍可用现有 PreferenceKey distance 作为传感器，但必须通过“programmatic-scroll-in-flight 事件门闩”避免布局抖动误判为用户上滑。
       - 这不是 sleep：是显式事件标记。
- **不得破坏既有 scrollTo 稳定性护栏**：保留 `pendingScrollTask` + `Task.yield()` 合并机制（见 `doc/chat-rendering/04-scroll-stability.md`）。

---

## Work Objectives

### Core Objective
建立统一的“Tail-Follow 意图状态机”，在 SwiftUI 与 AppKit 两条聊天渲染路线中复用，使滚动行为稳定、可预测、可测试，并彻底消除因布局抖动导致的 pinned 误判。

### Must Have（非功能性 + 语义硬要求）
- 用户上滑离开底部 → **立即停跟随**（不再自动滚底）。
- 用户发送消息 → **强制滚到底部**（并恢复跟随）。
- streaming 期间：仅当处于 followingTail 时才跟随；pausedByUser 时不跟随。
- 不引入 `time.sleep` / 固定延时门闩。
- 保留既有 scrollTo 合并/去重与 `Task.yield()`（避免 SwiftUI scrollTo glitch 回归）。

### Must NOT Have（护栏，防止 scope creep 与回归）
- 不重写/改动 `Hush/Hush/HushCore/ChatWindowing.swift`（windowing 已独立且有测试）。
- 不修改 `RequestCoordinator` 的 streaming UI flush 语义（已存在节流与测试，非本次范围）。
- 不改变 `ChatDetailPane.swift` 的路线选择开关（`HUSH_APPKIT_CONVERSATION`）。
- 不引入第三方依赖（如 SwiftUI introspection lib）。
- 不把滚动状态塞进 `AppContainer` 的 `@Published`（避免污染全局 DI 容器；滚动是 UI 层行为）。

---

## Verification Strategy（MANDATORY：零人工介入）

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> 所有验收均必须可由 agent 通过命令与自动化断言完成；不得要求人工拖拽滚动/肉眼确认。

### 测试决策
- **测试基础设施**：YES（Swift Testing，`HushTests/`）
- **策略**：TDD

### 主要验证方式
1) 单元测试：状态机转换表（覆盖 pinned/unpinned、user vs programmatic、streaming/grace、switch、older prepend）。
2) 回归测试：既有 scroll policy/windowing/switch generation 相关测试必须继续通过。
3) 构建验证：`make build` + `make fmt`。

### 关键命令（作为最终 Success Criteria 的一部分）
```bash
make fmt
make test
make build

# 关键套件定点回归
xcodebuild test \
  -project Hush.xcodeproj -scheme Hush -configuration Debug \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -only-testing:"HushTests/ChatScrollStageAutoScrollPolicyTests"

xcodebuild test \
  -project Hush.xcodeproj -scheme Hush -configuration Debug \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -only-testing:"HushTests/ConversationSwitchScrollTests"
```

---

## Execution Strategy

### Parallel Execution Waves

Wave 1（纯函数/TDD，先锁定语义）：
1) 设计并实现 `TailFollowStateMachine`（纯同步、无 UI 依赖）+ 完整测试矩阵
2) 抽取/迁移现有 `resolveCountChangeAutoScrollAction` 语义到新 policy（保持现有测试通过）

Wave 2（SwiftUI 路线接入）：
3) 在 `ChatScrollStage` 接入状态机（保留 `pendingScrollTask + yield`）
4) 引入 SwiftUI 路线 AppKit scroll telemetry bridge（捕获真实 scroll bounds 变化，作为“用户滚动事件源”）

Wave 3（AppKit fallback 路线对齐）：
5) `MessageTableView` 改用共享状态机/配置（补齐用户消息强制滚底、streaming breakaway/grace、完成时滚底等）
6) 为 AppKit 路线补足测试（不需要 UI 自动化，使用 NSScrollView/NSClipView 的可控单元测试来验证事件与距离计算）

Wave 4（文档与回归收敛）：
7) 更新 `doc/chat-rendering/04-scroll-stability.md` 与 `06-debugging.md`（如果涉及调试开关/日志变化）
8) 全量回归：`make fmt && make test && make build`

---

## TODOs

> 说明：每个任务都包含 References（执行者必须读）+ Acceptance Criteria（可执行）+ Agent-Executed QA Scenarios（命令/断言）。

### 1) TDD：新增共享 Tail-Follow 状态机（纯值类型，参考 ChatWindowing 模式）

**What to do**
- 在 `Hush/Hush/HushCore/` 新增一个“无 UI 依赖”的模块文件（建议命名：`TailFollowStateMachine.swift`）。
- 采用与 `ChatWindowing` 相同的模式：
  - `public struct ...Input / ...State / ...Config`
  - `public enum ...` 作为命名空间 + `static func reduce(state:event:config:now:) -> (state, actions)`
- 事件至少覆盖：
  - `userScroll(distanceFromBottom:)`
  - `programmaticScrollRequested(reason:)`（用户消息/切换/streaming-follow）
  - `reachedTail(distanceFromBottom:)`（用于恢复 followingTail 与清 unread）
  - `messageCountChanged(lastRole:didPrependOlder:)`
  - `streamingDeltaApplied` / `streamingCompleted`
  - `conversationSwitched(generation:)`
- 输出动作：
  - `ScrollAction.scrollToBottom(animated: Bool, reason: Reason)`
  - `ScrollAction.none`
- 配置化阈值：80pt/260pt/0.6s 作为 `TailFollowConfig` 输入（不在 View 里硬编码）。

**Must NOT do**
- 状态机内不得引入 `Task`/`async`/`@MainActor`/`sleep`。

**References**
- `Hush/Hush/HushCore/ChatWindowing.swift` — 纯函数/输入输出 struct 的风格模板。
- `Hush/Views/Chat/ChatScrollStage.swift` — 现有滚动触发源与 guard 逻辑（需迁移语义）。
- `HushTests/ChatScrollStageAutoScrollPolicyTests.swift` — 既有语义基线（必须保持）。
- `doc/chat-rendering/04-scroll-stability.md` — 必须保留 yield 合并护栏（只改决策不改机制）。

**Acceptance Criteria**
- 新增测试文件（示例名）：`HushTests/TailFollowStateMachineTests.swift`
  - 覆盖转换表 ≥ 20 个用例（following ↔ paused、user vs programmatic、streaming/grace、switch、older prepend）。
- `xcodebuild test ... -only-testing:"HushTests/TailFollowStateMachineTests"` → PASS。
- `xcodebuild test ... -only-testing:"HushTests/ChatScrollStageAutoScrollPolicyTests"` → PASS（无回归）。

**Agent-Executed QA Scenarios**
1) Tool: Bash（xcodebuild）
   - Steps:
     1. 运行 `xcodebuild test` 指定 `TailFollowStateMachineTests`
     2. 断言 0 failures
   - Expected: 测试全部通过，且不依赖任何 UI/人工滚动。

---

### 2) TDD：把现有 AutoScrollPolicy 语义迁移/包裹到新状态机（保持旧测试通过）

**What to do**
- 保留或重定向 `ChatScrollStage.resolveCountChangeAutoScrollAction(...)`：
  - 允许作为兼容层存在，但其内部应调用新 policy/state machine 的等价逻辑。
- 确保“用户消息强制滚底、上滑抑制 assistant/streaming”的语义继续成立。

**References**
- `Hush/Views/Chat/ChatScrollStage.swift: resolveCountChangeAutoScrollAction`
- `HushTests/ChatScrollStageAutoScrollPolicyTests.swift`

**Acceptance Criteria**
- 现有 `ChatScrollStageAutoScrollPolicyTests` 全部通过。

**Agent-Executed QA Scenarios**
1) Tool: Bash（xcodebuild）
   - Steps: 仅跑 `ChatScrollStageAutoScrollPolicyTests` 并确认 PASS。

---

### 3) SwiftUI 路线重构：ChatScrollStage 改为“状态机驱动 + yield 合并执行”

**What to do**
- 将 `ChatScrollStage` 内关于 `userHasScrolledUp` 的“几何推导=用户意图”拆解：
  - `BottomAnchorPreferenceKey` 继续用于计算 distance（作为传感器/到尾部判定），但不直接决定“用户已上滑”的意图。
  - “用户已上滑”改由 telemetry 的真实 scroll bounds 变化触发（下一任务实现）。
- 保留：`requestScrollToBottom`（cancel + yield 合并）执行机制。
- 将 `.onChange(of: messages.count / last.content / isSending)` 的判断收敛为：
  - 事件 → 状态机 reduce → 得到 `ScrollAction` → 再调用 `requestScrollToBottom`。

**References**
- `Hush/Views/Chat/ChatScrollStage.swift`（核心改动文件）
- `doc/chat-rendering/04-scroll-stability.md`（yield 合并护栏）
- `openspec/specs/conversation-switch-scroll-state-machine/spec.md`（switch 动画到底 + streaming tail-follow）

**Acceptance Criteria**
- `make test` → PASS
- `ConversationSwitchScrollTests` → PASS（切换 generation 门闩行为不回归）

**Agent-Executed QA Scenarios**
1) Tool: Bash
   - Steps:
     1. `xcodebuild test -only-testing:"HushTests/ConversationSwitchScrollTests"`
     2. `xcodebuild test -only-testing:"HushTests/ChatScrollStageAutoScrollPolicyTests"`
   - Expected: 通过，证明切换/策略回归不破坏。

---

### 4) SwiftUI 路线 AppKit bridge：捕获真实滚动事件（NSScrollView bounds change）

**What to do**
- 新增一个 `NSViewRepresentable`（参考现有模式：`WindowCloseObserver`、`WindowDragArea`）：
  - 放置到 `ChatScrollStage` 的 ScrollView 层级中（例如 background/overlay），用于定位 `enclosingScrollView` 并订阅 `NSView.boundsDidChangeNotification`。
  - 将 scroll bounds 变化转成状态机事件 `userScroll(distanceFromBottom:)`。
- 关键：区分用户滚动 vs programmatic scroll
  - 在 `requestScrollToBottom` 发起前设置“programmaticScrollInFlight”标记；在 telemetry 收到下一次 bounds change（或 reachedTail）后清除。
  - 这是一种**事件门闩**，不是 sleep。

**References**
- `Hush/HushApp.swift: WindowCloseObserver` — NSViewRepresentable + NotificationCenter observer 的现成写法。
- `Hush/Views/TopBar/UnifiedTopBar.swift: WindowDragArea` — NSViewRepresentable 的极简示例。
- `Hush/Views/Chat/AppKit/MessageTableView.swift` — 已有 bounds change observer 的模式（可复用计算思路）。

**Acceptance Criteria**
- 新增单测覆盖 telemetry 的“距离计算”和“programmatic in-flight 不误判为用户上滑”。（允许通过可控 NSScrollView/NSClipView 构造来测试，而非 UI 自动化。）
- `make test` → PASS

**Agent-Executed QA Scenarios**
1) Tool: Bash
   - Steps:
     1. 跑 telemetry 相关 tests（示例：`HushTests/ChatScrollTelemetryTests`）
     2. 确认 PASS

---

### 5) AppKit fallback 路线对齐：MessageTableView 使用共享状态机/配置

**What to do**
- 将 `MessageTableView.apply(...)` 内的滚动逻辑替换为：
  - events → reduce → actions → `scrollRowToVisible(lastRow)`
- 补齐当前缺失语义：
  - 用户消息强制滚底
  - streaming breakaway threshold（260）与 post-streaming grace（0.6s）
  - streaming finished 的最终滚底（在 followingTail 时）

**References**
- `Hush/Views/Chat/AppKit/MessageTableView.swift` — 当前逻辑与 pinned 判定（仅 80pt）。
- `Hush/Views/Chat/ChatScrollStage.swift:updatePinnedState` — 260/0.6s 语义来源。

**Acceptance Criteria**
- 新增/更新 AppKit 路线测试（不需要 UI automation）：
  - 使用 `NSScrollView` + `NSTableView`/假的 docHeight 来验证 pinned 判定与动作输出。
- `make test` → PASS

---

### 6) 文档对齐与回归收敛

**What to do**
- 更新 `doc/chat-rendering/04-scroll-stability.md`：
  - 补充“用户意图状态机 vs 几何传感器”的架构说明
  - 解释为何不需要 sleep、如何保留 yield 合并
  - 增补两条路线对齐点与差异（如果仍存在）
- 视需要更新 `doc/chat-rendering/06-debugging.md`：
  - 加入新的调试信号（例如状态机状态打印的 DEBUG 开关）

**Acceptance Criteria**
- `make fmt && make test && make build` → PASS
- 文档中引用的关键文件路径与当前实现一致。

---

## Commit Strategy

建议按“可回滚的语义锁定”拆分为小步提交（执行阶段由实施 agent 决定是否 commit）：
1) `test(scroll): add tail-follow state machine contract tests`
2) `refactor(scroll): route ChatScrollStage through state machine`
3) `feat(scroll): add AppKit telemetry bridge for SwiftUI scroll intent`
4) `refactor(scroll): align MessageTableView with shared tail-follow policy`
5) `docs(scroll): update scroll stability docs for new architecture`

---

## Success Criteria

### Verification Commands
```bash
make fmt
make test
make build
```

### Final Checklist
- [ ] SwiftUI 路线：发送消息强制滚底；用户上滑立即停跟随；followingTail 时 streaming 可持续跟随。
- [ ] AppKit fallback 路线：行为与 SwiftUI 一致（同一套状态机/阈值/语义）。
- [ ] 不引入任何固定 sleep；保持 yield 合并护栏。
- [ ] 相关测试套件新增且稳定（≥20 状态机用例），且既有测试全部通过。
