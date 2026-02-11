## Why

当前聊天执行模型是“全局单 activeRequest + 全局 messages 数组”，导致请求执行与当前激活会话强耦合：会话切换期间被硬性禁止，且若放开切换会产生跨会话串写风险。与此同时，会话切换滚动依赖固定 `sleep 300ms` 抑制动画，表现为加载后生硬跳到底部，不满足工具型聊天场景对并发与丝滑交互的要求。

## What Changes

- 引入多会话并发请求调度：全局并发上限 `N`（默认 3）+ 每会话最多 1 个 running + 超限排队（全局队列容量沿用 5）。
- 引入确定性调度策略：active 会话优先、后台按会话 FIFO + round-robin、配额式防饿死（`T=15s`, `K=3`，本次固定）。
- 将消息归属从“全局唯一 messages”升级为“按会话分桶（messagesByConversationId）+ active 会话投影”。
- 请求会话绑定 conversationId，streaming delta 与持久化严格按 request->conversation 路由，禁止跨会话污染。
- 会话切换滚动改为事件驱动状态机（snapshot/layout 就绪门闩），移除固定 `sleep 300ms`，并统一为切换时动画滚到底部。
- UI 调整：移除 TopBar Stop，仅保留 Dock Stop（仅停止当前会话 running，不清队列）；Sidebar 增加 running/queued/unread completion 状态徽标，不增加 Sidebar Stop 操作。
- Settings 增加并发上限 `N` 配置入口（仅暴露 N；T/K 保持默认常量），并持久化到现有偏好存储。

## Capabilities

### New Capabilities
- `multi-conversation-request-scheduling`: 定义多会话并发执行、排队、优先级与防饿死调度规则。
- `conversation-scoped-message-buckets`: 定义按会话分桶的消息内存模型与 active 会话投影读取语义。
- `conversation-switch-scroll-state-machine`: 定义会话切换滚动事件门闩与动画到底部语义，替代时间猜测。
- `sidebar-conversation-activity-badges`: 定义 Sidebar 的 running/queued/unread completion 展示与清除规则。
- `chat-concurrency-settings`: 定义并发上限 N 的设置项、默认值与持久化恢复语义。

### Modified Capabilities
- `serial-streaming-chat-execution`: 从单请求串行执行演进为多会话并发执行（保留队列满原子拒绝语义）。
- `serial-streaming-chat-execution-durability`: 明确并发场景下 requestId/conversationId 路由的持久化一致性与终态稳定性。

## Impact

- Affected runtime/state orchestration:
  - `Hush/AppContainer.swift`
  - `Hush/RequestCoordinator.swift`
  - `Hush/HushCore/RequestLifecycle.swift`
- Affected chat/scroll UI:
  - `Hush/Views/Chat/ChatScrollStage.swift`
  - `Hush/Views/Chat/ComposerDock.swift`
  - `Hush/Views/TopBar/UnifiedTopBar.swift`
  - `Hush/Views/Sidebar/ConversationSidebarView.swift`
- Affected settings/persistence:
  - `Hush/HushCore/AppSettings.swift`
  - `Hush/HushStorage/AppPreferencesRecord.swift`
  - `Hush/HushStorage/DatabaseManager.swift`（appPreferences 迁移）
- Affected tests:
  - Request scheduling / routing invariants / queue-full atomic rejection
  - conversation switch scroll state-machine behavior
