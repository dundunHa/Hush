# 06 — Debugging 指南

## 1) 常用入口

- 本地运行：`make run`
- 主要日志类别：`Rendering`、`PerfTrace`、`SwitchRender`、`SwitchScroll`、`SwitchRenderScheduler`

## 2) 调试开关

- `HUSH_RENDER_DEBUG=1`：渲染链路详细日志
- `HUSH_SWITCH_DEBUG=1`：会话切换与调度日志
- `HUSH_CONTENT_DEBUG=1`：输出内容片段日志（建议仅短时开启）

> 这些开关只影响可观测性，不再用于聊天路由切换。

## 3) 常见问题定位

### A. 切换后首帧为空白或闪动

优先检查：
- cache 命中是否被即时回填
- queued work 是否被 stale 剪枝后仍有后续请求
- cell 是否重复 cancel/recreate 导致输出被覆盖

### B. streaming 卡顿或频繁重排

优先检查：
- `RenderController` 是否发生冗余 request
- `MessageTableView.apply` 是否落入不必要全量刷新
- scheduler 队列深度与 priority 是否符合预期

### C. 滚动贴底异常

优先检查：
- `TailFollow.reduce` 事件序列是否正确
- prepend 场景是否错误触发了 append 逻辑
- `distanceChanged` 与 programmatic grace 窗口是否生效

## 4) 最小排障顺序

1. 先确认 `activeConversationId` / generation 变化时序。
2. 再看 `MessageTableView.apply` 的更新模式与 tail-follow action。
3. 最后看 `RenderController` 去重与 scheduler 剪枝。
