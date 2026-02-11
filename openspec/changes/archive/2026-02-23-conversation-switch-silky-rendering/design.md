## Context

Hush 的会话切换链路：`beginConversationActivation()` → 递增 `activeConversationRenderGeneration` (@Published) → 视图层响应。

**AppKit 路由（主路径）**：`ConversationViewController.renderConversationState()` → `MessageTableView.apply()` → `tableView.reloadData()`。所有 cell 经历 `prepareForReuse()`（cancel RenderController）→ `configure()`（设置 plain text → 创建新 RenderController → requestRender）。即使 RenderCache 命中，cell 仍先写入 plain text（`MessageTableCellView` 第 405-408 行），再通过 Combine sink 异步替换为 rich text，产生至少一帧闪动。

**SwiftUI 路由（fallback）**：`.id(container.activeConversationRenderGeneration)` 销毁重建整棵 ScrollView 子树，所有 `@State` 重置。

**渲染缓存现状**：`RenderCache` 全局 LRU 64 条目，keyed by `(contentHash, width, styleKey)`。10 条 assistant 消息 × 7 个会话 = 70 条目，已超容量。`ConversationRenderScheduler` 的 stale 机制（第 342-345 行）在 `setActiveConversation()` 时 prune 所有非 active 会话的排队任务。

**现有预热**：startup prewarm 覆盖 2 个非 active 会话 × 4 条 assistant 消息。无 switch-away 预热，无 idle 预热。

## Goals / Non-Goals

**Goals:**
- 会话切换首帧呈现 rendered 内容（rich text 或等效），不出现 plain→rich 替换闪动
- 最近 N 个会话回环切换体感"像切 tab"——无可感知卡顿
- 切换后看到的区域包含最新消息尾部，且为 rich-ready（公式/表格已完成渲染）
- 全链路可度量：`switch.tap → presentedRendered` ≤ 16ms（热会话），冷会话有明确的 graceful degradation 路径

**Non-Goals:**
- 不改变渲染内核（Markdown → NSAttributedString 管线、MathRenderer、TableRenderer）
- 不改变消息持久化模型或 DB schema
- 不改变多会话并发 streaming 的调度模型（RequestScheduler / RequestCoordinator）
- 不支持无限会话常驻（pool 有容量上限，超出的走正常重建路径）
- 不做 SwiftUI 路由的 hot scene pool（仅 AppKit 主路径；SwiftUI fallback 路由保持现有行为）

## Decisions

### D1: 四阶段递进，每阶段独立可验收

**决策**：Phase 0（缓存扩容+预热）→ Phase 1（cell 闪动消除）→ Phase 2（Hot Scene Pool）→ Phase 3（多场景调度），每阶段独立交付、独立可验收，前序阶段不依赖后序。

**理由**：Phase 0+1 改动面小、风险低、收益确定——扩大 cache hit rate + 消除 hit 场景闪动即可解决大部分体感问题。Phase 2+3 是架构级改造，即使延后或中止，Phase 0+1 的收益不丢失。

**替代方案（否决）**：原 plan 的 Phase 1 是 bitmap snapshot gating。否决原因：SwiftUI `ImageRenderer` 无法截图 AppKit 嵌入视图（NSTableView），需要走 AppKit `cacheDisplay` 路径；且 bitmap 与实际 live 内容可能不一致（streaming 场景）；复杂度高于收益。

### D2: RenderCache 会话保护驱逐

**决策**：RenderCache 容量从 64 提升至 256。引入 conversation-aware eviction：每个会话可"保护"最多 P 条最新条目（建议 P=12），驱逐时优先驱逐无保护标记的条目；保护条目仅在所有无保护条目耗尽后才被 LRU 驱逐。

**实现方式**：`RenderCache.CacheKey` 不变（仍为 contentHash+width+styleKey）。新增 `markProtected(key:conversationID:)` 接口，由 prewarm 和 configure 路径调用。内部维护 `protectedKeys: [String: Set<CacheKey>]`（conversationID → keys），驱逐时先从 `accessOrder` 中跳过 protected 条目。

