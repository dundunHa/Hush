# Hush

<p align="center">
  <img src="Hush/Assets.xcassets/AppIcon.appiconset/appIcon_256x256@2x.png" width="128" alt="Hush logo" />
</p>

Hush 是一个 macOS 原生 LLM chat 客户端，基于 SwiftUI + AppKit + Xcode 工程构建。当前仓库面向 macOS 14，聊天主路径使用 `NSTableView` 热场景池，支持多会话并发 streaming、OpenAI-compatible provider、Markdown / LaTeX / 表格渲染，以及本地优先的数据持久化。

## 核心能力

- 多会话并发请求调度：默认全局并发 `3`，单会话同时最多运行 `1` 个请求，采用 active 优先 + round-robin + aged quota 防饥饿。
- AppKit 单路径聊天渲染：`HotScenePoolRepresentable` + `HotScenePoolController` + `ConversationViewController` + `MessageTableView` 负责高频切换与流式更新。
- 两阶段消息渲染：先展示 fallback 文本，再异步升级为 Markdown / LaTeX / 表格富渲染。
- OpenAI-compatible provider：支持自定义 endpoint、模型目录刷新与缓存、默认模型选择。
- 本地优先存储：GRDB + SQLite 保存会话、消息、provider 配置、agent presets、prompt templates、归档状态、附件与调试信息。
- 图片附件链路：图片生成结果会先物化到本地文件，再写回消息附件元数据并在聊天区预览。
- 玻璃主题与工作区设置：当前内置 `graphiteGlass`、`lightGlass`、`ivoryGlass` 三套主题，并提供 Provider / AI Agent / Prompt Library / Data / Archived 设置页。

## 环境要求

- macOS 14.0+
- Xcode 15+ 与命令行工具
- Homebrew

默认构建缓存使用：

- `DERIVED_DATA=/tmp/hush-dd`
- `SPM_DIR=/tmp/hush-spm`

这样做是为了绕开 Dropbox / File Provider 给构建产物附加扩展属性后引发的 codesign 与测试稳定性问题。

## 快速开始

```bash
make setup       # 安装 swiftformat / swiftlint / fswatch，并 resolve SwiftPM
make build       # Debug 构建
make run         # clean + build + 启动 app，并持续输出渲染/切换日志
make test        # 运行全部 Swift Testing 单元测试
make fmt         # SwiftFormat + SwiftLint
```

如需自定义构建缓存目录，可以在命令前覆写：

```bash
DERIVED_DATA=$PWD/.build/DerivedData \
SPM_DIR=$PWD/.build/SourcePackages \
make build
```

## 常用开发命令

```bash
make check-tools     # 检查 brew 工具、xcodebuild、版本配置是否齐全
make resolve         # 只 resolve SwiftPM 依赖
make check-xcode     # 用 strict concurrency 做诊断构建
make test-cov        # 跑测试并导出 xccov 覆盖率报告
make dev             # watch Hush/ 与 HushTests/，自动重建并重启
make crash-context   # 收集最近崩溃报告与 unified logs 到 .build/crash
make xctrace-memory  # 录制 Hot Scene 内存轨迹并估算 delta
make version         # 输出 MARKETING_VERSION / CURRENT_PROJECT_VERSION
make release         # Release 构建 + ad-hoc 重签名 + 打包 DMG
make clean           # 清理 build、.build 和当前 DerivedData
```

`make run` 会设置并透传这些调试环境变量：

- `HUSH_RENDER_DEBUG`
- `HUSH_SWITCH_DEBUG`
- `HUSH_CONTENT_DEBUG`
- `HUSH_PROVIDER_DEBUG`
- `HUSH_DB_PATH`（仅 DEBUG）

## 单测运行

项目测试框架使用 **Swift Testing**，不是 XCTest。定向运行建议沿用仓库默认缓存目录：

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

运行单个测试方法：

```bash
xcodebuild test \
  -project Hush.xcodeproj \
  -scheme Hush \
  -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath /tmp/hush-dd \
  -clonedSourcePackagesDirPath /tmp/hush-spm \
  -only-testing:"HushTests/SSEParserTests/multilineDataPayload"
```

## 仓库结构

