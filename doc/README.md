# Engineering Docs

本目录用于存放 Hush 的工程化文档（架构/流程/选型/排障）。

## 模块

- `chat-rendering/` — 会话切换、富渲染（Markdown + LaTeX）、渲染调度、滚动稳定性与排障

## 架构概览

- **多会话并发 streaming**：全局并发上限 N（默认 3，可配置），per-conversation running≤1。`RequestScheduler` 提供 active 优先 + round-robin + aged 配额的确定性调度。
- **消息分桶**：`messagesByConversationId` 为每个会话维护独立消息数组；`messages` 为 active 会话投影。所有 request delta 按 owning `conversationId` 路由，不使用 `activeConversationId` 决定写入目标。
- **事件门闩滚动**：会话切换使用 `generation` 作用域的事件门闩（SnapshotApplied + LayoutReady），替代旧的固定 300ms sleep 窗口。

