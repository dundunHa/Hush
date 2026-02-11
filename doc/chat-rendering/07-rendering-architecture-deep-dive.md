# 07 — Rendering Architecture Deep Dive (AppKit Single Path)

## 1. 架构边界

聊天渲染路径已经固定为：

- `ChatDetailPane`
  - `HotScenePoolRepresentable`
    - `HotScenePoolController`
      - `HotScenePool` (LRU 场景池)
      - `ConversationViewController` (每会话一个 scene)
        - `MessageTableView`
          - `MessageTableCellView`
            - `RenderController`
              - `MessageContentRenderer` + `ConversationRenderScheduler`

该路径是唯一生产路径，不再依赖运行时路由开关。

## 2. 会话切换策略

### 2.1 场景池

- 容量固定：`RenderConstants.hotScenePoolCapacity`（默认 3，硬上限 6）。
- 命中热场景：只切换显隐，不重建 scene。
- 冷切换：创建新 scene 或淘汰最冷 scene 后创建。
- 淘汰前会取消可见渲染工作并清理父子视图关系。

### 2.2 generation 纪律

- 切换时 generation 变化作为渲染与调度隔离键。
- scene layout ready 只在每个 generation 首次完成后上报。
- stale generation 的队列工作会被 scheduler 剪枝。

## 3. 列表更新与滚动稳定

`MessageTableView.apply(...)` 是热路径核心，目标是：

- 安全更新 rows
- 保持尾部跟随语义
- 在切换/streaming/append/prepend 下维持正确性
- 持续产出关键 perf 指标（visible recompute、scroll adjust 等）

`TailFollowStateMachine` 负责语义决策，不把滚动策略散落到多处调用点。

## 4. cell 渲染契约

`MessageTableCellView.configure(...)` 契约：

- non-assistant 直接 plain
- assistant 先 cache-first，再按需异步 rich render
- 输出回填必须匹配当前 row 身份，避免 stale 覆盖
- 复用/回收路径必须可取消 render 工作

## 5. 渲染调度与一致性

- non-streaming：进入 `ConversationRenderScheduler` 串行队列
- streaming：`RenderController` 本地合并并直接驱动 renderer
- 任何优化都必须保证 Markdown/LaTeX/表格行为一致
- 优化失败时允许回退到保守路径，优先保证正确性

## 6. 观测点建议

- 切换性能：scene 命中率、冷切换频率、首帧 ready 时间
- 列表性能：apply 模式分布、全量刷新占比
- 渲染性能：cache hit/miss、队列深度、streaming coalesce 命中率
- 滚动稳定：programmatic scroll 次数、suppressed 触发比例

## 7. 回归清单

- 切换后尾部可见且不闪烁
- streaming 连续更新时不触发不必要全量刷新
- prepend 不导致行索引错乱
- scene 淘汰后无挂载残留与回调泄漏
