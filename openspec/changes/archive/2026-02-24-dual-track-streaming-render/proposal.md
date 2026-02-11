## Why

流式聊天内容显示存在两个问题：（1）新会话发起聊天后，流式内容接收一段后停止显示更新（重启后内容完整可见，说明后台入库正常），根因是流式更新链路经过 SwiftUI diff → HotScenePoolController diff guard → reloadData(forRowIndexes:) 这条长链，多个环节可能短路导致断流；（2）即使不断流，每个 delta 端到端延迟 150-300ms+（100ms UI throttle + SwiftUI 渲染周期 + 50ms render coalesce + markdown 渲染时间），远达不到逐字丝滑吐字的体验。

## What Changes

- 新增**快轨（Fast Track）**流式更新路径：RequestCoordinator 直接通过 AppKit 路径推送纯文本到可见 cell，绕过 SwiftUI diff 和 reloadData，延迟降至 ~30ms
- 现有路径降级为**慢轨（Slow Track）**：降低 RequestCoordinator 层输入频率（~200ms），专门负责更新 `@Published messages` 模型 + 触发富文本 markdown 渲染。RenderController 自身的 coalesce 间隔保持 50ms 不变，避免误伤非流式渲染场景
- 修复 `resolveUpdateMode` 中流式结束最后一跳的 `.noOp` 断流 bug：用"old/new 任一 isStreaming"替代 `isActiveConversationSending` 门禁，精确覆盖流结束场景且不误触发非流式更新
- 新增 `MessageTableView.updateStreamingCell()` 方法：以 **messageID** 定位目标行（不假设 last row），通过 `tableView.view(atColumn:row:makeIfNecessary:false)` 直接获取可见 cell 并更新纯文本 + 按需调用 `noteHeightOfRows(withIndexesChanged:)` + tail-follow 滚动
- 新增 **cell 层防回退机制**：流式期间 slow-track configure 不得用更短/更旧的 plain text 覆盖 fast-track 已显示的内容；流结束（isStreaming→false）时必须允许最终态覆盖
- 首个 delta 走一次**不节流的 slow-track 插入**，确保消息气泡立即出现，delta#2 起 fast-track 接管低延迟推送
- 对话切换回流式会话时，立即推送一次当前累积内容以对齐 UI
- 打通 `AppContainer → HotScenePool → ConversationViewController → MessageTableView` 的直通路径，暴露流式推送入口

## Capabilities

### New Capabilities
- `streaming-fast-track`: 快轨流式纯文本直推路径——从 RequestCoordinator 到 NSTableView cell 的直达更新通道，绕过 SwiftUI 和 reloadData。包含 cell 层防回退、messageID 定位、高度变化检测后按需刷新行高

### Modified Capabilities
- `markdown-message-rendering`: 慢轨输入频率由 RequestCoordinator 层控制为 ~200ms，但 RenderController 自身 coalesce 间隔保持 50ms 不变。cell.configure 期间遵循防回退规则：流式中不覆盖更长的已显示内容
- `serial-streaming-chat-execution`: handleDelta 从单路径 throttledUIFlush 改为双路径（快轨 + 慢轨）flush。首个 delta 不节流立即插入。resolveUpdateMode 用 `wasOrIsStreaming` 条件替代 `isActiveConversationSending`

## Impact

- **RequestCoordinator.swift**: handleDelta 拆分为 fast/slow 双 flush 路径；首 delta 不节流；新增 `throttledFastFlush`；清理逻辑覆盖 fast/slow 双路径 Task
- **AppContainer.swift**: 新增 `pushStreamingContent(conversationId:content:)` 方法，通过 HotScenePool 直达 active scene；对话切换时对流式会话立即同步
- **ConversationViewController.swift**: 新增 `pushStreamingContent(_:)` 方法，暴露 messageTableView 的流式更新入口
- **MessageTableView.swift**: 新增 `updateStreamingCell(messageID:content:)` 方法，以 messageID 定位行；修复 `resolveUpdateMode` 用 `wasOrIsStreaming` 条件
- **MessageTableCellView**: 新增 `updateStreamingText(_:)` 轻量纯文本更新方法 + `streamingDisplayedLength` 防回退状态追踪
- **RenderConstants.swift**: 新增快轨 flush 间隔常量、慢轨 flush 间隔常量（不修改 `streamingCoalesceInterval`）
- **HotScenePool.swift**: 已有 `sceneFor(conversationID:)` 公开接口，无需修改
