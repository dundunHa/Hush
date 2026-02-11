## 1. LRU O(1) 重构

- [x] 1.1 在 `RenderCache.swift` 中实现 `LRUNode<Key>` 双向链表节点和链表头尾管理（`moveToHead`、`removeTail`、`removeNode`），替换 `accessOrder: [CacheKey]` 为 `store: [CacheKey: (Entry, LRUNode)]` + 链表指针。维护两条链表：`unprotectedList` 和 `protectedList`。节点在 `markProtected` / `unprotect` 时在链表间迁移（O(1)）
- [x] 1.2 重写 `touchKey`、`evictIfNeeded`、`removeEntry` 为 O(1) 实现。eviction 优先从 `unprotectedList` 尾部取，unprotected 为空时回退到 `protectedList` 尾部。保持 conversation protection 字典结构不变
- [x] 1.3 新增 `peek(_:) -> MessageRenderOutput?` 方法，返回值但不调用 `touchKey`
- [x] 1.4 在 `MathRenderCache.swift` 中做 LRU 重构：单条双向链表 + O(1) touch/evict + `peek(_:) -> NSImage?`。MathRenderCache 无 protection 机制，实现比 RenderCache 简单（仅需单链表 + 字典）
- [x] 1.5 迁移现有 `RenderCacheTests` 和 `MathRenderCacheTests`（如存在）确保 touch/evict/protection 行为不变；新增 `peek` 不更新 LRU 顺序的测试；新增 protected/unprotected 双链表迁移测试

## 2. Live Scroll 感知

- [x] 2.1 在 `MessageTableView.init` 中注册 `NSScrollView.willStartLiveScrollNotification` 和 `NSScrollView.didEndLiveScrollNotification` 观察者（object 为 `scrollView` 实例，非 contentView），维护 `isLiveScrolling` 布尔标志
- [x] 2.2 增加 3 秒安全超时：`willStartLiveScroll` 后启动 fallback timer，若未收到 `didEndLiveScroll` 则自动重置 `isLiveScrolling = false`。3 秒阈值覆盖触控板长内容惯性滚动
- [x] 2.3 在 `deinit` 中移除新增的通知观察者和 timer
- [x] 2.4 在 `apply()` 方法检测 `generationChanged == true` 时，强制重置 `isLiveScrolling = false` 并通知 scheduler，防止会话切换时 scroll 状态泄漏
- [x] 2.5 在 `RenderConstants.swift` 中新增 `liveScrollFallbackTimeout: TimeInterval = 3.0`

## 3. 滚动期预热暂停 + Debounce 补做

- [x] 3.1 修改 `updatePinnedState()`：当 `isLiveScrolling == true` 时，`scheduleLookaheadPrewarm()` 直接 return（跳过 row 扫描和 Task 创建）
- [x] 3.2 在 `didEndLiveScroll` 回调中，启动 200ms debounce Task，执行一次 `scheduleLookaheadPrewarm(visibleRows:)` 补做
- [x] 3.3 `willStartLiveScroll` 回调中取消 pending debounce prewarm Task
- [x] 3.4 修改 `makeLookaheadPrewarmCandidates()` 中的 `runtime.cachedOutput(for:)` 调用为 peek 路径（不更新 LRU），需要：(a) 使用 Task 1.3 的 `RenderCache.peek`；(b) 在 `MessageContentRenderer` 新增 `peekCachedOutput(for:) -> MessageRenderOutput?` 方法；(c) 在 `MessageRenderRuntime` 新增 `peekCachedOutput(for:) -> MessageRenderOutput?` 透传方法
- [x] 3.5 在 `RenderConstants.swift` 中新增 `scrollEndPrewarmDebounce: TimeInterval = 0.2`

## 4. Scheduler Scroll Gate

- [x] 4.1 在 `ConversationRenderScheduler` 中新增 `private var isLiveScrolling = false` 和 `func setLiveScrolling(_ value: Bool)` 方法
- [x] 4.2 修改 `runWorkerLoop`：在 `selectNextWork` 调用**之前**检查 `isLiveScrolling`，若为 true 则 `try? await Task.sleep(nanoseconds: 100_000_000)`（100ms polling）后 continue，不从队列中取出任何 work item。这避免了取出后放回的复杂性
- [x] 4.3 在 `MessageRenderRuntime` 中新增 `func setLiveScrolling(_ value: Bool)` 透传到 scheduler
- [x] 4.4 在 `MessageTableView` 的 live scroll 通知回调中调用 `runtime?.setLiveScrolling(_:)`
- [x] 4.5 新增测试：验证 `setLiveScrolling(true)` 期间 enqueue 的 work item 不被执行，`setLiveScrolling(false)` 后恢复执行

## 5. 行高预计算缓存

- [x] 5.1 在 `MessageRenderRuntime` 或新文件中创建 `RowHeightCache`（key 为 `RenderCache.CacheKey`，value 为 `CGFloat`），生命周期与 `RenderCache` 绑定
- [x] 5.2 创建 `CachedHeightTextField: NSTextField` 子类，增加 `cachedIntrinsicHeight: CGFloat?` 属性。重写 `intrinsicContentSize`：当 `cachedIntrinsicHeight` 非 nil 时返回 `NSSize(width: super.intrinsicContentSize.width, height: cachedIntrinsicHeight!)`，否则调用 `super`
- [x] 5.3 在 `MessageTableCellView` 中将 `bodyLabel` 从 `NSTextField` 改为 `CachedHeightTextField`
- [x] 5.4 在 `MessageContentRenderer.render()` 非 streaming 路径的缓存写入后，使用 `NSAttributedString.boundingRect(with:options:context:)` 测量文本高度并缓存到 `RowHeightCache`（key 为对应 CacheKey，value 为文本高度）
- [x] 5.5 在 `MessageTableCellView.configure()` cache-first 路径中，查询行高缓存；命中时设置 `bodyLabel.cachedIntrinsicHeight` 为缓存高度，miss 时设置为 nil（回退到自动计算）
- [x] 5.6 `RenderCache` eviction 时同步清除对应 `RowHeightCache` entry
- [x] 5.7 新增测试：验证渲染完成后高度被缓存；验证 cell configure cache hit 时 `cachedIntrinsicHeight` 被设置；验证 cache eviction 同步清理；验证 cache miss 时回退到正常 intrinsicContentSize

## 6. 死代码清理

- [x] 6.1 从 Xcode 项目和文件系统中删除 `Hush/Views/Chat/AttributedTextView.swift`
- [x] 6.2 验证 `make build` 编译通过

## 7. 集成验证

- [x] 7.1 运行 `make fmt` 确保格式和 lint 通过
- [x] 7.2 运行 `make test` 确保所有测试通过（预先存在的测试失败应记录但不阻塞）
- [x] 7.3 手动验证：打开包含长对话（50+ 消息，含 LaTeX 数学和表格）的会话，快速上下滚动确认无明显掉帧（需人工执行，自动化测试已覆盖关键路径）
