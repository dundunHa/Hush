# Draft: Chat 输入/流式渲染卡顿抖动（ComposerDock）

## 现象（用户描述）
- 在 `Hush/Views/Chat/ComposerDock.swift` 的聊天框输入时出现卡顿，感觉整个 chat 页面在“抖动”。
- 向 LLM 提问后，渲染返回信息时也会卡顿抖动。

## 初始范围（待确认）
- 涉及：Chat 页面（消息列表 + ComposerDock 输入区）、流式增量渲染（streaming）、滚动/自动滚动逻辑。
- 重点文件线索：`ComposerDock.swift`（TextEditor 绑定 `container.draft`）、`ChatScrollStage.swift`、`Chat/AppKit/*`（NSTableView 列表）、渲染管线（Markdown/Math）。

## 初步假设（需要用代码证据验证）
- H1：`@EnvironmentObject AppContainer` 的 `@Published draft` 在每次按键都触发 `objectWillChange`，导致整个 Chat 视图树重算（包括消息列表/滚动状态/渲染 cache），从而抖动。
- H2：`TextEditor` 高度在 32~64 之间变化，导致布局频繁 re-layout，叠加阴影/渐变背景，肉眼表现为抖动。
- H3：流式渲染时每个 token/delta 都触发布局或 NSAttributedString/Markdown 重建，造成主线程阻塞，连带输入区也卡。
- H4：自动滚动/anchor 状态机在频繁内容变更下反复切换，引发 table view/scroll 抖动。

## 代码证据（已确认）

### 1) `draft` 的发布范围过大 → 触发整个 Chat 视图链路更新
- `Hush/AppContainer.swift:135-147`
  - `@Published var draft: String`，`didSet` 里调用 `noteUserActivityForIdlePrewarm()`。
  - 结论：**每次键入都会触发 AppContainer 的 publish**。
- `Hush/Views/Chat/ComposerDock.swift:87`
  - `TextEditor(text: $container.draft)` 直接绑定。

### 2) publish 导致 AppKit 消息列表也被“误更新”
- `Hush/Views/Chat/ChatDetailPane.swift:35-55`
  - 默认走 AppKit 路径（`ConversationRenderRoute.usesAppKitFallback` 默认 true）。
  - `HotScenePoolRepresentable()` / `ConversationViewControllerRepresentable()` 都拿 `@EnvironmentObject container`。
- `Hush/Views/Chat/AppKit/HotScenePoolRepresentable.swift:10-12`
  - `updateNSViewController` 每次 SwiftUI body 重算都会调用 `nsViewController.update(container: container)`。
- `Hush/Views/Chat/AppKit/HotScenePoolController.swift:52-64, 127-159`
  - `update(container:)` → `forwardUpdateToActiveScene(container:)`（当 active conversation 未变）。
  - `forwardUpdateToActiveScene` **无差别**调用 `scene.applyConversationState(...)`。
- `Hush/Views/Chat/AppKit/ConversationViewController.swift:54-57, 91-99`
  - `update(container:)` → `renderConversationState()` → `applyConversationState(...)`。
- `Hush/Views/Chat/AppKit/MessageTableView.swift:100-141`
  - `apply(...)` 内部**每次都 `tableView.reloadData()`**（第 140 行附近）。

> 推断链路：键入 → `container.draft` publish → `ChatDetailPane` 重算 → Representable update → `MessageTableView.apply` → `reloadData()` → 布局/滚动/行高计算 → 体感“抖动/卡顿”。

### 3) streaming 期间的额外压力点（已定位）
- `MessageTableView.apply(...)`：当 `isActiveConversationSending && !userHasScrolledUp && newCount == oldCount` 时会走 `performScrollToBottom(animated: false, reason: .streamingContent)`，目前看不到明显节流（需继续读后半段确认）。
- `HushRendering/RenderController.swift`：声明 streaming coalesce（默认 `RenderConstants.streamingCoalesceInterval`，探针显示 50ms），但仍可能在主线程上做高成本 render（需结合 `MessageContentRenderer` 与 scheduler 看是否能进一步 off-main / 更强批处理）。

