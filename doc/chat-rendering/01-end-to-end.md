# 01 — End-to-End 链路

本文描述 AppKit 单路径下，从会话切换到富文本落盘展示的完整链路。

## 1. 入口与路由

- `ChatDetailPane` 固定渲染 `HotScenePoolRepresentable`（上半区）+ `ComposerDock`（下半区）。
- 不存在运行时聊天路由分支；聊天列表不再经由 SwiftUI 专用舞台组件。

## 2. 会话切换与场景复用

- `HotScenePoolController.update(container:)` 根据 active conversation 执行 `switchToActiveConversation`。
- `HotScenePool` 维护有界 LRU 场景池（默认 `RenderConstants.hotScenePoolCapacity = 3`）。
- 命中热场景时仅做显示切换；冷切换时创建场景或淘汰最冷场景。

## 3. 场景内列表更新

- 每个会话由 `ConversationViewController` 持有一个 `MessageTableView`。
- `applyConversationState(...)` 把当前会话快照（messages/sending/generation）下发到 table。
- generation 变化时触发一次 `markConversationSwitchLayoutReady()`。

## 4. 行级渲染

- `MessageTableView` 将 `ChatMessage` 投影为 `RowModel`。
- `MessageTableCellView.configure(...)`：
  - 非 assistant：直接 plain 文本
  - assistant：先查缓存命中，未命中再进入异步 rich render
- 渲染结果通过 `RenderController.$currentOutput` 订阅回填。

## 5. 渲染内核

- `MessageContentRenderer` 负责 Markdown AST、LaTeX、表格附件生成。
- `RenderCache` + `MathRenderCache` 负责 non-streaming 缓存复用。
- `ConversationRenderScheduler` 负责 non-streaming 队列优先级与 stale 剪枝。

## 6. 滚动语义

- `MessageTableView` 使用 `TailFollowStateMachine` 维持以下语义：
  - 会话切换到有消息时可见底部内容
  - 用户滚动上移时抑制 assistant 自动贴底
  - streaming 中在阈值内保持 tail-follow