**理由**：全局 LRU 在多会话场景下无法保证"最近切换过的会话"的缓存留存。会话保护确保热会话的渲染结果不被冷会话的新渲染挤掉。

**替代方案（否决）**：per-conversation 独立 cache。否决原因：相同内容不同会话会重复缓存；现有 key 是 content-based 不含 conversationID，改为 per-conversation 需要大幅重构。

### D3: Cell Cache-First 渲染路径

**决策**：改造 `MessageTableCellView.configure()` 流程——对 assistant 消息，在设置任何 textStorage 之前先通过 `MessageContentRenderer.cachedOutput(for:)` 查询 RenderCache。如果命中，直接设置 rich attributedString，不创建 RenderController，不设置 plain fallback。仅在 cache miss 时走现有 plain→async rich 路径。

**关键约束**：
- `cachedOutput(for:)` 是同步调用，不涉及异步开销
- 需要在 `configure()` 时已知 `availableWidth`（当前已有，来自 `tableView.bounds.width`）和 `RenderStyle`（当前已有，`MessageTableCellView.sharedRenderStyle`）
- Streaming 消息（`isStreaming == true`）永远走现有路径，不做 cache-first

**对 SwiftUI MessageBubble 的对等改造**：在 `RenderController.requestRender()` 的非 streaming 路径中，如果 `cachedOutput` 命中，synchronously 设置 `currentOutput` 后 return（当前代码第 279-291 行已经这样做）。但需确保 MessageBubble 的 view body 在首次渲染时读到非 nil 的 `currentOutput`——检查是否存在 view 创建 → RenderController 创建 → requestRender 之间的时序窗口导致首帧为空。

### D4: Hot Scene Pool 架构

**决策**：引入 `HotScenePool`（@MainActor final class），管理最多 N=3 个 `ConversationViewController` 实例。它作为一个 NSViewController 容器嵌入 `ChatDetailPane`，替代当前的单 `ConversationViewControllerRepresentable`。

**内部结构**：
```
HotScenePoolRepresentable (NSViewControllerRepresentable)
  └── HotScenePoolController (NSViewController, 容器)
       ├── ConversationViewController [conv-A] ← isHidden=false (active)
       ├── ConversationViewController [conv-B] ← isHidden=true
       └── ConversationViewController [conv-C] ← isHidden=true
```

**切换流程**：
1. `switchTo(conversationID:)` 被调用
2. 如果 pool 中已有目标 scene → `currentScene.view.isHidden = true; targetScene.view.isHidden = false`（O(1)）
3. 如果 pool 中没有 → 淘汰 LRU 最冷的 scene，创建新 scene，apply messages，show
4. 淘汰 scene 的清理：`removeFromParent()`, cell pool 自动释放

**SwiftUI 集成**：单个 `HotScenePoolRepresentable` (NSViewControllerRepresentable) 包装 `HotScenePoolController`。`updateNSViewController()` 接收 `container` 状态变化，转发给 active scene 的 `renderConversationState()`。

**理由**：NSViewController 容器模式是 macOS 成熟范式。比多个 NSViewControllerRepresentable + 条件显示更可控（避免 SwiftUI 生命周期干扰隐藏 scene）。

### D5: 多场景调度器改造

**决策**：`ConversationRenderScheduler` 从单 `activeConversationID` + 单 `activeGeneration` 改为分层优先级：

```swift
enum SceneTier: Comparable { case active, hot, cold }

// stale 判定改为：
private func isStale(_ key: RenderWorkKey) -> Bool {
    let tier = sceneTier(for: key.conversationID)
    if tier == .cold { return true }  // 仍然 prune cold
    if tier == .active || tier == .hot {
        return key.generation != generation(for: key.conversationID)
    }
    return false
}
```

