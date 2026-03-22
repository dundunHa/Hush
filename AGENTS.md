# PROJECT KNOWLEDGE BASE

**Generated:** 2026-03-22 (Asia/Shanghai)
**Commit:** b884caa
**Branch:** main

# AGENTS.md — Hush

Hush 是一个 macOS 原生 LLM chat 客户端，基于 SwiftUI + AppKit 混合界面和 Xcode 工程构建。当前仓库支持多会话并发 streaming、OpenAI-compatible provider、本地 SQLite 持久化、图片附件落盘，以及玻璃主题界面。

## Source Of Truth

- 生产代码以 `Hush/` 目录为准。
- 根目录 `HushCore/` 当前只保留历史文件 `PerfTrace.swift`，不要把它当成主模块目录。
- 子目录 `AGENTS.md` 适合补充局部约束；如果与实际文件结构冲突，以 `rg --files` 和当前源码为准。

## Hierarchy

- `./AGENTS.md`：根目录协作规则、架构总览、开发入口
- `Hush/HushCore/AGENTS.md`：领域模型、调度器、运行时常量
- `Hush/HushProviders/AGENTS.md`：provider 协议、OpenAI-compatible 请求与 streaming 契约
- `Hush/HushRendering/AGENTS.md`：两阶段渲染、缓存与调度约束
- `Hush/HushStorage/AGENTS.md`：GRDB repositories、migrations、附件与持久化
- `Hush/Views/AGENTS.md`：SwiftUI / AppKit 视图层约束
- `Hush/Views/Chat/AppKit/AGENTS.md`：聊天热路径、Hot Scene Pool、`NSTableView` 生命周期
- `HushTests/AGENTS.md`：Swift Testing 约定与测试隔离规则

## Build & Run

```bash
make setup          # 安装 swiftformat / swiftlint / fswatch，并 resolve SwiftPM
make check-tools    # 校验本地工具与 Config/Versions.xcconfig
make resolve        # 仅 resolve 包依赖
make build          # Debug 构建（默认禁用签名）
make check-xcode    # strict concurrency 诊断构建
make test           # 全量 Swift Testing
make test-cov       # 带覆盖率运行测试并输出 xccov 报告
make fmt            # SwiftFormat + SwiftLint
make run            # clean + build + open app + log stream
make dev            # watch Hush/ 与 HushTests/，自动重建并重启
make crash-context  # 导出最近崩溃报告与 unified logs
make xctrace-memory # 录制 Hot Scene Pool 内存轨迹
make version        # 输出 MARKETING_VERSION / CURRENT_PROJECT_VERSION
make release        # Release 构建 + ad-hoc 重签名 + DMG 打包
make clean          # 清理 build、.build 与派生产物
```

如需监听源码改动并自动重建 / 重启 app，直接运行：

```bash
make dev
```

### DerivedData / SwiftPM Cache

- 默认路径：`DERIVED_DATA=/tmp/hush-dd`、`SPM_DIR=/tmp/hush-spm`
- 这么做是为了避开 Dropbox / File Provider 给构建产物打扩展属性，影响 codesign 和测试稳定性
- 如需自定义目录，显式覆写环境变量即可

### Running a Single Test

```bash
xcodebuild test \
  -project Hush.xcodeproj \
  -scheme Hush \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath /tmp/hush-dd \
  -clonedSourcePackagesDirPath /tmp/hush-spm \
  -only-testing:"HushTests/SSEParserTests"
```

## Release Automation

- 版本真相源：`Config/Versions.xcconfig`
- CI 工作流：`.github/workflows/release-dmg.yml`
- push 到 `main` 时会运行 `make test` + `make release`，并更新滚动预发布标签 `main-latest`
- push tag 时会创建或更新对应 GitHub release，并上传当前 DMG
- `make release` 生成 ad-hoc 签名的 `.app`，关闭 `App Sandbox`，随后重新 codesign 并打包 DMG

## Dependencies

- `GRDB.swift` `7.0.0+`
- `swift-markdown` `0.4.0+`
- `SwiftMath` `1.0.0+`
- Homebrew tools：`swiftformat`、`swiftlint`、`fswatch`

## Architecture

```text
Hush.xcodeproj/                # Xcode project，包含 app 与 test targets
Config/Versions.xcconfig       # 版本号真相源
Hush/
  HushApp.swift                # @main 入口，窗口、commands、scene 生命周期
  HushAppDelegate.swift        # 主窗口与菜单栏状态项生命周期
  AppContainer.swift           # 根 ObservableObject、DI 组合根、settings/persistence glue
  RequestCoordinator.swift     # 请求编排、streaming/image 路由、队列推进
  StatusBarController.swift    # 主窗口关闭后的菜单栏入口
  HushCore/                    # 纯领域模型、调度器、主题/参数设置
  HushNetworking/              # HTTPClient、SSEParser
  HushProviders/               # LLMProvider、OpenAIProvider、MockProvider、ProviderRegistry
  HushRendering/               # Markdown/LaTeX/表格渲染、缓存、调度
  HushSettings/                # JSONSettingsStore
  HushStorage/                 # GRDB repositories、migrations、asset store、credential resolver
  HushTheme/                   # 颜色、排版、间距、glass theme token
  Views/
    RootView.swift             # 根 UI 外壳
    Chat/                      # ChatDetailPane、ComposerDock、AppKit bridge
    Sidebar/                   # 会话列表
    TopBar/                    # 顶栏
    Settings/                  # Provider / Agent / Prompt / Data / Archived Threads
HushTests/                     # Swift Testing suites
doc/                           # 工程文档、渲染/切换排障
openspec/                      # specs + changes
scripts/                       # 开发辅助脚本
```

## Key Patterns

