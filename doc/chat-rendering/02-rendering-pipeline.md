# 02 — Rendering Pipeline

assistant 消息在 AppKit 单路径中统一走 `MessageTableCellView` 渲染管线。

## Pipeline 概览

1. `MessageTableCellView.configure(...)` 生成 `MessageRenderInput`
2. non-streaming 先查 `MessageRenderRuntime.cachedOutput(for:)`
3. cache miss 或 streaming 时，`RenderController.requestRender(...)`
4. `MessageContentRenderer.render(...)` 执行 Markdown/LaTeX/表格转换
5. 输出 `MessageRenderOutput` 并写回 cell

## 两阶段展示契约

- **Phase 1**：先显示 plain fallback（保障首帧反馈）
- **Phase 2**：rich `NSAttributedString` 异步替换 fallback
- **禁止行为**：在新输出尚未就绪时清空当前输出，避免空白闪烁

## 缓存策略

- `RenderCache`：按 content + width + styleKey 命中 non-streaming 输出
- `MathRenderCache`：缓存公式 attachment，降低重复渲染成本
- prewarm 时只处理 non-streaming 输入，避免干扰 streaming 路径

## Guardrails

- 超长内容会在 rich 渲染阶段进行截断保护（保留可见稳定性）
- renderer 失败时回退 plain 输出，不中断 UI
- streaming 请求通过去重/合并抑制高频抖动
