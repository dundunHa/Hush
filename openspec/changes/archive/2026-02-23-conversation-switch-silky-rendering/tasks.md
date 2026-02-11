## 1. Phase 0: RenderCache 扩容与会话保护驱逐

- [x] 1.1 将 `RenderConstants.messageCacheCapacity` 从 64 提升至 256，同步更新 `RenderCache` 默认构造
- [x] 1.2 在 `RenderCache` 中实现 conversation-aware eviction protection，使用双向映射（`conversationToKeys` + `keyToConversations`）：新增 `markProtected(key:conversationID:)` / `clearProtection(conversationID:)` / `clearAllProtections()` 接口，驱逐时优先淘汰无保护条目
- [x] 1.3 实现 per-conversation protection 上限 P=12：`markProtected` 中若该 conversation 的 set 已达 P，移除最早加入的 key 再添加新 key（使用 Array 辅助维护插入顺序）
- [x] 1.4 新增 `RenderCacheProtectionTests`：验证 protected 条目在存在 unprotected 时不被驱逐；全 protected 时回退 LRU；多 conversation 保护叠加；clearProtection 正确移除；per-conversation 上限 P=12 溢出时移除最早 key；clearAllProtections 清空所有保护
- [x] 1.5 更新现有 `RenderCacheTests` 以适应新容量，确保 eviction 语义不变量通过
- [x] 1.6 评估 `RenderCache.touchKey()` O(n) 性能（n=256）：预计不是热瓶颈，暂不引入 OrderedDictionary / linked list 复杂度；如 Instruments 显示瓶颈再优化

## 2. Phase 0: 预热策略扩展

- [x] 2.1 将 `RenderConstants.startupPrewarmConversationCount` 从 2 提升至 4，`startupRenderPrewarmAssistantMessageCap` 从 4 提升至 8，同步将 `startupPrewarmMessageLimit` 从 9 提升至 17（确保 DB 加载足够消息以覆盖 8 条 assistant 消息）
- [x] 2.2 改造 `MessageContentRenderer.prewarm(inputs:)` 为 `async`：在每轮迭代之间检查 `Task.isCancelled` 并调用 `await Task.yield()`，使 prewarm 可取消且不长时间霸占主线程
- [x] 2.3 实现 switch-away prewarm：在 `beginConversationActivation()` 中，切换完成后通过 `Task(priority: .utility)` 对 sidebar 相邻会话执行 `prewarmRenderCache`（注意：不使用 `Task.detached`，保持 @MainActor 隔离），prewarm 完成后调用 `markProtected` 批量保护缓存条目
- [x] 2.4 实现 idle prewarm：当 active 会话无 streaming 且无用户输入超过 2s，通过 `Task(priority: .utility)` 对 hot 会话执行 tail prewarm；用户活动时通过 `Task.cancel()` 取消正在进行的 prewarm
- [x] 2.5 实现 streaming-complete prewarm：在 `RequestCoordinator` 的 streaming 完成回调中，如果 conversationId != activeConversationId，通过 `Task(priority: .utility)` prewarm 该会话最新 assistant 消息，使用 `HushSpacing.chatContentMaxWidth` 作为 width
- [x] 2.6 新增 `SwitchAwayPrewarmTests`：验证切换触发 prewarm、已缓存会话跳过、prewarm 不阻塞切换、prewarm 使用 chatContentMaxWidth
- [x] 2.7 新增 `IdlePrewarmTests`：验证 idle timeout 触发、用户活动取消（含渲染中途取消保留已完成条目）、仅对未缓存消息执行、prewarm 间 yield 不阻塞主线程
- [x] 2.8 更新 `AppContainerRenderGenerationTests` 中 startup prewarm 测试以适应新的 4×8（+17 message limit）参数

## 3. Phase 1: Cell Cache-First 渲染路径

- [x] 3.1 改造 `MessageTableCellView.configure()`：在 assistant 分支中，先通过 `MessageContentRenderer.cachedOutput(for:)` 查询缓存，cache hit 时直接 `textView.textStorage?.setAttributedString(cached.attributedString)` 并 return，不创建 RenderController
- [x] 3.2 确保 `MessageTableCellView.configure()` 对 streaming 消息（`isStreaming == true`）跳过 cache-first 路径，走现有 RenderController 路径
- [x] 3.3 验证 `RenderController.requestNonStreamingRender()` 的 cache-hit 路径（第 279-291 行）synchronously 设置 `currentOutput`——确认 SwiftUI `MessageBubble` 在首次订阅 `$currentOutput` 时能读到非 nil 值
- [x] 3.4 新增 `CellCacheFirstRenderingTests`：验证 cache hit 时 textStorage 直接为 rich、不创建 RenderController；cache miss 时走 plain→rich 路径；streaming 时跳过 cache-first
- [x] 3.5 运行 `make test` 确保现有 `RenderControllerSchedulingTests` / `ChatRenderingPerfHarnessTests` 全部通过

