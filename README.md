# Hush

<p align="center">
  <img src="Hush/Assets.xcassets/AppIcon.appiconset/appIcon_256x256@2x.png" width="128" alt="Hush logo" />
</p>

macOS 原生 LLM Chat 客户端.

## 为什么是 Hush

- **Swift 原生**
- **支持流式对话和多会话并发处理**
- **支持markdown和Latex格式渲染**
- **自定义provider**
- **本地优先,Sqlite存储数据在本地**

## 快速开发

命令：

```bash
make setup   # 安装 swiftformat / swiftlint / fswatch + resolve SPM
make build   # Debug build
make run     # 启动 .app 并 stream 日志
make test    # 跑单元测试（Swift Testing）
```

说明：
- 默认 `DerivedData` / SwiftPM 缓存现在写到 `/tmp/hush-dd` 和 `/tmp/hush-spm`，避免 Dropbox / File Provider 给测试产物附加扩展属性，导致 macOS codesign 失败。
- 如需自定义目录，可在命令前覆写，例如：`DERIVED_DATA=$PWD/.build/DerivedData SPM_DIR=$PWD/.build/SourcePackages make build`

## Release（DMG）

```bash
make release
ls build/release
```

说明：
- 本项目默认生成面向外部分发的 ad-hoc 签名 `.app`，并在 `make release` 时关闭 `App Sandbox`，以避免“本机可运行、别的 Mac 直接无法打开”的兼容性问题。
- 从互联网下载的 DMG 在 macOS 上仍可能被 Gatekeeper 标记为未验证应用；预期路径是用户可通过“右键打开”或“系统设置 → Privacy & Security → Open Anyway”继续。
- 若希望用户下载后直接正常打开、不出现风险提示，仍需要 Developer ID 签名 + notarization。

## 目录结构

```text
Hush/            # App + feature modules
HushCore/        # Domain models / scheduler logic
HushProviders/   # Provider 协议与实现
HushRendering/   # Markdown/LaTeX 渲染与缓存
HushStorage/     # GRDB repositories / migrations / keychain bridge
Views/           # SwiftUI + AppKit bridge views
HushTests/       # Swift Testing suites
openspec/        # Spec-driven workflow artifacts
doc/             # Engineering docs（架构/流程/排障）
```
