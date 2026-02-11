## Why

已渲染完成的聊天消息在上下滚动时出现明显掉帧。根因是滚动关键路径被三层主线程工作污染：(1) 每滚动帧触发 lookahead 预热，而预热渲染全量在 `@MainActor` 执行；(2) LRU 缓存的 `touchKey` 采用 O(n) 线性扫描，高频 cache check 累积开销；(3) `usesAutomaticRowHeights` 依赖 NSTextField `intrinsicContentSize`，cell 复用时设置 `attributedStringValue` 触发同步 TextKit 布局。此外 `AttributedTextView`（NSViewRepresentable）已无任何引用，属于死代码应清理。

## What Changes

- **滚动期主线程保护**：引入 live scroll 感知（`willStartLiveScroll` / `didEndLiveScroll` 通知），滚动期间暂停 lookahead 预热和 ConversationRenderScheduler 的 Phase 2 工作消费，scroll-end 后 debounce 补做。
- **LRU 缓存 O(1) 化**：将 `RenderCache` 和 `MathRenderCache` 的内部数据结构从"字典 + 数组"改为"字典 + 双向链表"，`touchKey` / evict 均 O(1)；新增 `peek` 方法（不更新 LRU 顺序）供扫描场景使用。
- **行高预计算缓存**：渲染完成时使用 `NSAttributedString.boundingRect` 计算并缓存行高（以 contentHash + width + styleKey 为 key），cell configure 时通过 CachedHeightTextField 子类重写 `intrinsicContentSize` 直接返回缓存高度，跳过 NSTextField 的 TextKit 同步布局。
- **清理死代码**：移除 `AttributedTextView.swift`（LSP 确认零外部引用）。

## Capabilities

### New Capabilities
- `scroll-aware-render-gating`: 定义滚动期间渲染调度与预热的暂停/恢复门控机制，包含 live scroll 状态检测、scheduler 暂停语义、scroll-end debounce 补做规则。

### Modified Capabilities
- `render-cache-conversation-protection`: LRU 内部结构从 O(n) 数组改为 O(1) 双向链表；新增 `peek` 方法供预热扫描使用，避免滚动期缓存写放大。
- `multi-scene-render-scheduling`: ConversationRenderScheduler 增加 `isLiveScrolling` 门控，滚动期暂停非关键 work items 消费。
- `cell-cache-first-rendering`: cell configure 路径增加行高预计算缓存，cache hit 时跳过 NSTextField intrinsicContentSize 同步布局。

## Impact

- 渲染调度与缓存：
  - `Hush/HushRendering/ConversationRenderScheduler.swift`（增加 live scroll gate）
  - `Hush/HushRendering/RenderCache.swift`（O(1) LRU 重构 + peek + 双链表 protected/unprotected）
  - `Hush/HushRendering/MathRenderCache.swift`（O(1) LRU 重构 + peek）
  - `Hush/HushRendering/RenderConstants.swift`（新增 scroll debounce 常量 + fallback timeout 常量）
  - `Hush/HushRendering/MessageRenderRuntime.swift`（暴露 scroll gate 接口 + peek 接口 + 行高缓存）
  - `Hush/HushRendering/MessageContentRenderer.swift`（新增 peekCachedOutput 通路）
- 滚动与 cell 渲染：
  - `Hush/Views/Chat/AppKit/MessageTableView.swift`（live scroll 通知 + 预热 debounce + 行高缓存 + generation 切换重置 scroll 状态）
  - `Hush/Views/Chat/AppKit/MessageTableCellView`（CachedHeightTextField 子类 + 行高缓存查询）
- 死代码清理：
  - `Hush/Views/Chat/AttributedTextView.swift`（删除）
- 测试：
  - LRU O(1) 正确性测试（touch / evict / peek 语义）
  - scroll gate 暂停/恢复调度测试
  - 行高缓存命中/失效测试
  - 预热 debounce 时序测试