## 4. Phase 2: HotScenePool 基础架构

- [x] 4.1 新增 `RenderConstants.hotScenePoolCapacity = 3`
- [x] 4.2 新增 `HotScenePoolFeature` enum：`static let isEnabled` 读取 `HUSH_HOT_SCENE_POOL` 环境变量一次并缓存，采用与 `RenderDebug.isEnabled` 相同的模式
- [x] 4.3 新增 `HotScenePool`（@MainActor final class）：管理 `ConversationViewController` 实例池，支持 `switchTo(conversationID:messages:...)` / `evictColdest()` / `sceneFor(conversationID:)` 接口；淘汰时优先淘汰空会话（0 消息）scene
- [x] 4.4 HotScenePool 内部维护 LRU 顺序（accessOrder），提供 `hotConversationIDs` 属性
- [x] 4.5 新增 `HotScenePoolController`（NSViewController）：容器 VC，持有 HotScenePool，管理子 VC 的 addChild/removeFromParent 与 view hierarchy
- [x] 4.6 新增 `HotScenePoolRepresentable`（NSViewControllerRepresentable）：SwiftUI 桥接层，替代 `ConversationViewControllerRepresentable`；`updateNSViewController()` **仅**转发给 active scene，不转发给 hidden scenes
- [x] 4.7 改造 `ChatDetailPane.body`：根据 `HotScenePoolFeature.isEnabled` 选择 `HotScenePoolRepresentable` 或原 `ConversationViewControllerRepresentable`
- [x] 4.8 新增 `HotScenePoolTests`：验证 pool 容量限制、LRU 淘汰顺序（空会话优先淘汰）、scene 复用（无 reloadData）、清理后无悬挂引用、feature flag 一次性读取

## 5. Phase 2: Hot Scene 切换语义

- [x] 5.1 实现 visibility toggle 切换：`HotScenePoolController.switchTo()` 中，已有 scene 仅切换 `view.isHidden`，不调用 `reloadData`
- [x] 5.2 实现 cold miss 路径：pool 满时淘汰 LRU scene，创建新 `ConversationViewController`，apply messages，add to hierarchy，show
- [x] 5.3 确保 evicted scene 的 cleanup：`removeFromParent()` + `view.removeFromSuperview()` 后 cell pool 通过 NSTableView 自动释放；eviction 时调用 `renderCache.clearProtection(conversationID:)` 清除该会话的 protection
- [x] 5.4 确保后台 streaming 的 scene 被淘汰时不影响 streaming：验证 `RequestCoordinator` 仍按 conversationId 路由 delta
- [x] 5.5 实现 scroll position 保留：hot scene 内部 NSScrollView 状态天然保留（不重建），验证切换回后 scroll offset 不变
- [x] 5.6 新增 `HotSceneSwitchTests`：验证 visibility toggle 不触发 cell reconfigure；cold miss 正确创建 scene；eviction 不中断 streaming；eviction 清除 protection

## 6. Phase 2: Hidden Scene 延迟更新

- [x] 6.1 在 `ConversationViewController` 中新增 `needsReload: Bool` 标记
- [x] 6.2 改造消息更新路径：当 scene isHidden 时，设置 `needsReload = true` 而非直接 `reloadData`；确保 `HotScenePoolRepresentable.updateNSViewController()` 不转发状态给 hidden scenes
- [x] 6.3 在 scene 变为 visible（`switchTo` 或 `view.isHidden = false`）时，检查 `needsReload` 并执行一次 `apply(messages:...)` + `reloadData`
- [x] 6.4 新增 `HiddenSceneDeferredUpdateTests`：验证 hidden 时不 reloadData；变 visible 后执行 reload；非 dirty scene 不 reload；SwiftUI updateNSViewController 不触发 hidden scene 的 renderConversationState

## 7. Phase 3: 多场景渲染调度器改造

- [x] 7.1 在 `ConversationRenderScheduler` 中引入 `SceneTier` enum（active/hot/cold）和 `sceneConfiguration` 状态
- [x] 7.2 新增 `setSceneConfiguration(active: (String, UInt64), hot: [(String, UInt64)])` 接口，将 `setActiveConversation()` 改为兼容 wrapper（等价于 `setSceneConfiguration(active: (id, gen), hot: [])`）
- [x] 7.3 改造 `isStale()` 方法：cold → prune，hot → 检查 per-conversation generation，active → 现有逻辑
- [x] 7.4 实现 hot tier 优先级 demotion：hot 会话的 high→visible、visible→deferred
- [x] 7.5 在 `HotScenePool.switchTo()` 时调用 `scheduler.setSceneConfiguration()` 更新所有 tier
- [x] 7.6 新增 `MultiSceneSchedulerTests`：验证 active 工作按原始优先级执行；hot 工作 demoted 执行；cold 工作 pruned；generation 不匹配 pruned；atomic configuration 更新；`setActiveConversation` wrapper 等价于 `setSceneConfiguration(active:, hot: [])`