- **AppContainer 是组合根**
  - `@MainActor final class ObservableObject`
  - 通过 `AppContainer.bootstrap()` 组装生产依赖
  - 通过 `AppContainer.forTesting(...)` / preview factory 注入测试依赖
- **RequestCoordinator + RequestScheduler 定义请求执行**
  - `RequestCoordinator` 持有运行态、flush state、provider 路由、timeout 与 debug trace
  - `RequestScheduler` 保持纯函数语义，默认全局并发上限 `3`
  - 同一 `conversationId` 同一时刻最多一个运行请求
  - active conversation 优先，但仍保留 round-robin / aged quota 公平性
- **消息按会话分桶**
  - `AppContainer.messagesByConversationId` 是事实来源
  - `messages` 只是 active conversation 的投影
  - 所有 delta 必须按 owning `conversationId` 写回，不能借 `activeConversationId` 猜目标
- **聊天 UI 固定是 AppKit 单路径**
  - 生产路径为 `ChatDetailPane -> HotScenePoolRepresentable -> HotScenePoolController -> ConversationViewController -> MessageTableView`
  - 不再维护 SwiftUI / AppKit 双聊天路由
  - 会话切换依赖 hot-scene pool、generation discipline 与 tail-follow state machine
- **渲染是 cache-first 的 two-phase**
  - assistant 消息先展示 plain fallback，再异步升级为 rich `NSAttributedString`
  - rich render 由 `RenderController` 与 `ConversationRenderScheduler` 负责
  - 不允许在 replacement output ready 前清空当前 output
- **Storage 是 protocol-first 且 SQLite-first**
  - `StorageProtocols.swift` 定义 repository protocols
  - `GRDB*Repository` 是具体实现
  - provider configurations、catalog cache、agent presets、prompt templates、archived thread metadata 都持久化在 SQLite
  - `KeychainAdapter.swift` 只是历史文件名；当前 provider credential 读取不再依赖 Keychain
- **Credential flow**
  - `ProviderConfiguration.apiKey` 持久化在 `providerConfigurations` 表
  - `ProviderConfiguration` 的通用 JSON 编码会排除 `apiKey`
  - `CredentialResolver` 在请求发起前做最终校验与标准化
- **Image generation 是一等请求路径**
  - 图片模型走 `provider.send(...)` 非 streaming 路由
  - 结果附件通过 `FileMessageAssetStore` 物化到本地文件，再写回消息记录
- **Theme system 是 glass-based，不是 dark-only**
  - 当前主题包括 `graphiteGlass`、`lightGlass`、`ivoryGlass`
  - `RootView` 会根据 `theme.usesDarkAppearance` 切换 `preferredColorScheme`
  - 视觉层统一走 `HushColors` / `HushSpacing` / `HushTypography`
- **Window lifecycle 包含菜单栏回退**
  - 主窗口关闭后 app 切到 accessory，显示 `StatusBarController`
  - 从菜单栏可重新激活主窗口或打开设置

## Current Product Facts

- macOS deployment target：`14.0`
- bundle identifier：`com.dundunha.Hush`
- 内置 provider 类型：`openAI`，DEBUG 下额外提供 `mock`
- 主题：`graphiteGlass`、`lightGlass`、`ivoryGlass`
- 默认并发上限：`RuntimeConstants.defaultMaxConcurrentRequests = 3`
- 待处理队列容量：`RuntimeConstants.pendingQueueCapacity = 5`
- 图片生成超时：`RuntimeConstants.imageGenerationTimeoutSeconds = 180`
- 当前数据库迁移版本：`v15`

## Code Style

### Formatting

- `.swiftformat`：4 空格缩进、LF、trim trailing whitespace
- `.swiftlint.yml`：line length warning 140 / error 180；function body warning 80 / error 120；file length warning 600 / error 900
- 提交前运行 `make fmt`

### Naming

- 类型：`UpperCamelCase`
- 属性/方法：`lowerCamelCase`
- 常量：优先放在 `enum` namespace 的 `static let`
- provider / model / request 等缩写保持自然中缀写法，例如 `providerID`、`modelID`

### Concurrency

- 状态持有者优先 `@MainActor final class`
- 领域模型优先 `struct + Sendable + Equatable + Codable`
- 优先 `async/await`、`Task`、`AsyncThrowingStream`
- 跨 actor 边界时显式处理 `nonisolated` / `Sendable`

### Views

- 视图从 `@EnvironmentObject var container: AppContainer` 读取状态
- 颜色、间距、字体必须来自 `HushColors`、`HushSpacing`、`HushTypography`
- 不要把聊天列表替换成 SwiftUI `List`
- 当前界面不是纯暗色，`AppTheme` 同时支持深浅两类玻璃主题

### Storage

- 先定义 repository protocol，再落 `GRDB*Repository`
- 不修改已有 migration，只能追加新 migration
- provider API key 当前持久化在 SQLite `providerConfigurations` 表中
- 通用 JSON 编解码默认不输出 `ProviderConfiguration.apiKey`

## Testing

- 框架：`Swift Testing`
- 禁止：`XCTestCase`、`XCTAssert*`、`setUp()`、`tearDown()`
- 断言：`#expect(...)`、`#expect(throws:)`
- 数据库测试：`DatabaseManager.inMemory()`
- 网络测试：`StubURLProtocol`
- 共享可变状态的 suite 需要 `.serialized`

## Practical Guardrails

- 先看模块级 `AGENTS.md`，再动手
- 涉及聊天切换、流式刷新、渲染性能时，优先读 `doc/chat-rendering/`
- 涉及功能实现或行为变更时，先确认对应 `openspec/specs/` 是否已有规范
- 当前仓库存在局部文档漂移；写代码前先核对真实文件名和符号，而不是只抄旧文档
