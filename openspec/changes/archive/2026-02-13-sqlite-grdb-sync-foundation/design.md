## Context

Hush 目前只有设置项持久化（JSON），聊天消息与“历史”都来自内存数组。应用重启后无法恢复会话，也无法为未来多端同步提供稳定的数据主键、变更日志与冲突处理基础。该变更需要同时覆盖 UI 状态容器、数据层边界、迁移策略与安全边界（密钥管理），属于跨模块架构升级。

约束条件：
- 保持当前请求生命周期契约不变（单活跃流、FIFO 队列、显式 stop、严格 provider/model 校验）。
- 本次不实现远端同步，只建设本地可同步基础。
- 敏感密钥不得进入任何持久化介质（例如 settings 或数据库文件）。

## Goals / Non-Goals

**Goals:**
- 建立 `SQLite + GRDB` 本地持久化基础，支持会话与消息恢复。
- 引入稳定的数据模型与迁移机制，为后续演进与同步提供可维护路径。
- 定义同步元数据与 outbox 结构，支持后续增量同步扩展。
- 将凭据与业务数据分离，确保 API 密钥通过 Keychain 管理。
- 通过 repository 边界降低 `AppContainer` 对存储实现的耦合。

**Non-Goals:**
- 不实现 CloudKit/自建后端的真实同步流程。
- 不改变现有请求执行语义（仅增加持久化语义）。
- 不实现跨设备冲突可视化或人工合并 UI。
- 不在本轮替换所有设置项存储（`AppSettings` JSON 可继续保留）。

## Decisions

### 1) Storage engine: SQLite + GRDB
- Decision: 采用 SQLite 作为本地数据真相源，使用 GRDB 管理连接、迁移、事务与查询。
- Rationale: 聊天历史属于增长型数据，需稳定查询能力、可预测迁移和未来 FTS 支撑；GRDB 提供 SQL-first 的可控性。
- Alternatives considered:
  - SwiftData/Core Data：CloudKit 集成更顺手，但 SQL 可控性与迁移可见性较弱。
  - 继续 JSON 文件：无法支撑关系查询、增量同步元数据和规模增长。

### 2) Data model: conversation/message normalized schema + sync metadata
- Decision: 使用标准化表结构，核心包含 `conversations`、`messages`，并在两者上引入 `updated_at`、`deleted_at`、`sync_state`、`source_device_id` 等同步元数据。
- Decision: 增加 `sync_outbox` 记录本地变更事件（insert/update/delete），用于未来同步器消费。
- Note: 当前代码实现中的 SQLite 表名为 `syncOutbox`，与文档中的 `sync_outbox` 指代同一实体。
- Rationale: 通过记录级元数据与 outbox，实现“先本地一致，再远端对账”的扩展路径。
- Alternatives considered:
  - 仅靠 `updated_at` 扫描：实现简单，但在删除与重试语义上不足。
  - 直接引入双向同步：范围过大，不满足当前里程碑。

### 3) Write semantics: append-first with request-correlated updates
- Decision: 用户消息在提交被接受时落盘；assistant 首个 delta 创建消息行，后续 delta 基于消息 ID 或 request ID 原地更新，终态（completed/failed/stopped）写入最终状态。
- Decision: 队列满被拒绝时保持原子性，不落盘任何消息。
- Rationale: 与现有运行时契约一致，确保重启后可恢复与运行时相同的可见结果。
- Alternatives considered:
  - 仅在请求完成后一次性落盘：会丢失流式中间态与失败前部分结果。

### 4) Repository boundary and UI integration
- Decision: 新增 repository/store 协议层，`AppContainer` 仅依赖接口，不直接依赖 GRDB。
- Decision: 启动时从 repository 加载最近会话与消息，替代当前纯内存初始化。
- Rationale: 降低后续切换存储策略和测试替身成本。
- Alternatives considered:
  - 直接在 `AppContainer` 内嵌 SQL 调用：耦合高，不利测试与未来同步扩展。