```text
Hush/                     # 应用主代码
  HushApp.swift           # @main 入口
  AppContainer.swift      # 根状态容器与 DI 组合根
  RequestCoordinator.swift# 多会话请求生命周期与调度
  HushCore/               # 纯领域模型、调度器、运行时常量
  HushNetworking/         # HTTPClient 与 SSEParser
  HushProviders/          # Provider 协议、OpenAI-compatible 实现、目录刷新
  HushRendering/          # 两阶段富渲染、缓存、调度
  HushSettings/           # JSON settings store
  HushStorage/            # GRDB repositories、migrations、附件存储、持久化协调
  HushTheme/              # 主题色板、字体、间距
  Views/                  # SwiftUI / AppKit 混合视图层
HushTests/                # Swift Testing 测试套件
Config/                   # 版本配置
scripts/                  # watch、崩溃采集、xctrace 等工程脚本
doc/                      # 工程文档与渲染深潜
openspec/                 # spec-driven 设计与变更记录
```

补充说明：

- 实际生产代码以 `Hush/` 目录为准。
- 根目录 `HushCore/` 当前只保留历史文件 `PerfTrace.swift`，不要把它误当成主模块目录。
- 子目录里存在多份模块级 `AGENTS.md`，适合在进入局部模块前先读一遍。

## 架构速览

### 请求与状态

- `AppContainer` 是 `@MainActor` 根容器，负责 bootstrap、消息分桶、设置持久化、侧边栏线程和热场景协调。
- `RequestCoordinator` 管理运行中请求、队列状态、流式 flush、图片生成链路、调试信息和队列推进。
- `RequestScheduler` 是纯函数调度器，核心状态为 `SchedulerState`。

### Provider 与模型

- `LLMProvider` 定义 `availableModels`、`send`、`sendStreaming`。
- 当前内置实现是 `OpenAIProvider`，DEBUG 下保留 `MockProvider`。
- `CatalogRefreshService` 将 provider 模型发现结果落到 SQLite 缓存。

### 渲染与切换

- 聊天区固定走 AppKit 单路径，不再在 SwiftUI / AppKit 间运行时切换。
- `RenderController` + `ConversationRenderScheduler` 负责流式 coalescing、优先级和离屏/空闲调度。
- `RenderCache` / `MathRenderCache` 与 `HotScenePool` 一起承担性能热路径。

### 存储

- `DatabaseManager` 当前迁移已到 `v15`，覆盖 provider 配置、agent presets、prompt templates、归档、附件与 debug info。
- provider API key 已持久化到 `providerConfigurations` 表；通用 JSON 编解码默认不携带 `apiKey`。
- 图片等附件由 `FileMessageAssetStore` 物化到本地文件，再写回消息附件元数据。

## 发布

```bash
make version
make release
ls build/release
```

发布逻辑当前有这些约束：

- 版本号统一维护在 `Config/Versions.xcconfig`。
- `make release` 会构建 `arm64 x86_64` 双架构 Release app，生成 ad-hoc 签名 `.app`，并关闭 `App Sandbox` 以提升跨机器可打开性。
- DMG 文件名格式为 `Hush-<marketing>-<build>.dmg`。
- 如需“下载即打开”体验，仍需要 Developer ID 签名 + notarization。

### GitHub Actions 自动发布

仓库包含 [`.github/workflows/release-dmg.yml`](/Users/lxp/Library/CloudStorage/Dropbox/code-space/mygitspace/Hush/.github/workflows/release-dmg.yml)：

- push 到 `main` 时：
  - 运行 `make test`
  - 运行 `make release`
  - 上传 workflow artifact
  - 更新滚动预发布标签 `main-latest`
- push 任意 tag 时：
  - 运行 `make test`
  - 运行 `make release`
  - 创建或更新对应 tag 的 GitHub release
  - 上传当前 DMG 作为 release asset

## 依赖

- [GRDB.swift](https://github.com/groue/GRDB.swift) `7.0.0+`
- [swift-markdown](https://github.com/swiftlang/swift-markdown) `0.4.0+`
- [SwiftMath](https://github.com/mgriebling/SwiftMath) `1.0.0+`
- Homebrew tools: `swiftformat`、`swiftlint`、`fswatch`

## 进一步阅读

- [AGENTS.md](/Users/lxp/Library/CloudStorage/Dropbox/code-space/mygitspace/Hush/AGENTS.md)
- [doc/README.md](/Users/lxp/Library/CloudStorage/Dropbox/code-space/mygitspace/Hush/doc/README.md)
- [doc/chat-rendering/README.md](/Users/lxp/Library/CloudStorage/Dropbox/code-space/mygitspace/Hush/doc/chat-rendering/README.md)
