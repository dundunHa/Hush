## Context

`AttributedTextView` 当前在 update 时会调用 `TableScrollAttachment.removeAllTableViews(from:)` 清空旧表格视图，再遍历 attachment 全量重建。这一策略实现简单，但会导致：

- 非内容变化也触发创建/销毁开销。
- 宽表横向滚动状态丢失。
- 长会话中更易出现可感知抖动。

## Design Decisions

### 1) 引入 host 层差量 reconcile

新增 `TableAttachmentHost` 负责：

- 扫描当前 `NSTextView` 中的 attachment 描述符（key + frame + attachment）。
- 基于 key 复用/创建/删除 `TableScrollContainer`。
- 对复用视图恢复横向偏移并做 clamp。

### 2) 复用 key 采用 `ordinal + signature`

- `ordinal`：attachment 在当前 message 中的出现顺序。
- `signature`：`TableScrollAttachment.reuseSignature`（稳定内容签名）。

不把宽度纳入 key，避免窗口 resize 时失去复用能力；宽度变化通过 frame 更新和偏移 clamp 处理。

### 3) `AttributedTextView` 改为变更感知更新

Coordinator 持有：

- `managedViewsByKey`（在 host 内）
- `lastAttributedStringIdentity`
- `lastAvailableWidth`

仅在以下条件之一成立时更新 `textStorage` 或重新布局：

- attributedString 对象身份变化
- availableWidth 超过阈值变化

随后始终执行 host reconcile，保证 frame/存在性正确。

### 4) 保持渲染语义不变

本次不改 `MarkdownToAttributed`、`MessageContentRenderer`、`RenderController`，仅改 host 生命周期管理。

## Testing Strategy

新增 `TableAttachmentHostReuseTests` 覆盖：

- 重复 update 复用实例。
- 横向滚动位置保持与 clamp。
- stale 子视图清理。
- 内容变化触发替换。
- 重复表格不被错误合并。

并保留执行：

- `TableRenderingTests`
- `StreamingCoalescingTests`