## 8. Phase 3: Tail Prewarm 持续维护

- [x] 8.1 实现 hot scene 的 streaming-complete tail prewarm：streaming 完成时对 hot scene 的最新 K 条 assistant 消息执行 `prewarmRenderCache()`
- [x] 8.2 确保 tail prewarm 仅对 RenderCache 未命中的消息执行渲染（通过 `cachedOutput` 检查）
- [x] 8.3 新增 `TailPrewarmTests`：验证 hot scene streaming 完成触发 prewarm；已缓存消息跳过；cold 会话不触发

## 9. 窗口 Resize 缓存清理

- [x] 9.1 在 `HotScenePoolController.viewDidLayout()` 中检测 `bounds.width` 变化，debounce 300ms 后触发 resize cleanup
- [x] 9.2 Resize cleanup：调用 `renderCache.clearAllProtections()`，然后对 active + hot scenes 触发 tail prewarm（新 width）
- [x] 9.3 确保 conversation 删除时调用 `renderCache.clearProtection(conversationID:)` 清除对应保护
- [x] 9.4 新增 `ResizeCacheCleanupTests`：验证 resize 后旧 protection 被清除；debounce 期间不触发 prewarm；resize 稳定后触发新 width prewarm

## 10. 埋点与度量

- [x] 10.1 新增 `PerfTrace.Event.switchPresentedRendered`：记录切换首帧呈现方式（hot-scene / cache-hit-reload / cache-miss-reload）与耗时
- [x] 10.2 新增 `PerfTrace.Event.renderCacheHitRate`：在切换时记录 cache hit / miss 比例
- [x] 10.3 在 `HotScenePool.switchTo()` 中埋点：区分 hot hit（visibility toggle）vs cold miss（新建 scene）
- [x] 10.4 确保现有 `ConversationSwitchTrace`（snapshotApplied / layoutReady / richReady）对 hot scene 路径仍正确记录

## 11. 回归验证与集成

- [x] 11.1 运行 `make test` 全部通过
- [x] 11.2 运行 `make build` 通过
- [x] 11.3 运行 `make fmt` 通过（SwiftFormat + SwiftLint clean）
- [x] 11.4 脚本化验证（xcrun xctrace + App 自动场景）：验证 3 个 hot scene 的内存开销不超过 15MiB（Activity Monitor: memory-physical-footprint）
  - 入口（全自动）：`make xctrace-memory XCTRACE_ARGS="--automation"`（自动计算 baseline/hot 窗口，默认断言 0–15MiB，FAIL 退出码=4）
  - 可选（更严格区间）：`make xctrace-memory XCTRACE_ARGS="--automation --expected-min-mib 5 --expected-max-mib 15 --assert-range"`
  - 输出：生成 `.build/xctrace/*.trace` 与 `*.process-live.xml`，并打印 baseline/hot mean + delta + PASS/FAIL
  - 备注：如需更细粒度（Allocations 的 Live/Persistent Bytes），仍建议手动 Instruments 附加验证
- [x] 11.5 自动化验证（单测覆盖）：4 会话快速回环切换不出现 `cache-miss-reload`（避免 plain→rich 闪动），并至少出现一次 `hot-scene` 路径
  - 覆盖点：`HotSceneSwitchTests.fourConversationLoopAvoidsCacheMissReload()`
- [x] 11.6 自动化验证（单测覆盖）：feature flag `HUSH_HOT_SCENE_POOL=0` 时退化为单 VC 行为，功能正常
  - 覆盖点：feature flag 解析 + 单 VC 切换 apply（见 `FeatureFlagFallbackTests`）
- [x] 11.7 自动化验证（单测覆盖）：后台会话 streaming 中切换不中断 streaming，切回后显示最新内容
  - 覆盖点：中途切走/后台 streaming 继续 + 切回后 apply 最新内容（见 `HotSceneSwitchTests` 新增用例）
- [x] 11.8 自动化验证（单测覆盖）：窗口 resize 后立即切换会话，体验 graceful degradation（cache miss → plain→rich，无 crash）
  - 覆盖点：resize debounce 期间立即切换不崩 + cleanup 仍能在新 width 完成预热（见 `ResizeCacheCleanupTests` 新增用例）
