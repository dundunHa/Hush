## 1. OpenSpec 契约校准与实现前护栏

- [x] 1.1 审核 proposal/design/specs 一致性：确认 N=3、T=15、K=3、同会话 running≤1、队列容量=5、原子拒绝、TopBar Stop 移除、Dock Stop running-only、Sidebar 徽标 only、切换总是动画到底。
- [x] 1.2 为实现阶段定义不可破坏不变量清单（request->conversation 路由、后台 delta 不污染 active 视图、队列满零持久化写入）。

## 2. 请求模型与调度基础设施改造

- [x] 2.1 在请求快照/会话运行态中增加 conversationId 归属字段，并在 send 提交时捕获当前会话 ID。
- [x] 2.2 将 RequestCoordinator 从单 activeRequest 模型重构为可管理多 RequestSession 的调度器（先兼容 N=1 路径）。
- [x] 2.3 将调度状态拆分为：running 集合、activeQueue、backgroundQueues、round-robin 光标与 aged 配额计数。
- [x] 2.4 实现确定性选择函数：active 优先 + background RR + aged 配额放行（K=3，T=15s）。
- [x] 2.5 实现并发约束：global running≤N、per-conversation running≤1、global queued≤5（不含 running）。

## 3. 消息分桶与路由不变量落地

- [x] 3.1 在 AppContainer 引入 messagesByConversationId 与 active 会话投影，替换单 messages 中心语义。
- [x] 3.2 改造 delta 处理：按 request owning conversation 路由写入 bucket 与持久化，禁止使用 activeConversationId 决定写入目标。
- [x] 3.3 改造错误/停止/完成路径，确保终态消息与持久化始终写入 owning conversation。
- [x] 3.4 改造 messagesForExecution 上下文来源，使用 owning conversation 的 bucket（或等价一致源）。

## 4. 会话切换与滚动状态机改造

- [x] 4.1 移除 ChatScrollStage 中基于固定 sleep 的切换抑制逻辑（300ms）。
- [x] 4.2 引入事件门闩（SnapshotApplied + LayoutReady + generation 作用域）驱动切换滚动。
- [x] 4.3 统一切换滚动语义为 animated=true，并确保切换到 streaming 会话时保持尾部跟随。
- [x] 4.4 放开接收中切换会话限制（移除 beginConversationActivation 中 isSending/pendingQueue guard）。

## 5. UI 语义与设置面板更新

- [x] 5.1 移除 UnifiedTopBar 的 Stop 按钮，仅保留 Dock Stop。
- [x] 5.2 更新 Dock Stop 语义为"仅停止当前会话 running 请求，不清队列"。
- [x] 5.3 在 SidebarThreadRow 增加 running / queued / unread completion 徽标展示。
- [x] 5.4 实现 unread completion 设置与清除规则（后台完成置位；切换并到达尾部后清除）。
- [x] 5.5 在 Settings 增加并发上限 N 配置项（仅 N），并通过现有偏好持久化链路保存与恢复。

## 6. 持久化与迁移

- [x] 6.1 扩展 AppSettings 与偏好记录映射，加入并发上限 N 字段及默认值回填（默认 3）。
- [x] 6.2 增加 appPreferences 迁移版本以持久化 N（不修改 messages 表结构）。
- [x] 6.3 验证旧数据升级路径：无 N 的历史偏好可平滑读取并落默认值。

## 7. 测试后补与回归验证

- [x] 7.1 新增调度器单测：active 优先、RR、公平放行（aged quota）、per-conversation limit、并发上限。
- [x] 7.2 新增路由不变量单测：并发多会话 delta 不串写，错误/停止/完成写入 owning conversation。
- [x] 7.3 新增队列满原子拒绝单测：拒绝时不追加消息、不入队、不持久化。
- [x] 7.4 新增会话切换滚动门闩单测：不依赖 sleep，按 generation 与 readiness 触发动画滚底。
- [x] 7.5 运行并通过 `make test`、`make build`、`make fmt`。
