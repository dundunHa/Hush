## Context

Hush 的聊天界面基于 NSTableView（`usesAutomaticRowHeights = true`）+ Hot Scene Pool 架构。消息渲染采用两阶段管线：Phase 1 即时纯文本 fallback，Phase 2 异步富文本（Markdown → NSAttributedString，含 LaTeX 数学图片和表格附件）。

当前滚动性能瓶颈集中在三个互相放大的路径上：

1. **`boundsDidChangeNotification` 每滚动帧无差别触发** `updatePinnedState()`，其中 `scheduleLookaheadPrewarm()` 每帧扫描 rows 并调用 `runtime.cachedOutput(for:)`，未命中时进一步触发 `renderer.render()` —— 全量在 `@MainActor` 上执行。
2. **LRU 缓存** `touchKey()` 使用 `accessOrder.firstIndex(of:)` 做 O(n) 线性查找（n≤256），高频 cache check 时累积开销。
3. **Cell 复用时** 设置 `bodyLabel.attributedStringValue` 触发 NSTextField 重算 `intrinsicContentSize`，结合 `usesAutomaticRowHeights` 导致主线程同步布局。

另外，`AttributedTextView.swift`（NSViewRepresentable）经 LSP 确认无任何外部引用，属于历史重构遗留死代码。

## Goals / Non-Goals

**Goals:**
- 消除已渲染消息滚动时的掉帧（目标：稳定 60fps）
- 滚动期间主线程零渲染工作（预热/Phase 2 全部暂停或延迟）
- LRU 缓存操作从 O(n) 降至 O(1)
- Cell 复用路径高度计算优先走缓存，减少 NSTextField 同步布局
- 清理死代码 `AttributedTextView.swift`

**Non-Goals:**
- 不改变渲染管线的 `@MainActor` 隔离模型（将渲染移至后台 actor 是长期目标，不在此 change 范围）
- 不改变 streaming 路径的 fast-track / slow-track 双轨机制
- 不改变 `usesAutomaticRowHeights = true` 为手动 `heightOfRow:` delegate（风险过大，本次以缓存拦截为主）
- 不修改 Hot Scene Pool 容量/淘汰策略
- 不修改 TailFollow 状态机逻辑

## Decisions

### D1: Live Scroll 感知 — 使用 NSScrollView 通知而非自定义标志

**选择**: 监听 `NSScrollView.willStartLiveScrollNotification` 和 `NSScrollView.didEndLiveScrollNotification`（object 为 `scrollView` 实例），维护 `isLiveScrolling` 布尔标志。

**替代方案**:
- 基于 `boundsDidChangeNotification` 频率推断滚动状态 → 不可靠，需要时间窗口 heuristic
- 在 `scrollWheel(with:)` override 中检测 → 侵入性强，且不覆盖触控板惯性滚动

**理由**: NSScrollView 原生提供 live scroll 生命周期通知，语义精确，零额外开销。惯性滚动阶段仍处于 live scroll 窗口内，自然覆盖。

### D2: 滚动期预热策略 — 完全暂停 + scroll-end debounce 补做

**选择**: `isLiveScrolling == true` 时 `scheduleLookaheadPrewarm()` 直接 return，`didEndLiveScroll` 后 debounce 200ms 执行一次预热。同时 `ConversationRenderScheduler.runWorkerLoop` 在 `isLiveScrolling == true` 时，在 `selectNextWork` **之前**检查并 sleep 100ms 循环等待 scroll end，不从队列中取出任何 work item。

**替代方案**:
- 仅暂停预热但不暂停 scheduler → 已入队的 work items 仍会在滚动期执行，占用主线程
- 降低预热频率而非完全暂停 → 仍有主线程抢占，不够彻底

**理由**: 滚动期用户不需要新的 Phase 2 渲染结果（已渲染内容直接从缓存显示），完全暂停是最安全的选择。scroll-end 后统一补做可批量处理，效率更高。

### D3: LRU O(1) 化 — 字典 + 双向链表，无外部依赖

**选择**: 自实现轻量双向链表节点 `LRUNode<Key>`，`store` 改为 `[Key: (value, node)]`，touch/evict 均 O(1)。新增 `peek(_:)` 方法返回值但不更新 LRU 顺序。

**RenderCache protection-aware eviction**: 维护两条双向链表（protected / unprotected），节点在 `markProtected` / `unprotect` 时在链表间迁移。eviction 优先从 unprotected 链表尾部取，unprotected 为空时回退到 protected 链表尾部。这保证了 eviction 操作 O(1)，但增加了 protect/unprotect 操作的链表迁移开销（仍为 O(1)）。

**MathRenderCache**: 无 protection 机制，仅需单条双向链表 + 字典，实现更简单。

