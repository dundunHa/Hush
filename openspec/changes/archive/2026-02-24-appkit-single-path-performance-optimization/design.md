## Context

当前聊天层处于双路径状态：`ChatDetailPane` 同时保留 SwiftUI（`ChatScrollStage`/`MessageBubble`）与 AppKit（`HotScenePoolRepresentable` 或单 VC 回退）分支。  
这导致以下问题：

1. 路由与调试逻辑分叉：`HUSH_APPKIT_CONVERSATION`、`HUSH_HOT_SCENE_POOL` 与 overlay 行为交织，文档与脚本维护成本高。
2. AppKit 热路径存在冗余刷新：`MessageTableView.apply()` 每次全量 `reloadData()`，流式场景下高频触发主线程布局。
3. Cell 渲染存在重复请求：同一输入会反复 `configure` + `requestRender`，放大渲染与绑定开销。
4. 流式性能优化需要与现有渲染安全边界一致：当前渲染链路大量依赖 AppKit 对象与缓存一致性，不能粗暴后台化。

该变更属于跨模块改造（Views + Rendering + tests + docs + Makefile），需要先统一路径，再做热路径性能优化。

## Goals / Non-Goals

**Goals:**
- 聊天展示统一到 AppKit Hot Scene Pool 单路径，移除 SwiftUI 聊天分支与回退桥接。
- `MessageTableView` 从全量刷新改为“增量优先”的稳定更新策略，降低流式期间主线程抖动。
- 引入 cell 级 fingerprint 去重，减少重复渲染请求。
- 在不破坏渲染正确性的前提下，降低流式主线程阻塞感知。
- 保持会话切换与尾部跟随语义不回退。

**Non-Goals:**
- 不重写 Markdown/LaTeX/表格渲染内核。
- 不变更持久化模型与消息路由模型。
- 不引入新的外部依赖。
- 不在本次变更中进行“全链路 detached 后台渲染”重构。

## Decisions

### D1. 单路径化策略：固定 AppKit Pool，删除双路由

**Decision:** `ChatDetailPane` 固定渲染 `HotScenePoolRepresentable`，删除 `ConversationRenderRoute` 与 SwiftUI 聊天分支入口；移除不再需要的回退桥接与 feature gate。

**Rationale:** Hot Scene Pool 已是默认稳定路径，双路由继续存在会持续产生策略与测试分叉。

**Alternatives considered:**
- 保留双路径仅做性能优化：短期改动小，但长期维护成本持续累积，且回归矩阵更大。

### D2. 表格更新策略：增量优先 + 安全回退

**Decision:** `MessageTableView.apply()` 采用分支式更新：
- 会话切换/代际变化：全量 `reloadData()`
- 尾部 append：`insertRows`
- 流式同条更新：定向刷新目标行
- 历史消息 prepend 或无法安全判断 diff：回退全量 `reloadData()`

**Rationale:** 直接“按计数推断 append”会在 prepend 场景出错；必须显式保留安全回退分支。

**Alternatives considered:**
- 全量 diff（逐行比对 + 批量 move/insert/delete）：精细但复杂度和回归风险高于当前目标。

### D3. Cell 去重策略：fingerprint guard

**Decision:** 在 `MessageTableCellView.configure` 增加输入 fingerprint（消息身份、内容签名、streaming 状态、generation、宽度/样式 key）去重；fingerprint 相同直接跳过重复请求。

**Rationale:** 复用与频繁更新场景下存在大量“等价 configure”调用，去重可直接降低 render 请求量。

**Alternatives considered:**
- 仅依赖 `RenderController` 内部去重：仍会重复建立观察与 fallback 写入，收益不完整。

### D4. 预热策略：基于滚动观察链路实现前瞻预热

**Decision:** 不依赖不存在的 `NSTableView` prefetch API；复用现有 `boundsDidChangeNotification` 与可见区信息，计算 lookahead rows，触发低优先级预热。

**Rationale:** 与当前 AppKit 架构兼容，且可控地利用已有 runtime cache。

### D5. 渲染并发策略：分阶段降压，不突破安全边界

**Decision:** 本变更优先通过减少冗余刷新/渲染请求来降压；渲染链路保持现有 actor 安全约束。  
如果后续需要后台化，只允许先拆分“纯计算阶段”，UI/AppKit 对象构建与应用仍留在主线程，单独变更推进。

**Rationale:** 当前渲染输出与缓存大量使用 AppKit 类型，直接 detached 迁移风险高（线程安全与一致性风险）。

## Risks / Trade-offs

- **[Risk] 增量更新误判导致索引错位** → 保留 prepend/未知 diff 的 `reloadData` 回退，先保证正确性。
- **[Risk] 去重过强导致丢更新** → fingerprint 必须包含内容签名与宽度/代际信息；对 streaming 保持可更新路径。
- **[Risk] 单路径化影响现有调试脚本** → 同步更新 `Makefile` 与 `doc/chat-rendering/*`，移除过时环境变量说明。
- **[Risk] 测试重构成本上升** → 需要成组替换与清理双路径相关测试，避免“删代码不删契约”。

## Migration Plan

1. 新建单路径化与性能优化 change artifacts（proposal/design/specs/tasks）。
2. 先落地单路径路由清理（不改渲染策略），确保编译与核心测试通过。
3. 实施 `MessageTableView` 增量更新与 cell fingerprint 去重，逐步补齐回归测试。
4. 实施滚动前瞻预热，验证缓存命中与滚动体感。
5. 最后清理遗留文档、脚本、无效测试与 dead code。

**Rollback strategy:**
- 每阶段保持可独立回滚；若增量更新触发异常，先回退到 `reloadData()` 全量路径，保留单路径化成果。

## Open Questions

- 是否保留仅用于 Debug 的轻量 overlay（不再依赖旧双路由开关）？
- 滚动前瞻预热的窗口大小（ahead rows）默认值是否需要暴露常量配置？
- 后续“纯计算后台化”是否需要独立 capability，而非并入本次变更？
