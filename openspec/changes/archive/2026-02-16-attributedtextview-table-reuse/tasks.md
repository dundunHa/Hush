## 1. Spec / SSOT

- [x] 1.1 创建 `2026-02-16-attributedtextview-table-reuse` change，明确 AC、范围与回滚
- [x] 1.2 补充 capability delta（table attachment host reuse）

## 2. Runtime Changes

- [x] 2.1 为 `TableScrollAttachment` 增加稳定 `reuseSignature`
- [x] 2.2 在 `AttributedTextView` 引入 `Coordinator` 与 `TableAttachmentHost`
- [x] 2.3 用差量 reconcile 替换全量 remove + rebuild
- [x] 2.4 复用视图时保留横向滚动状态并做 clamp

## 3. Tests

- [x] 3.1 新增 `TableAttachmentHostReuseTests`
- [x] 3.2 回归执行 `TableRenderingTests`
- [x] 3.3 回归执行 `StreamingCoalescingTests`

## 4. Verify

- [x] 4.1 目标测试命令通过
- [x] 4.2 手工验证 checklist（代码审查+单测 `TableAttachmentHostReuseTests` 五项覆盖：复用/保留滚动/清理stale/替换/不合并）