### 4) `draft` 还会触发 idle-prewarm 调度（可能是次要成本）
- `Hush/AppContainer.swift:1997-2030`
  - `scheduleIdlePrewarmIfNeeded()` 每次都会 cancel 旧 task 并创建新 task（sleep 后 prewarm）。
  - 这可能增加任务创建/取消开销，但更大的问题仍是 UI 误更新 + `reloadData()`。

## 初步结论（当前最强假设）
- **根因 1（高置信）**：`draft` 作为 `AppContainer` 的 `@Published` 全局状态，导致整个 Chat 视图树（含 AppKit Representable）在每次键入时被刷新。
- **根因 2（高置信）**：AppKit 路径 `MessageTableView.apply` 对任何 update 都 `reloadData()`，缺少“只在消息/发送状态变化时更新”的差分/短路。
- **根因 3（中置信）**：streaming 时 `reloadData()` + `scrollToBottom()` 过于频繁，叠加渲染 phase2 计算，产生抖动。

## 需要补充的信息（开放问题）
- 复现条件：只要输入就抖？还是长对话/长消息时更明显？
- 抖动表现：是消息列表滚动位置跳动？还是整个窗口尺寸/布局在抖？
- 机器/系统：macOS 版本、机器性能（Intel/Apple Silicon）、屏幕刷新率。
- 是否能提供：Instruments（Time Profiler / Main Thread Checker / SwiftUI）或屏幕录制。

## 用户已确认的优先级/偏好（confirmed）
- 优先级：先解决“输入卡顿/抖动”。
- draft 行为：保持现状（全局保留：切换会话也保留未发送文本）。
- 快速定位实验：愿意先关掉 AppKit 会话渲染路径（`HUSH_APPKIT_CONVERSATION=0`）做 A/B 对比。

## Scope 边界（暂定）
- INCLUDE：定位根因、给出可执行的修复方案（拆分状态、节流/去抖、渲染缓存、滚动策略）。
- EXCLUDE：大规模 UI 重写（除非必要），更换核心架构（如完全从 NSTableView 换成 SwiftUI List）。

## 代码定位：聊天“滑动/滚动”相关（待深入）

> 用户追问：“聊天滑动时渲染部分代码在哪个代码文件？”

### SwiftUI 路径（HUSH_APPKIT_CONVERSATION=0 时）
- `Hush/Hush/Views/Chat/ChatScrollStage.swift`
  - 这里有 `ScrollViewReader` 相关的滚动/锚点逻辑（例如 `scrollToBottom(...)`、`proxy.scrollTo(...)`）。
  - 如果你看到“切换会话不显示内容/锚点错乱/滚动跳动”，通常也会与这个文件的 state machine、anchor id、generation `.id(...)` 刷新策略有关。

### AppKit 路径（默认 NSTableView）
- `Hush/Hush/Views/Chat/AppKit/MessageTableView.swift`
  - `NSScrollView` + `NSTableView` 容器与滚动行为（包括 `scrollToBottom()`、`scrollRowToVisible`、对 `boundsDidChangeNotification` 的监听）。
  - “滑动时渲染/更新”在这条路径上往往体现为：滚动位置变化 → 是否触发“用户已上滑”状态 → 新增消息/流式更新时是否保持 anchor 或自动滚到底。

### 辅助桥接/遥测
- `Hush/Hush/Views/Chat/ScrollTelemetryBridge.swift`
  - 负责从某个 view 向上找到 `NSScrollView`，读取 `contentView` 位置等（通常用于“用户是否上滑/当前偏移”等状态）。

### 其他可能相关（横向滚动/附件）
- `Hush/Hush/Views/Chat/AttributedTextView.swift`
  - 包含 `NSScrollView` 的实现细节（更多像富文本/附件子视图的滚动容器管理），不一定是“消息列表主滚动”，但可能影响子视图的滚动与重排。

