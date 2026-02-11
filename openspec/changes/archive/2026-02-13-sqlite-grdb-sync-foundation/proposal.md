## Why

Hush 当前仅将 `AppSettings` 持久化到本地 JSON，聊天消息仍是内存态，应用重启后会丢失历史会话。随着后续云同步需求，项目需要先建立可迁移、可查询、可跟踪变更的本地数据基础。

## What Changes

- 引入基于 `SQLite + GRDB` 的本地聊天数据存储，用于持久化会话与消息历史。
- 新增数据访问边界（repository/store），将 UI 容器状态与持久化实现解耦。
- 明确 v1 会话边界：应用维持“单个活跃会话（active conversation）”；启动时加载最近会话；`Clear Chat` 创建并切换到新会话（旧会话保留但本轮不新增会话切换 UI）。
- 为未来云同步预留同步元数据（如更新时间、删除标记、设备标识、待同步队列），但本变更不包含远端同步实现。
- 引入凭据分离策略：供应商 API 密钥进入 Keychain；持久化配置（settings / database）仅保存引用标识与非敏感配置。
- 保持现有请求生命周期与队列语义不变，仅扩展其状态落盘能力。

## Capabilities

### New Capabilities
- `chat-history-persistence`: 持久化会话与消息，应用重启后可恢复历史，并支持按时间顺序读取。
- `sync-metadata-foundation`: 为会话/消息引入同步所需元数据与待同步记录基础，支持未来增量同步。
- `secure-provider-credential-storage`: 定义密钥不落库策略，要求敏感凭据通过 Keychain 管理。

### Modified Capabilities
- `serial-streaming-chat-execution`: 在保持单活跃流与 FIFO 队列语义的前提下，补充“持久化写入与崩溃恢复”的行为要求（包括 queue-full 原子拒绝不落盘、streaming 增量写入、终态落盘与重启后恢复一致性）。

## Impact

- Affected code:
  - `/Users/lxp/Library/CloudStorage/Dropbox/code-space/mygitspace/Hush/Hush/AppContainer.swift`
  - `/Users/lxp/Library/CloudStorage/Dropbox/code-space/mygitspace/Hush/Hush/HushCore/ChatMessage.swift`
  - 新增持久化与仓储模块（例如 `Hush/HushStorage/*`）。
- Dependencies:
  - 新增 `GRDB.swift` 依赖（SQLite 访问与迁移）。
  - 新增 Keychain 访问封装（使用 Security framework）。
- Data & schema:
  - 引入数据库 schema、版本迁移与初始化流程。
- Testing:
  - 需要新增仓储层与迁移测试，并补充请求执行后持久化一致性测试。