- `active`：当前可见 scene，渲染任务正常执行
- `hot`：pool 中隐藏 scene，渲染任务执行但优先级降一级（high→visible, visible→deferred）
- `cold`：不在 pool 中的会话，仍然 prune

**接口变更**：`setActiveConversation()` 改为 `setSceneConfiguration(active:hotConversationIDs:generations:)`，由 `HotScenePool` 在切换时调用。

**替代方案（否决）**：每个 scene 独立 scheduler。否决原因：`MessageRenderRuntime` 是单例持有单 scheduler，所有 `RenderController` 共享；改为多 scheduler 需要改造 `RenderController` 的创建路径，且多 scheduler 并行执行会失去全局 budget 控制。

### D6: Hidden Scene 的 Streaming Delta 处理

**决策**：hidden scene 接收 streaming delta 时**不立即 reloadData**。改为标记 `needsReload = true`，在 scene 变为 visible 时一次性 apply。

**实现调用链（避免歧义）**：
- 消息增量进入 `AppContainer.appendMessage(_:toConversation:)` 后，对非 active 会话调用 `hotScenePool?.markNeedsReload(conversationID:)`
- `HotScenePool.markNeedsReload(conversationID:)` 将目标 scene 的 `needsReload` 置为 `true`
- `HotScenePoolRepresentable.updateNSViewController()` 仅驱动 active scene 更新；hidden scenes 不走 `update` 级联
- 切回该会话时，`HotScenePoolController.switchToActiveConversation()` 若发现 `needsReload == true`，执行一次 `applyConversationState(...)` 并清除 dirty 标记

**理由**：hidden NSTableView 的 reloadData 虽然不触发绘制，但仍走 cell 生命周期（prepareForReuse + configure），造成不必要的主线程开销。defer 到可见时批量 apply 更高效。

**但 streaming 完成时**：即使 hidden，也触发一次 prewarm（将最终 content 渲染入 RenderCache），确保切回时 cache hit。

### D7: 预热策略扩展

**决策**：三种新预热触发点：

1. **Switch-away prewarm**：`beginConversationActivation()` 中，在切换到新会话后，异步对 sidebar 中下一个/上一个会话执行 prewarm（如果不在 cache 中）
2. **Idle prewarm**：当 active 会话无 streaming 且无用户输入超过 2s（实现常量：`RenderConstants.idlePrewarmDelay = 2.0`），对 pool 中 hot scene 的 tail 消息执行 prewarm
3. **Streaming-complete prewarm**：后台会话 streaming 完成时，对其最新 assistant 消息执行 prewarm

**策略边界**：
- 对 **hot** 会话：执行 tail K 条持续维护（continuous tail prewarm）
- 对 **cold** 会话：仅执行 streaming 完成时的**一次性 final-message prewarm**，不执行持续 tail 维护

预热均通过现有 `MessageContentRenderer.prewarm(inputs:)` 执行。prewarm 的线程安全策略见 D8。

预热使用的 `availableWidth` 统一取 `HushSpacing.chatContentMaxWidth`（当前 startup prewarm 已采用此值），不依赖具体 view 的 bounds。这确保即使 scene 已被淘汰（无 view），prewarm 仍有确定的 width 来源。

### D8: 线程安全策略

**决策**：所有 prewarm（switch-away / idle / streaming-complete）**在 @MainActor 上执行**，不使用 `Task.detached`。prewarm 通过 `Task(priority: .utility)` 发起（注意：非 `Task.detached`），因为 `Task {}` 在 `@MainActor` 上下文中继承 actor isolation，保证 `MessageContentRenderer.prewarm()` 和 `RenderCache` 的所有访问都在主线程。

**边界澄清**：上述“不使用 `Task.detached`”仅约束 **RenderCache / prewarm 渲染链路**。仓库中的其他非渲染工作（例如 DB 拉取、统计查询）可继续按各自场景选择并发模型，不在本决策范围内。

