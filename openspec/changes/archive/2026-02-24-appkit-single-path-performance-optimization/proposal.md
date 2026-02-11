## Why

当前聊天视图仍保留 SwiftUI 与 AppKit 双路径，导致路由、调试开关、测试与文档长期分叉；同时 AppKit 路径在高频流式更新下存在全量 `reloadData()` 与重复 `configure/requestRender`，会放大主线程布局开销并造成滚动与渲染卡顿。需要把聊天渲染收敛到单一路径，并补齐针对流式场景的结构化性能优化。

## What Changes

- 将聊天展示路径单路径化为 AppKit Hot Scene Pool：移除 SwiftUI 聊天渲染分支与回退桥接，`ChatDetailPane` 固定使用 `HotScenePoolRepresentable`。
- 移除仅用于双路径切换的 feature-gate 与相关回退逻辑（包括 `ConversationViewControllerRepresentable` 回退入口），并同步清理对应文档与运行脚本。
- 改造 `MessageTableView.apply` 为“安全增量更新优先、必要时回退全量刷新”的策略，覆盖流式同条更新、尾部 append、新旧会话切换与历史消息 prepend 场景。
- 在 `MessageTableCellView.configure` 增加 fingerprint 去重，避免同输入重复触发 render 订阅与请求。
- 引入滚动前瞻预热机制（基于现有滚动观察链路）以提升滚动进入视区时的缓存命中率。
- 调整渲染执行链路，降低流式阶段主线程阻塞风险；改造需保持现有渲染正确性与 AppKit 线程安全约束。

## Capabilities

### New Capabilities
- `appkit-chat-single-path`: 定义聊天页面固定走 AppKit Pool 路径后的路由、回退移除与代码清理边界。

### Modified Capabilities
- `hot-scene-pool`: 调整 capability 要求，使 Hot Scene Pool 成为默认且唯一聊天会话视图路径，并移除单 VC feature-flag 回退语义。
- `cell-cache-first-rendering`: 增加 cell 级去重约束，避免重复 `configure` 导致的冗余 render 请求与闪动。
- `markdown-message-rendering`: 增加“流式阶段减少主线程阻塞”的执行约束，并明确在性能优化过程中保持 Markdown/LaTeX/表格渲染行为一致。
- `conversation-switch-scroll-state-machine`: 明确单路径化后仍需保持会话切换与流式尾部跟随语义不回退。

## Impact

- 视图路由与聊天容器：
  - `Hush/Views/Chat/ChatDetailPane.swift`
  - `Hush/Views/Chat/AppKit/ConversationViewController.swift`
  - `Hush/Views/Chat/AppKit/HotScenePoolFeature.swift`
  - `Hush/Views/Chat/ChatScrollStage.swift`
  - `Hush/Views/Chat/MessageBubble.swift`
  - `Hush/Views/Chat/ScrollTelemetryBridge.swift`
- AppKit 列表与 cell 渲染热路径：
  - `Hush/Views/Chat/AppKit/MessageTableView.swift`
- 渲染执行与调度：
  - `Hush/HushRendering/RenderController.swift`
  - `Hush/HushRendering/ConversationRenderScheduler.swift`
  - `Hush/HushRendering/MessageContentRenderer.swift`
- 文档与运行入口（环境变量/调试说明）：
  - `Makefile`
  - `doc/chat-rendering/*`
- 测试：
  - AppKit 热路径、滚动策略、feature flag、渲染调度与附件复用相关测试集