**替代方案**:
- 使用 `OrderedDictionary`（swift-collections）→ 引入新 SPM 依赖，违反奥卡姆原则
- 保持数组但用 index 映射加速 → 增删时维护映射复杂度高
- 单条链表 + eviction 时遍历跳过 protected 节点 → 最坏情况 O(n)

**理由**: 双链表是 LRU 的经典最优解，RenderCache 的双链表方案（protected + unprotected）保证所有操作 O(1)，无外部依赖。`peek` 方法消除了预热扫描场景下的缓存写放大。

### D4: 行高预计算缓存 — 渲染完成时存储，cell configure 时拦截

**选择**: 在 `MessageRenderOutput` 旁边引入行高缓存（存储在 `MessageRenderRuntime` 中），key 为 `(contentHash, width, styleKey)`。渲染完成时，使用 `NSAttributedString.boundingRect(with:options:context:)` 测量 body 文本 intrinsic 高度并缓存。Cell configure 时通过 `CachedHeightTextField.cachedIntrinsicHeight` 注入缓存值，跳过 NSTextField 的同步 TextKit 布局。缓存的是 body 文本高度而非总行高——Auto Layout 仍负责叠加 metaLabel 和 padding。

Cell configure 的 cache-first 路径增加行高缓存查询。命中时，通过子类化 NSTextField 重写 `intrinsicContentSize` 返回 `(width, cachedHeight)` 而非触发完整 TextKit 布局计算。子类（`CachedHeightTextField`）持有可选的 `cachedIntrinsicHeight: CGFloat?`，非 nil 时 `intrinsicContentSize.height` 直接返回缓存值，nil 时回退到 `super.intrinsicContentSize`。

**替代方案**:
- 将高度存入 `MessageRenderOutput` 本身 → 耦合渲染输出与 UI 布局；不同宽度下同一 output 高度不同
- 切换到手动 `heightOfRow:` delegate → 需要自行管理所有行高状态，风险高
- 在 `RenderCache.Entry` 中存储高度 → 可行但 cache 本身不应关心 UI 概念
- 仅设置 `preferredMaxLayoutWidth` → 只影响宽度协商，无法跳过高度计算

**理由**: 独立的行高缓存与 RenderCache key 对齐但职责分离。子类化 NSTextField 重写 `intrinsicContentSize` 是最小侵入性方案——保持 `usesAutomaticRowHeights = true` 不变，Auto Layout 正常工作，仅在缓存命中时跳过 TextKit 同步布局。渲染完成时测量一次（离线，不在滚动路径上），后续 cell 复用路径直接命中缓存。

### D5: 死代码清理 — 直接删除 AttributedTextView.swift

**选择**: 直接删除文件，无需迁移。

**理由**: LSP `find_references` 确认 `AttributedTextView` 仅有自引用，无任何外部使用。该文件是从早期 SwiftUI 路径重构到 AppKit 单路径后遗留的死代码。

## Risks / Trade-offs

### [Risk] 滚动期暂停 Phase 2 导致用户看到更久的 Phase 1 fallback
→ **Mitigation**: 仅对新滚入视区且缓存未命中的消息可见（极少数场景）；scroll-end 后 200ms 内补做渲染；已缓存消息不受影响。lookahead 预热在 scroll-end 后立即执行，预覆盖即将进入视区的消息。

### [Risk] O(1) LRU 实现引入链表指针管理 bug
→ **Mitigation**: 专门的单元测试覆盖 touch/evict/peek/protection 交互；现有 RenderCache 和 MathRenderCache 测试套件全量迁移验证。

### [Risk] 行高缓存失效导致行高跳动
→ **Mitigation**: 缓存 key 包含完整 fingerprint（contentHash + width + styleKey）；宽度变化时缓存自然失效重算；resize debounce 300ms 后批量清理。

### [Risk] `didEndLiveScroll` 在某些输入设备上行为差异
→ **Mitigation**: 增加 fallback timer — 如果 `willStartLiveScroll` 后超过 3 秒未收到 `didEndLiveScroll`，自动恢复。3 秒阈值覆盖长内容触控板惯性滚动（通常 2-3 秒）。键盘方向键滚动不触发 live scroll 通知，原有路径不受影响。

### [Risk] 滚动期间切换会话导致 isLiveScrolling 泄漏
→ **Mitigation**: Hot Scene Pool 切换时旧 scene 的 scrollView 被隐藏，可能导致 `didEndLiveScroll` 不触发。在 `MessageTableView.apply()` 检测 `generationChanged == true` 时，强制重置 `isLiveScrolling = false` 并通知 scheduler。3 秒 fallback timer 作为二级保护。

## Open Questions

*无（已全部在 Decisions 中解决）。*

### [Resolved] 行高缓存生命周期
行高缓存与 RenderCache 生命周期绑定：RenderCache eviction 时同步清除对应行高缓存条目。理由：保持一致性，避免行高缓存指向已驱逐的渲染输出。
