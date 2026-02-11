## Why

当前 `/Hush/Views/Chat/AttributedTextView.swift` 在每次 `updateNSView` 都会移除并重建全部 `TableScrollContainer` 子视图。对于包含宽表格的消息，这会在非内容型重绘（窗口尺寸变化、布局刷新、父视图状态变化）下引入额外的 subview churn，降低滚动与交互流畅度，并导致用户已滚动的横向位置丢失。

## What Changes

- 为表格 attachment host 增加差量复用机制，避免每次 update 全量重建。
- 新增稳定复用键：`attachment 顺序 + 内容签名`。
- 复用命中时保留横向滚动偏移；尺寸变化时做边界 clamp。
- 仅在内容或宽度变化时更新 text storage / layout。
- 保持现有 Markdown/Math 渲染语义与 guardrail 行为不变。

## Acceptance Criteria

- 同一消息重复 update 时，已有 `TableScrollContainer` 实例可复用，不会全量重建。
- 用户在宽表中的横向滚动位置在重绘后保持；当视口变宽导致越界时会被安全 clamp。
- 从“有表格”切换到“无表格”后，host 中不存在遗留 `TableScrollContainer`。
- 表格内容变化会触发替换，避免误复用。
- 重复/同签名表格在同一消息内不会错误合并（顺序参与 key）。
- 现有 `TableRenderingTests` 与 `StreamingCoalescingTests` 语义保持通过。

## Scope

### In Scope

- `AttributedTextView` 的表格子视图复用与差量同步。
- `TableScrollAttachment` 的稳定签名字段。
- 对应新增回归测试。

### Out of Scope

- `MarkdownToAttributed` 解析策略改造。
- `MessageContentRenderer` / `RenderController` 策略改造。
- 数据库/持久化/主题机制改动。
- 全局 transcript 单 `NSTextView` 重构。

## Risks / Rollback

- 风险：复用 key 设计不当导致误复用。
  - 缓解：顺序 + 签名，并覆盖替换场景测试。
- 风险：宽度变化后滚动偏移越界。
  - 缓解：统一 clamp 逻辑并覆盖测试。
- 回滚：恢复 `updateNSView` 的全量 remove + rebuild 路径（单文件可逆）。
