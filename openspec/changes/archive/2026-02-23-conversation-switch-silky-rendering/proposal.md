## Why

会话切换时存在两个体感问题：(1) 每次切换都通过 `.id(generation)` 销毁并重建整棵 ScrollView/NSTableView 子树，所有 cell 经历 `prepareForReuse → configure → plain text → async rich render` 的完整生命周期，即使 RenderCache 命中也会出现至少一帧的 plain→rich 替换闪动；(2) RenderCache 全局 LRU 仅 64 条目，多会话场景下频繁切换导致缓存驱逐，非 active 会话的渲染任务被 scheduler stale 机制全量丢弃，切回时必须从零重新渲染。这两个问题叠加，使得会话切换无法达到"回环丝滑"的体验标准。

## What Changes

- **Phase 0 — 缓存扩容与预热增强**：将 RenderCache 从全局 LRU 64 升级为带会话保护的 LRU 256；扩大 startup prewarm 覆盖范围（2→4 会话，4→8 条 assistant 消息）；新增 switch-away prewarm（切离会话时预热 sidebar 相邻会话）和 idle prewarm（空闲时预热最近访问会话）。
- **Phase 1 — Cell 闪动消除**：改造 `MessageTableCellView.configure()` 流程，在设置 plain text 之前先查询 RenderCache，cache hit 时直接设置 rich text 跳过 plain fallback；SwiftUI 路由的 `MessageBubble` 做对等改造。
- **Phase 2 — Hot Scene Pool**：维护 2-4 个 `ConversationViewController` 实例池，会话切换变为 visibility toggle 而非销毁重建；引入 `HotScenePool` 管理 scene 生命周期与 LRU 淘汰。
- **Phase 3 — 多场景调度与后台维护**：将 `ConversationRenderScheduler` 从单会话 stale 模式升级为多层优先级（active > hot > cold）；hidden scene 接收 streaming delta 时延迟 batch apply；tail prewarm 持续保证 hot scene 尾部 K 条消息 render-cached。

## Capabilities

### New Capabilities
- `render-cache-conversation-protection`: 定义 RenderCache 的会话保护驱逐策略、容量扩展规则与预热触发条件（switch-away / idle / startup 扩展）。
- `cell-cache-first-rendering`: 定义 MessageTableCellView 和 MessageBubble 的 cache-first 渲染流程，消除 cache hit 场景下的 plain→rich 闪动。
- `hot-scene-pool`: 定义会话视图实例池的容量管理、LRU 淘汰、visibility toggle 切换语义与 scene 状态保留规则。
- `multi-scene-render-scheduling`: 定义 ConversationRenderScheduler 的多会话优先级调度（active/hot/cold 分层）、hidden scene 的 deferred batch apply 与 tail prewarm 持续维护规则。

### Modified Capabilities
- `markdown-message-rendering`: 新增 cache-first 渲染路径要求——非 streaming assistant 消息在 RenderCache 命中时 MUST 直接输出 rich text，不经过 plain fallback 阶段。prewarm 方法改为支持取消和 yield 的 async 版本。

## Impact

- 渲染缓存与预热：
  - `Hush/HushRendering/RenderCache.swift`（驱逐策略改造）
  - `Hush/HushRendering/RenderConstants.swift`（容量常量调整）
  - `Hush/AppContainer.swift`（prewarm 触发扩展：switch-away / idle）
- Cell 渲染流程：
  - `Hush/Views/Chat/AppKit/MessageTableView.swift`（MessageTableCellView.configure cache-first）
  - `Hush/Views/Chat/MessageBubble.swift`（SwiftUI 路由对等改造）
- Hot Scene Pool：
  - `Hush/Views/Chat/AppKit/ConversationViewController.swift`（从单实例改为池化）
  - `Hush/Views/Chat/ChatDetailPane.swift`（嵌入 HotScenePool 替代单 VC）
  - 新增 `Hush/Views/Chat/AppKit/HotScenePool.swift`
- 调度器改造：
  - `Hush/HushRendering/ConversationRenderScheduler.swift`（多会话 stale 策略）
  - `Hush/HushRendering/MessageRenderRuntime.swift`（多 scene 调度接口）
- 测试：
  - RenderCache 会话保护驱逐测试
  - Cell cache-first 渲染路径测试
  - HotScenePool 生命周期与 LRU 淘汰测试
  - ConversationRenderScheduler 多会话优先级调度测试
  - 端到端会话切换性能回归测试