### 5) Credential isolation via Keychain
- Decision: Provider 凭据仅存 Keychain；持久化配置（如 settings / database）仅保存 `credential_ref`（如服务名/账号键），不保存任何 secret material。
- Decision: 凭据缺失或读取失败需抛出显式错误，不允许静默降级到不安全路径。
- Rationale: 数据库文件可能被备份或导出，密钥必须与业务数据分离。
- Alternatives considered:
  - 环境变量-only：不适合最终产品形态，且用户体验差。
  - 数据库加密字段：密钥仍需本地管理，复杂度更高且收益有限。

### 6) Incremental migration strategy
- Decision: 先新增聊天持久化路径；设置项 JSON 持久化策略暂保留，后续可按需合并到 SQLite。
- Decision: 首次启用数据库时若不存在历史数据，按空库启动；无需历史迁移脚本。
- Rationale: 降低引入风险，避免一次性迁移过多路径导致回归面扩大。
- Alternatives considered:
  - 同步迁移 settings + chat 到 SQLite：一致性更高，但范围超出当前变更。

### 7) Conversation semantics: single active conversation (v1)
- Decision: v1 引入 `conversations` 但仅维护“单个活跃会话”。应用启动时加载最近会话；`Clear Chat` 创建并切换到新会话。旧会话数据保留在库中，但本轮不新增“会话列表/切换”UI。
- Rationale: 既满足“重启可恢复历史”的核心目标，又避免在同一轮把 UI/导航/数据结构全量重构成多会话产品。
- Alternatives considered:
  - 永久单会话（无 `conversations` 表）：实现更小，但会把未来多会话/同步扩展成本推高，且难以稳定定义同步粒度。
  - 立即做多会话 UI：范围扩大、回归面显著增加。

### 8) Crash/kill recovery: finalize in-progress records as interrupted
- Decision: 对于处于“streaming/draft”的 assistant 消息，若应用在终态写入前退出（崩溃/强退/断电），下次启动时必须将其标记为 `interrupted`（或等价终态），并禁止后续任何迟到事件继续修改该记录。
- Rationale: 保证“重启后数据可解释且稳定”，同时保持与当前“迟到事件不应改变终态”语义一致。

### 9) Streaming write throttling: coalesce deltas, flush on terminal
- Decision: streaming delta 的持久化更新需要节流/合并（例如以时间窗口 coalesce），并在 `completed/failed/stopped` 终态到达时强制 flush，确保终态与最终内容一致落盘。
- Rationale: 避免每个 delta 一次写盘带来的 I/O 压力与主线程卡顿风险，同时保持终态可恢复的强一致性。

## Risks / Trade-offs

- [数据库引入提高复杂度] -> Mitigation: 通过 repository 接口隔离实现，并增加迁移/仓储测试。
- [双存储并存（JSON settings + SQLite chat）带来认知负担] -> Mitigation: 在文档中明确边界，后续独立变更再收敛。
- [流式更新频繁写入导致 I/O 压力] -> Mitigation: 对 delta 更新采用批量节流或最小写入粒度策略。
- [outbox 长期堆积] -> Mitigation: 设计消费确认与定期清理规则（成功同步后归档/删除）。
- [未来同步冲突复杂] -> Mitigation: 先统一记录级元数据，后续再引入明确冲突策略（LWW/字段级）。

## Migration Plan

1. 引入 GRDB 依赖并建立 `DatabaseManager` 启动路径（app support 目录数据库文件）。
2. 创建 schema v1 迁移：`conversations`、`messages`、`sync_outbox` 与必要索引。
3. 新增 repository 协议与 GRDB 实现，覆盖会话查询、消息追加、消息流式更新、终态写入。
4. 将 `AppContainer` 初始化与消息写路径切换到 repository（保持现有行为契约）。
5. 引入 Keychain 适配层并更新 provider 凭据读取路径。
6. 增加测试：迁移测试、repository 测试、请求生命周期到持久化一致性测试。
7. 验证无回归后作为默认路径启用。

Rollback strategy:
- 保留内存路径作为应急回退开关（仅临时），若发现严重数据回归可切回内存模式并禁用数据库写入。
- 数据库 schema 采用前向兼容迁移，回滚时不做 destructive downgrade，避免数据破坏。

## Open Questions

- 未来云同步目标优先 CloudKit 还是自建 API（会影响 outbox payload 设计）？
- 是否需要在首版即启用全文检索（FTS5）还是延后到检索功能变更？
