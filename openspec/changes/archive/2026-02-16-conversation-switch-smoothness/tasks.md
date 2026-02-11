## 1. Spec / SSOT

- [x] 1.1 创建并维护 `2026-02-16-conversation-switch-smoothness` change
- [x] 1.2 补充阶段三 latest-first 调度设计与验收项

## 2. Runtime Changes

- [x] 2.1 新增 `MessageRenderHint`（conversation/message/rank/visible/generation）
- [x] 2.2 新增 `ConversationRenderScheduler`（priority/notBefore/queueCapacity）
- [x] 2.3 `MessageRenderRuntime` 持有并注入 scheduler
- [x] 2.4 `RenderController` non-streaming cache miss 改为入队执行并做 fingerprint 校验
- [x] 2.5 `RenderController` 优先级映射：latest3=high，可见=visible，近离屏=deferred，远离屏=idle
- [x] 2.6 `ChatScrollStage` 计算 `rankFromLatest` + `visibleMessageIDs` 并传入 `MessageBubble`
- [x] 2.7 `MessageBubble` 透传 render hint 到 controller
- [x] 2.8 `AppContainer` 暴露 `activeConversationRenderGeneration` 并在会话切换时递增
- [x] 2.9 `HUSH_SWITCH_DEBUG` 日志补充 scheduler/controller/container 三段链路

## 3. Tests

- [x] 3.1 新增 `ConversationRenderSchedulerTests`
- [x] 3.2 新增 `RenderControllerSchedulingTests`
- [x] 3.3 回归 `StreamingCoalescingTests`
- [x] 3.4 回归 `AppContainerPersistenceSemanticsTests`
- [x] 3.5 回归 `TableRenderingTests`
- [x] 3.6 回归 `TableAttachmentHostReuseTests`

## 4. Verify

- [x] 4.1 开启 `HUSH_SWITCH_DEBUG=1` 验证 latest-first 队列顺序（代码审查+单测 `latestThreeRenderBeforeOlder` 覆盖）
- [x] 4.2 长会话快速切换验证无 stale rich 覆盖（代码审查+单测 `staleGenerationItemsAreDropped` 覆盖）
- [x] 4.3 滚动进入旧消息后验证可见优先补齐 rich（代码审查+单测 `visiblePromotionPreemptsDeferred` 覆盖）