**理由**：`RenderCache` 和 `MessageContentRenderer` 都不是线程安全的——没有锁，没有 `@Sendable`，没有 actor isolation。当前的 startup prewarm 实际也运行在 `@MainActor`（通过 `messageRenderRuntime.prewarm()`，而 `MessageRenderRuntime` 是 `@MainActor`）。引入 `Task.detached` 到后台线程会造成数据竞争。

**utility 优先级的意义**：虽然在主线程执行，`Task(priority: .utility)` 确保 prewarm 的 render 工作让位于用户交互（`.userInitiated`）和 UI 更新（`.high`）。每条消息的 render 在 prewarm 循环中间 yield（通过 `Task.isCancelled` 检查 + `Task.yield()`），避免长时间占用主线程。

**关键约束**：
- `MessageContentRenderer.prewarm(inputs:)` 需要改为在每轮迭代之间检查 `Task.isCancelled` 并调用 `await Task.yield()`
- 方法签名从 `func prewarm(inputs:)` 改为 `func prewarm(inputs:) async`
- 调用方在 `Task(priority: .utility) { await renderer.prewarm(inputs:) }` 中使用

**替代方案（否决）**：给 `RenderCache` 加 `NSLock`。否决原因：锁的引入增加了所有 cache 访问路径的复杂度，且 main-thread render（configure path）会因锁竞争产生延迟。不值得。

### D9: Protection 数据结构与生命周期

**决策**：`RenderCache` 的 protection 使用双向映射：

```swift
private var conversationToKeys: [String: Set<CacheKey>] = [:]
private var keyToConversations: [CacheKey: Set<String>] = [:]
```

- `markProtected(key:conversationID:)` 同时写入两个映射
- `clearProtection(conversationID:)` 从 `conversationToKeys` 取所有 keys，逐个从 `keyToConversations` 中移除该 conversationID；如果某 key 的 conversations set 变空则该 key 失去保护
- 驱逐判定：`keyToConversations[key]?.isEmpty != false` 即为无保护

**Protection 调用时机**：
- **prewarm 路径**：prewarm 完成后，对该会话缓存的所有 keys 批量 `markProtected`。这是唯一的 bulk protection 入口
- **configure 路径**：**不**调 `markProtected`。configure 只读 cache（`cachedOutput(for:)`），不写 protection。避免每次 reloadData 产生 15-30 次 protection 写入
- **clearProtection 时机**：(1) Hot scene pool 淘汰 scene 时；(2) 会话被用户删除时；(3) 窗口 resize 完成时（清除所有旧 width 的 protection，见 D10）

**每会话 protection 上限**：每个会话最多保护 P=12 个 key。`markProtected` 中如果该 conversation 的 set 已达 P，先移除最早加入的 key 再添加新 key。使用 `Array<CacheKey>` 辅助维护插入顺序。

### D10: 窗口 Resize 缓存策略

**决策**：窗口 resize 后所有旧 width 的 RenderCache 条目自然 miss（CacheKey 包含 width）。Resize 完成后：

1. 清除所有 conversation 的 protection（`clearAllProtections()`）——旧 width 的 protected 条目不再有保留价值
2. 触发一次 active + hot scenes 的 tail prewarm（使用新 width），使用 `Task(priority: .utility)`
3. Resize 期间的 prewarm 被 debounce——只在 resize 稳定 300ms 后执行

**理由**：Protection 保护旧 width 条目会浪费 cache 容量。及时清除 + 新 width prewarm 确保 resize 后的会话切换仍然 cache hit。

**检测 resize**：`HotScenePoolController.viewDidLayout()` 中检测 bounds.width 变化，debounce 后通知 `HotScenePool` 执行 resize cleanup。

### D11: Feature Flag 读取时机

**决策**：`HUSH_HOT_SCENE_POOL` 环境变量在 app 启动时读取一次，缓存为 `static let`：

