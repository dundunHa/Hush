# Chat Rendering (AppKit Single Path)

聊天区域已经统一为 **AppKit 单路径**：`ChatDetailPane` 固定托管 `HotScenePoolRepresentable`，不再在运行时切换 SwiftUI/AppKit 路由。

## 文档目录

1. `01-end-to-end.md`：端到端链路（会话切换 -> 列表更新 -> cell 渲染）
2. `02-rendering-pipeline.md`：Markdown/LaTeX/表格渲染流水线
3. `03-scheduler.md`：`RenderController` + `ConversationRenderScheduler` 调度机制
4. `04-scroll-stability.md`：`MessageTableView` 的 TailFollow 滚动稳定策略
5. `05-tech-selection.md`：当前技术选型与替代方案
6. `06-debugging.md`：调试开关、日志分类与排障路径
7. `07-rendering-architecture-deep-dive.md`：架构深潜与性能边界

## 当前契约

- 会话视图仅通过 `HotScenePoolRepresentable` / `HotScenePoolController` / `ConversationViewController` 呈现。
- 消息列表仅通过 `MessageTableView` + `MessageTableCellView` 更新与渲染。
- assistant 渲染仍是“两阶段 + 缓存优先”：先 fallback 文本，再异步 rich。
- 调试开关仅保留渲染与切换观测用途，不用于路由切换。
