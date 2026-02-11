## Context

阶段二后，性能瓶颈从“每条消息都同步渲染”变成“会话切换瞬间有多个 non-streaming cache miss 竞争主线程”。因此要把渲染成本从“同帧爆发”改为“按优先级分批释放”。

## Design Decisions

### 1) 新增 `MessageRenderHint` 作为调度输入

每条 assistant 消息在渲染请求时附带：

- `conversationID`
- `messageID`
- `rankFromLatest`
- `isVisible`
- `switchGeneration`

该 hint 只用于调度，不影响渲染语义。

### 2) 新增 `ConversationRenderScheduler` 负责 non-streaming 队列

调度器托管于 `MessageRenderRuntime`，全局共享，保证跨 `MessageBubble` 有统一排序与容量控制。

核心类型：

- `RenderWorkPriority`: `high` / `visible` / `deferred` / `idle`
- `RenderWorkKey`: `conversationID + messageID + fingerprint + generation`
- `RenderWorkItem`: `priority + notBefore + enqueuedAt + input + apply`

执行规则：

- 同 key 新任务覆盖旧任务。
- `high/visible/deferred` 立即可执行；`idle` 延迟 `1.5s`。
- 每条执行后 sleep `120ms` 节流。
- 队列超过 `64` 时，只淘汰最低优先级最旧任务，不淘汰 `high`。

### 3) `RenderController` non-streaming 路径改为“队列优先”

当 cache miss：

- 不再直接同步 `renderer.render(...)`
- `currentOutput = nil` 后入队调度器
- 回调应用前校验 `fingerprint == lastRequestedFingerprint`
- 同时校验 `switchGeneration`，防止 stale 覆盖

高优先级（`.high`）cache hit 立即返回；非关键 cache hit 也入队以避免会话切换时 burst 布局。streaming 路径保持原逻辑。

### 4) `ChatScrollStage` 提供最新序与可见性

- 列表改为带 index 的遍历，计算 `rankFromLatest`
- 维护每条消息 frame 与 viewport 交集，得到 `visibleMessageIDs`
- 组装 `MessageRenderHint` 传给 `MessageBubble`

### 5) `AppContainer` 暴露渲染代际

- 新增 `activeConversationRenderGeneration`（只读）
- 每次 `activateConversation` 递增 generation
- runtime 在 generation 变化后丢弃旧 generation 队列项

### 6) 调试指标保持同一开关

`HUSH_SWITCH_DEBUG=1` 下输出：

- scheduler: enqueue/dequeue/drop/skip-stale/queueDepth/waitMs
- controller: priority/enqueue/apply
- container: start/snapshot-applied/rich-ready

## Testing Strategy

- `ConversationRenderSchedulerTests`：顺序、延迟、可见提升、代际丢弃。
- `RenderControllerSchedulingTests`：cache miss 走队列、cache hit 立即、stale 回调丢弃。
- 回归：
  - `StreamingCoalescingTests`
  - `AppContainerPersistenceSemanticsTests`
  - `TableRenderingTests`
  - `TableAttachmentHostReuseTests`