```swift
enum HotScenePoolFeature {
    static let isEnabled: Bool = {
        guard let raw = ProcessInfo.processInfo.environment["HUSH_HOT_SCENE_POOL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return true } // 默认启用
        return raw != "0" && raw != "false"
    }()
}
```

**理由**：运行时切换 pool 模式会导致 view hierarchy 不一致。启动时一次性决定，整个 app 生命周期不变。

## External References (Design Coherence)

- Apple: `NSViewControllerRepresentable` lifecycle (`makeNSViewController` / `updateNSViewController`)
  - https://developer.apple.com/documentation/swiftui/nsviewcontrollerrepresentable
  - https://developer.apple.com/documentation/swiftui/nsviewcontrollerrepresentable/makensviewcontroller(context:)
  - https://developer.apple.com/documentation/swiftui/nsviewcontrollerrepresentable/updatensviewcontroller(_:context:)
- Apple: AppKit/VC containment APIs
  - https://developer.apple.com/documentation/appkit/nsviewcontroller/addchild(_:) 
  - https://developer.apple.com/documentation/appkit/nsviewcontroller/removefromparent()
- Caffeine (pinning ideas, tradeoffs)
  - https://github.com/ben-manes/caffeine/wiki/Faq

## Risks / Trade-offs

**[R1] 内存增长** → Pool 中每个 scene 持有 NSTableView + cell pool + NSTextView per visible cell。估算：3 scene × 15 cells × ~50KB/cell ≈ 2.25MB（基础），含 math image attachments 和 table attachments 时可达 5-15MB。Mac 上可接受。设置 pool 容量上限 N=3（可配置），超出时 LRU 淘汰释放。实施后需进行 Instruments 内存 profiling 验证。

**[R2] 调度器改造影响面** → `ConversationRenderScheduler` 的 stale 逻辑被多处依赖（`RenderController.shouldApplyQueuedOutput`、`pruneStaleWorkItems`）。改造时需确保 cold tier 的行为与现有行为完全一致。→ 用现有 `ConversationRenderSchedulerTests` 作为回归基线，新增 hot tier 专属测试。

**[R3] Cell cache-first 的 width 不一致** → `configure()` 时的 `availableWidth` 可能与 cache 中存储的 width 不同（窗口 resize 后）。→ RenderCache key 包含 width（truncated to int），width 不同自然 cache miss，安全退化到现有路径。

**[R4] Hot scene 淘汰时正在 streaming** → 淘汰一个正在后台 streaming 的 scene 时，其 cells 被销毁但 streaming delta 仍在写入 `messagesByConversationId`。→ 淘汰不影响 streaming 本身（RequestCoordinator 按 conversationId 路由 delta），重新切回时会重新创建 scene 并 apply 最新消息。

**[R5] SwiftUI fallback 路由未改造** → SwiftUI 路由（ChatScrollStage）仍使用 `.id(generation)` 重建。→ 明确为 Non-Goal。SwiftUI 路由是 fallback/debug 用途，主路径是 AppKit。

## Open Questions

- **Q1**：Hot Scene Pool 的 N=3 是否需要暴露为用户设置项？还是固定常量？
  - 建议：固定常量，写在 `RenderConstants` 中。用户无需关心。
- **Q2**：RenderCache 的 conversation protection 需要 `conversationID` 作为标记依据，但当前 `RenderCache.CacheKey` 不含 conversationID（是 content-based）。同一条消息被多个会话引用（不太可能但理论上可能）时，protection 归属如何处理？
  - 建议：protection 是 key→conversationID 的多对多映射，一个 key 可以被多个 conversation 保护。淘汰时只要有任何一个保护方存在就跳过。
- **Q3**：Phase 2（Hot Scene Pool）是否需要 feature flag 控制回退到单 VC 模式？
  - 建议：是的。新增环境变量 `HUSH_HOT_SCENE_POOL=0` 可禁用，退化为当前单 VC 行为。