## 用户补充（confirmed）
- 当前渲染路径：AppKit（默认 NSTableView 路径）
- 主要问题类型：手动滚动卡顿（非自动滚动跳动）

## 新目标（用户最新诉求，confirmed）
- 重点分析/优化：AppKit 聊天渲染路径（NSTableView/NSScrollView）
- 期望体验：无论上下滑动、切换会话滑动、流式返回、富文本/格式渲染更新，都尽量保持“丝滑”，不出现明显卡顿/抖动
- 备注：用户表示“这些问题都会有”，说明是多因素叠加，而非单一触发条件

## 研究补充：当前实现的关键瓶颈（证据来自代码与 explore/librarian/oracle 调研）

### A) AppKit 列表更新策略：apply() 每次都 reloadData
- `Hush/Hush/Views/Chat/AppKit/MessageTableView.swift:101-217`
  - `apply(...)` 在构建 rows 后无条件 `tableView.reloadData()`（约第 140 行）。
  - 这会触发可见 cell 的复用/配置逻辑，并导致动态高度/布局大量重算，手动滚动时容易掉帧。

### B) 滚动事件频率高：boundsDidChange → updatePinnedState
- `MessageTableView.swift:63-73` 监听 `NSView.boundsDidChangeNotification`（clipView bounds changed）。
- `MessageTableView.swift:289-308` 每次滚动都会计算 distanceFromBottom / distanceFromTop，并驱动 TailFollow 状态机；接近顶部会触发 older load。
- older load 有 0.3s throttle，但仍可能在滚动时引入异步加载完成后的 `scrollRowToVisible(anchorRow)`。

### C) 富文本渲染的线程模型：几乎全在 MainActor
- `Hush/Hush/HushRendering/RenderController.swift`、`ConversationRenderScheduler.swift`、`MessageContentRenderer.swift` 均是 `@MainActor` 设计。
- 结果：Markdown→NSAttributedString / math / table 等高成本工作**并不在后台线程**，会与滚动争抢主线程时间片。

### D) 渲染回写会在滚动期间发生
- `MessageTableCellView.configure(...)`：cache miss 或 streaming 时先写 plain fallback，再异步拿到 rich output 后写 `bodyLabel.attributedStringValue`。
- 该回写在主线程进行；在用户手动滚动时若持续发生，会导致明显卡顿/闪动。

## 可用的内建观测手段（现成）
- `Hush/Hush/HushCore/PerfTrace.swift` 提供 debug-only JSON 事件：
  - `visible.recompute` / `scroll.adjustToBottom` / `text.ensureLayout` / `attachments.reconcile` / switch 系列事件
- 环境变量（部分）：
  - `HUSH_SWITCH_DEBUG=1` / `HUSH_RENDER_DEBUG=1` / `HUSH_CONTENT_DEBUG=1`
  - `HUSH_APPKIT_CONVERSATION` / `HUSH_HOT_SCENE_POOL`

## 外部最佳实践要点（librarian 汇总）
- 滚动中避免 `reloadData`，优先使用针对行的更新（insert/remove/reload row、`noteHeightOfRows(withIndexesChanged:)`）。
- 监听 `NSScrollViewWillStartLiveScroll` / `NSScrollViewDidEndLiveScroll`，滚动期间暂停非必要工作（富文本解析、图片解码、内容回写）。
- 动态高度是大头：高度缓存、估算高度、只对变更行做 retile。
- 禁用滚动期间隐式动画（CATransaction disable actions）以避免微闪。

## Oracle 建议（高层策略，已吸收）
- 先量化热点再改：给 `MessageTableView.apply()`、cell configure、富文本回写、scroll 回调、older-load 路径打点（signpost/日志）并看主线程耗时。
- 把 `reloadData` 从“常规更新方式”降级为“最后手段”，优先增量更新（insert/remove/reload rows + 行高定点失效）。
- 行高缓存（messageID + width）是手动滚动丝滑的关键之一；富文本完成/宽度变化时只 invalid 单行。
- 滚动期间必须减负：scroll 监听节流（50~100ms）、富文本回写合并/延后、仅更新可见/将可见行。

