## Context

当前聊天执行与 UI 状态是“单会话中心”模型：`activeRequest` 单例、`messages` 单数组、`isSending` 全局布尔。该模型通过禁止切换会话规避竞态，但无法满足多会话并发 streaming。并且会话切换滚动依赖固定 300ms 抑制窗口，导致视觉跳变。

本次变更跨越 AppContainer、RequestCoordinator、ChatScrollStage、Sidebar、Settings 与偏好持久化，属于跨模块架构重构。数据库 `messages` 已具备 `conversationId` 与 `requestId`，可支撑 request 路由与持久化一致性，不需要新增 message schema。

## Goals / Non-Goals

**Goals:**
- 支持多会话并发 streaming：全局 running ≤ N（默认 3，可配置），同会话 running ≤ 1。
- 引入确定性调度：active 优先、后台按会话 FIFO + round-robin、配额式防饿死（T=15s, K=3，固定常量）。
- 建立会话级消息分桶 `messagesByConversationId`，UI 仅读取 active conversation 投影。
- 建立 request->conversation 强绑定，保证 delta/UI/persist 不串写。
- 会话切换采用事件门闩滚动（snapshot/layout ready），移除 `sleep 300ms`，切换时动画到底部。
- UI 语义更新：移除 TopBar Stop；Dock Stop 仅停止当前会话 running；Sidebar 显示 running/queued/unread completion 徽标。
- 设置页仅暴露并发上限 N，持久化恢复。

**Non-Goals:**
- 不支持同一会话多 request 并行 running。
- 不支持 Sidebar 直接 Stop 操作。
- 不修改 LLMProvider/HTTPClient 协议。
- 不引入新第三方依赖。
- 不修改 messages 表结构。

## Decisions

### 决策 1：采用会话分桶内存模型（方案 A）
**选择**：`messagesByConversationId: [String: [ChatMessage]]` + `activeMessages` 投影。

**原因**：
- 并发场景下后台会话也会持续收 delta，若仍使用单数组会导致 UI 串写或频繁重载 DB。
- 切换会话时可直接投影，减少“切换->加载->闪烁”窗口。

**备选方案**：后台只写 DB，active 才有内存数组。未选原因：切回会话时体验和一致性窗口更差，且会放大 I/O。

### 决策 2：请求上下文与路由绑定 conversationId
**选择**：在请求快照与运行态 session 中显式携带 `conversationId`，所有 delta 与持久化根据 session 路由，禁止使用 `activeConversationId` 作为写入依据。

**原因**：这是防串写不变量的核心。

**备选方案**：按当前 activeConversation 动态路由。未选原因：并发/切换下必然污染。

### 决策 3：调度器采用“active 优先 + RR + aged 配额”
**选择**：
- 全局并发 `N`（默认 3，可配置）
- 全局 queued 容量沿用 5（不含 running）
- 每会话 running 上限 1
- 调度补位顺序：
  1) 若达到 aged 放行时机，优先放行 aged 请求（等待 ≥ T）
  2) 否则 activeQueue 头部
  3) 否则 backgroundQueues 按 round-robin 选队头
- aged 放行时机：每 K 次 active 放行后，若有 aged 则强制放行 1 个（K=3）

**原因**：平衡主观体验（active 快响应）与公平性（防饿死）。

**补充约束**：队列满时执行原子拒绝：不追加用户消息、不入队、不持久化，仅返回可见错误提示。

**备选方案**：
- 全局 FIFO：active 体验差。
- aged 永远优先：可能劣化 active 首 token 延迟。

### 决策 4：滚动从时间门闩改为事件门闩
**选择**：移除会话切换 `sleep 300ms`。改为在本代次 `generation` 下等待 `SnapshotApplied` + `LayoutReady` 后执行动画滚底。

**原因**：固定时延不稳定，且与机器性能/消息复杂度耦合。

**备选方案**：保留 sleep 并调参。未选原因：无法从根上消除竞态。

### 决策 5：UI 控制语义
**选择**：
- 移除 TopBar Stop
- Dock Stop 仅作用于当前 activeConversation 的 running request
- Sidebar 只显示状态徽标，不提供 stop 行为

**原因**：保持操作入口单一，避免跨会话误停；同时提供可见状态。

### 决策 6：Settings 仅暴露 N
**选择**：设置页新增并发上限 N，默认 3；T/K 固定常量。

**原因**：降低认知负担和变更范围，先交付核心能力。

## Risks / Trade-offs

- **[风险] 状态复杂度显著上升** → **缓解**：引入明确数据模型（RequestSession）与纯函数调度选择器，先实现 N=1 兼容路径再放开并发。
- **[风险] `isSending` 语义变更影响现有 UI 分支** → **缓解**：区分全局 running 与 activeConversationRunning 两个派生状态，逐处替换引用并补测试。
- **[风险] 背景 delta 导致过多 UI 刷新** → **缓解**：后台会话只更新其 bucket/持久化，不驱动 active 视图刷新。
- **[风险] 切换滚动事件门闩实现不当导致不滚或双滚** → **缓解**：以 generation 作为唯一作用域，定义一次性 scroll latch 并写测试覆盖。
- **[风险] 偏好迁移（新增 N 字段）不兼容老数据** → **缓解**：AppSettings/DB migration 提供默认值 3，decode 走向后兼容。

## Migration Plan

1. **OpenSpec 锁定契约**：先完成 proposal/specs/design/tasks。
2. **数据结构迁移（兼容态）**：引入 bucket 与 RequestSession，但先保持并发 N=1，保证行为不变。
3. **路由切换**：delta/persist 改为 request->conversation 路由，移除 activeConversation 写入依赖。
4. **调度放开**：启用 N>1、RR、aged 配额。
5. **UI 语义更新**：移除 TopBar Stop、增加 Sidebar 徽标、Dock stop 定向。
6. **滚动状态机**：去 sleep，改事件门闩并统一切换动画滚底。
7. **设置持久化**：新增 N 配置项与 DB 偏好迁移。
8. **测试后补 + 回归**：覆盖核心不变量与调度行为，执行 make test/build/fmt。

**Rollback**：
- 通过 feature flag 或配置回退到 N=1；
- 保持老 UI 路径兼容（TopBar Stop 移除可单独回滚）；
- bucket 模型可退回 active-only 投影，不破坏 DB 数据。

## Open Questions

- unread completion 清除时机是否严格要求“切换并滚动到底后”还是“切换即清除”（当前采用前者）。
- 队列满提示文案是否区分“全局队列满”与“当前会话不可再排队”。
- N 的可配置范围（建议 1...3 或 1...5）最终 UI 是否固定。
