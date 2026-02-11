## Why

现有优化（共享 renderer + 长文本渐进）已经减少一部分切换等待，但长会话切换仍会在同一时段触发多条 assistant 的富渲染，造成主线程拥塞。问题主因是“渲染调度策略”而非渲染引擎本身。

## What Changes

- 引入 `MessageRenderHint` 与 `ConversationRenderScheduler`，把 non-streaming cache miss 改为队列调度执行。
- 固定调度参数：
  - `latestPriorityCount = 3`
  - `nonStreamingBudget = 120ms`
  - `offscreenDelay = 1.5s`
  - `nonStreamingQueueCapacity = 64`
- 执行顺序策略：
  - 最新 3 条 assistant 为 `high`
  - 其余可见 assistant 为 `visible`
  - 近端离屏为 `deferred`
  - 远端离屏为 `idle`（延迟 1.5s）
- 保持 streaming 渲染语义不变，仅重构 non-streaming cache miss 路径。
- 增加 generation 隔离：会话切换后旧 generation 的排队工作不允许覆盖当前会话。
- 扩展 `HUSH_SWITCH_DEBUG=1` 日志，输出 enqueue/dequeue/drop/skip-stale 与 `snapshot-applied -> rich-ready` 链路耗时。

## Acceptance Criteria

- 会话切换首屏优先可读，最新 3 条 assistant 先完成 rich 渲染。
- non-streaming 渲染按 120ms 预算节流执行，离屏 idle 任务至少延后 1.5s。
- 快速切换会话时，旧 generation 渲染结果不会覆盖当前会话。
- 队列超过 64 时仅丢最低优先级最旧项，不丢 `high`。
- 不改变 Markdown/Math/Table 渲染语义、不改变数据库 schema 与分页语义。

## Scope

### In Scope

- `MessageRenderHint`、`ConversationRenderScheduler`、`RenderController` non-streaming 调度重构。
- `ChatScrollStage` 可见区/最新顺序提示传递到 `MessageBubble`。
- `AppContainer` 渲染 generation 暴露与会话切换代际推进。
- 调度与 stale 丢弃相关单测、回归测试与手工验证日志。

### Out of Scope

- TextKit1 / SwiftMath / table attachment 架构重写。
- 数据层 schema、SQL、分页大小调整。
- streaming 渲染链路重构。

## Risks / Rollback

- 风险：优先级判断错误导致老消息长期不渲染。
  - 缓解：队列容量控制 + 可见提升测试 + idle 补齐测试。
- 风险：代际判断不严导致 stale 回写。
  - 缓解：fingerprint 与 generation 双重校验。
- 回滚：保留 `RenderController` 旧的同步 non-streaming 路径，可单文件回退。