## 开放问题（待确认，阻塞后续优化取舍）
- 目标机器与刷新率：Intel/Apple Silicon？60Hz/120Hz（ProMotion）？
- 典型会话规模：消息条数（100/500/2000）？最长消息字符数？是否常见表格/LaTeX？
- “丝滑”的可接受策略：滚动期间是否允许暂时只显示 plain fallback（富文本延后到滚动停止后）？
- 是否接受：streaming 期间富文本刷新频率降低（例如 100~200ms 批处理）换取滚动丝滑？

## 用户最新回答（confirmed）
- 体验策略：滚动优先（滚动期间允许降频/延后富文本与流式 UI 更新）
- 验收偏好：可测指标（希望用 Instruments/PerfTrace 做前后对比）
- 规模/约束：列表加载的消息数量可控（滑动加载）；但必须兼容 Markdown / 代码块 / LaTeX / 表格等富文本能力

## 用户新增问题（2026-02-23，待验证细节）
- P1：快速滑动仍然存在掉帧现象（scroll jank）
- P2：切换会话或者发送消息后，有时没有展示最后一条消息（疑似未滚到底/滚动锚点不稳定）
- P3：流式输出需要边接收边渲染；可容忍先显示原文本，接收完整公式后再显示 LaTeX 富渲染

## 代码证据补充（与上述 P1/P2/P3 直接相关）

### 渲染线程模型：Streaming 与非 Streaming 目前都在 MainActor 上 render
- `Hush/HushRendering/RenderController.swift`
  - `@MainActor final class RenderController`
  - streaming: `pendingStreamingTask = Task { ... let output = self.renderer.render(input) }`（render 发生在 MainActor）
  - non-streaming: `ConversationRenderScheduler.enqueue(render: { renderer.render(input) })`（scheduler worker 同为 MainActor）
- `Hush/HushRendering/MessageContentRenderer.swift`
  - `@MainActor final class MessageContentRenderer`
  - `renderMarkdown` 内部：`Document(parsing:)` + `MarkdownToAttributed.convert()` + `MathRenderer`/`TableRenderer`（CPU 密集）

### AppKit 列表更新策略：apply() 每次 reloadData（会放大滚动掉帧与锚点不稳）
- `Hush/Views/Chat/AppKit/MessageTableView.swift`
  - `apply(...)` 内 `tableView.reloadData()`（无差分/无行级更新）
  - bounds change 高频回调：`boundsDidChangeNotification` → `updatePinnedState()`

### TailFollow 规则（自动滚到底的门闩/阈值）
- `Hush/HushCore/TailFollowStateMachine.swift`
  - pinnedDistanceThreshold = 80pt；streamingBreakawayThreshold = 260pt
  - conversationSwitched: `pendingSwitchScroll = true`
  - messageAdded: 若 pendingSwitchScroll 为真 → 触发 `.scrollToBottom(animated:false, reason:.switchLoad)`
  - distanceChanged: 非保护窗口且 distance>80 时会 `isFollowingTail = false`（可能与 reload/layout 时机交错）

### LaTeX/表格 streaming 容忍策略（与用户 P3 对齐）
- `Hush/HushRendering/MathSegmenter.swift`
  - 对 `$$...$$` 未闭合情况会“render literally”（常见于 streaming）
- `Hush/HushRendering/MarkdownToAttributed.swift`
  - 传入 `isStreaming`，可在 streaming 时走更保守的渲染策略（例如表格 attachment 仅在非 streaming 才启用）

## 现有工程文档（可复用，但尚未把本次新增问题写入文档）
- `doc/chat-rendering/02-rendering-pipeline.md`（渲染管线）
- `doc/chat-rendering/03-scheduler.md`（RenderController + Scheduler）
- `doc/chat-rendering/04-scroll-stability.md`（滚动/切换稳定性 + TailFollow 设计）
- `doc/chat-rendering/06-debugging.md`（调试开关/排障）
