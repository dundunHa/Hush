## 1. TDD: TailFollowStateMachine 单元测试（25 tests）

- [x] 1.1 定义 TailFollowState 枚举（following / paused / suppressed）及状态转换事件。
- [x] 1.2 编写 25 个单元测试覆盖所有状态转换路径、边界事件（用户滚动上滑、内容追加、强制触底）。
- [x] 1.3 实现 `TailFollowStateMachine.swift` 通过全部 25 个测试。

## 2. AutoScrollPolicy 语义迁移

- [x] 2.1 废弃布尔 flag 形式的 `AutoScrollPolicy`，改用枚举表达三种策略语义。
- [x] 2.2 更新 `ChatScrollStage` 及所有调用点，适配新枚举 API。
- [x] 2.3 确保无回归：现有滚动行为测试全部通过。

## 3. ChatScrollStage 重构

- [x] 3.1 移除 `sleep` 延迟驱动逻辑。
- [x] 3.2 引入事件门闩（SnapshotApplied + LayoutReady + generation 作用域）驱动切换滚动。
- [x] 3.3 统一切换滚动语义为 `animated=true`，streaming 会话保持尾部跟随。

## 4. SwiftUI ↔ AppKit 滚动桥接

- [x] 4.1 实现 `ScrollTelemetryBridge`：观测 NSScrollView 滚动位置变化并发布到 SwiftUI 层。
- [x] 4.2 编写 `ScrollTelemetryBridgeTests`：验证事件发布与去抖逻辑。
- [x] 4.3 在 `MessageTableView` 中集成 bridge，替换散落的直接滚动观测。

## 5. AppKit 路由对齐

- [x] 5.1 统一 `MessageTableView` scroll-to-bottom 调用点，移除重复触发路径。
- [x] 5.2 编写 `MessageTableViewScrollTests`：验证滚动触发时序与状态机联动。
- [x] 5.3 确认 AppKit 路由与 TailFollowStateMachine 状态一致。

## 6. 文档收敛

- [x] 6.1 更新 `doc/chat-rendering/04-scroll-stability.md`：记录 TailFollowStateMachine 设计决策、状态图、迁移说明。
- [x] 6.2 补充 AutoScrollPolicy 枚举语义与使用指南。
