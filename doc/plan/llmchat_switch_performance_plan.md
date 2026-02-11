# LLM Chat 会话切换丝滑化：实施计划（Phase 1→2→3）

> 目标：会话切换“回环丝滑”，且用户首帧看到的是**渲染完成**的内容（最新消息尾部）。  
> 兼容：现有渲染内核（Markdown + LaTeX / Math + Table attachments），尽量复用 RenderCache / MathRenderCache / Scheduler。

---

## 0. 成功标准（KPI & 可观测）

### 0.1 体验 KPI（必须满足）
- **切换首帧**：`switch.tap -> presentedRendered <= 16ms`（1 帧内）
- **首帧内容**：必须是**已渲染输出**（live rich 或 bitmap snapshot），禁止出现 plain→rich 的“替换闪动”
- **最新尾部**：切换后看到的区域必须包含“最新消息最后部分”，且该部分为 rich-ready（公式/表格已完成）
- **回环切换**：最近 N 个会话互切，无明显卡顿（主观）+ 长帧（>16.7ms）比例不显著上升（客观）

### 0.2 建议埋点
- `switch.presentedRendered`：首帧呈现方式（snapshot/live）与耗时
- `switch.snapshotToLiveSwap`：从 snapshot 过渡到 live 的耗时
- `tailWindow.richReady`：尾部窗口 rich-ready 的达成时间（按 conversationID/widthBucket/styleHash）
- `render.apply.batchCount`：切换窗口内 batch apply 次数（用于控制主线程压力）

---

## 1. Phase 1（最快见效）：Rendered Snapshot Gating（首帧必渲染）

> 核心：切换时**先展示会话的底部渲染快照**（bitmap），后台构建 live；当且仅当 live 达到 Tail Rich Ready 才 swap。  
> 目的：从机制上消灭“切换后等待 rich 队列”的体感停顿。

### 1.1 交付物
- `ConversationSnapshotStore`
  - 为每个会话维护：`bottomSnapshot`（建议 1.0~1.5 屏高度，含 overscan）
  - key：`conversationID + widthBucket + styleHash`
  - 生命周期：切换后优先读；滚动/新消息/样式变化时更新（可节流）
- `ChatSwitchPresenter`
  - 切换事件：优先呈现 snapshot（若无则退化为当前会话保持不变 + loading 占位，但仍避免 plain→rich）
  - 监听 live ready：`tailWindowRichReady == true` 后进行无缝 swap

### 1.2 技术要点
- snapshot 生成方式：
  - macOS 13+：SwiftUI `ImageRenderer`（优先）
  - 兼容 macOS 12：AppKit `cacheDisplay`/`bitmapImageRepForCachingDisplay`
- snapshot 内容选取：永远取“底部区域”（满足“最新消息尾部”要求）
- swap 策略：无动画或极短淡入（避免感知）

### 1.3 验收
- 首帧 `presentedRendered` 100% 为 true
- 冷会话切换也不出现 plain→rich 替换
- `switch.tap -> presentedRendered` 稳定 < 16ms（或接近 1 帧）

---

## 2. Phase 2（体验稳定）：Tail Rich Guarantee（尾部必 ready）

> 核心：把“尾部窗口 rich-ready”从 best-effort 升级为 **硬保证**，确保 live 能快速达到可替换条件。

### 2.1 定义 Tail Window
- 尾部窗口范围：
  - 最近 `K` 条消息（建议 12~20）或
  - 最近 `H` 高度（建议 2 屏高度）  
- 必须包含：最新消息（latest）及其尾部片段

### 2.2 Tail Rich Ready 条件（建议硬条件）
对 tail window 内每条消息：
- `RenderCache` 命中或已产出 `MessageRenderOutput.attributedString`
- Math/LaTeX：`MathRenderCache` 命中或已完成渲染
- Table/attachments：完成 reconcile（避免 live swap 后抖动）
- 最新消息（latest）必须 rich-ready

### 2.3 Tail Prewarm Service（持续维护）
触发：
- 收到新消息（assistant/user）
- 样式变化（字体/主题）
- 宽度变化（窗口 resize、sidebar 展开）
- 会话从冷变热（进入 sidebar 前 X 或最近访问）

策略：
- 优先级：active > hot-but-hidden > others
- 限制：CPU 峰值受控（可用预算窗口 + batch apply）

### 2.4 验收
- `tailWindow.richReady` 在切换后快速达成（例如 <100ms 或直接命中）
- snapshot→live swap 稳定且用户无感

---

## 3. Phase 3（终极回环丝滑）：Hot Scene Cache + Multi-Scene Scheduling

> 核心：最近 N 个会话保持 live scene 常驻，回环切换变成“显示哪个 scene”，几乎 O(1)。  
> 同时让调度器从 active-only 升级为 multi-scene aware，避免后台会话渲染被 stale 掉。

### 3.1 Hot Scene Cache
- 保留最近 `N=2~4` 个会话的 live View/VC
- scene 内部保持自己的滚动/selection 状态
- 切换时：只变更可见 scene（不重建 scroll 子树，不使用 `.id(generation)` 强制重建）

### 3.2 Multi-Scene Scheduling（两种选型）
**推荐：选型 A（彻底）——调度器多会话感知**
- 从 `activeGeneration` 升级为 `generationByConversationID`
- 任务不再以 `conversationID != activeConversationID` 直接 stale
- 以优先级调度：active/hot/idle 分层，避免资源被后台耗尽

**保守：选型 B（风险小）——hot scene 独立 prewarm runner**
- 后台只做 RenderCache/MathCache 预热，不做 UI apply
- 切回时 cache-hit immediate，从而避免排队延迟

### 3.3 验收
- 最近 N 个会话回环切换：体感“像切 tab”
- long frames 不显著上升
- 内存可控：hot scene + snapshots 在目标机器上稳定运行

---

## 4. 风险与对策

### 4.1 内存/存储增长
- snapshot 仅存底部 1~1.5 屏 + overscan；LRU 淘汰
- hot scene 数量 N 控制在 2~4
- RenderCache 增加按会话/宽度桶的容量上限

### 4.2 主线程掉帧（apply 连发）
- batch apply（同一 runloop tick 合并 state 更新）
- 切换窗口 boost 设定时间/数量上限（<=400ms 或前 6~8 个 high）
- Instruments/MetricKit 监控长帧与热量

### 4.3 多会话 stale 隔离改造复杂
- 优先上 Phase 1/2（收益最大、改动小）
- Phase 3 分两步：先 hot scene cache（不改 stale），再升级 multi-scene scheduling

---

## 5. 里程碑建议（按 1~2 周节奏）

- M1：Phase 1 完成（snapshot gating + 指标）
- M2：Phase 2 完成（tail prewarm service + Tail Rich Ready）
- M3：Phase 3 完成（hot scene cache + multi-scene scheduling 选型 A 或 B）

---

## 6. 附：实现优先级清单（最小改动 → 最大收益）
1) snapshot gating（切换首帧 rendered）
2) Tail Rich Ready 硬条件 + 持续尾部预热
3) 移除切换时 `.id(generation)` 的重建依赖（改为状态复位/scene 切换）
4) hot scene cache（2~4）
5) multi-scene scheduling（彻底消灭后台 stale）
