## Why

当前滚动逻辑存在多处硬编码行为：`ChatScrollStage` 通过 `sleep` 延迟驱动切换滚动，`MessageTableView` 中尾部跟随依赖布尔标志而非状态机，导致竞态与抖动。`AutoScrollPolicy` 语义模糊，未区分"用户主动退出跟随"与"系统暂时抑制"两种场景。

## What Changes

- 引入 `TailFollowStateMachine`：有限状态机驱动尾部跟随行为，明确 following / paused / suppressed 三态转换。
- 迁移 `AutoScrollPolicy` 语义：废弃布尔 flag，改用枚举状态表达策略意图。
- 重构 `ChatScrollStage`：移除 sleep 驱动，改为事件门闩（SnapshotApplied + LayoutReady）触发滚动。
- 引入 `ScrollTelemetryBridge`：SwiftUI ↔ AppKit 双向滚动事件桥接，解耦滚动位置观测。
- 对齐 `MessageTableView` AppKit 路由：统一 scroll-to-bottom 调用点，消除多处散落的滚动触发。
- 文档收敛：更新 `doc/chat-rendering/04-scroll-stability.md` 记录新状态机设计决策。

## Scope

- `Hush/HushCore/TailFollowStateMachine.swift` (new)
- `Hush/Views/Chat/ScrollTelemetryBridge.swift` (new)
- `Hush/Views/Chat/ChatScrollStage.swift` (modified)
- `Hush/Views/Chat/AppKit/MessageTableView.swift` (modified)
- `HushTests/TailFollowStateMachineTests.swift` (new, 25 tests)
- `HushTests/ScrollTelemetryBridgeTests.swift` (new)
- `HushTests/MessageTableViewScrollTests.swift` (new)
- `doc/chat-rendering/04-scroll-stability.md` (modified)
