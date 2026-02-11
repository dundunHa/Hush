# 03 — Scheduler 与请求去重

## 组件职责

- `RenderController`：每条 assistant 消息一个控制器，负责请求去重与 streaming 合并。
- `ConversationRenderScheduler`：串行执行 non-streaming rich render，按优先级调度并剪枝 stale 任务。
- `MessageRenderRuntime`：共享 renderer + scheduler，确保缓存跨 cell 生命周期复用。

## 优先级模型

- `high`：最新且最关键的消息（如切换后尾部）
- `visible`：当前可视区域相关消息
- `deferred`：近期但非立即可视
- `idle`：离屏低优先级工作（可延迟启动）

## stale 防护

- key 包含 `conversationID + messageID + fingerprint + generation`。
- 当会话不再 active/hot 或 generation 变化时，队列工作会被丢弃。
- apply 前再次校验 fingerprint/generation，避免旧输出覆盖新内容。

## streaming 路径

- 高频 token 更新进入 coalesce 窗口（默认 `RenderConstants.streamingCoalesceInterval`）。
- 同 fingerprint 的 streaming 请求会直接 skip。
- 非 streaming 命中缓存时同步回填，避免无意义排队。
