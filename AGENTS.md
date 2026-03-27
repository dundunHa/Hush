# PROJECT KNOWLEDGE BASE

**Generated:** 2026-03-28 (Asia/Shanghai)
**Commit:** a4f99a2
**Branch:** dev

# AGENTS.md — Hush

macOS-native LLM chat client built with SwiftUI + Xcode. Dark-themed, single-window app with sidebar, multi-conversation concurrent streaming, multi-provider support, and system-wide Quick Bar.

## Hierarchy

- `./AGENTS.md` (global rules + architecture map)
- `Hush/HushCore/AGENTS.md` (pure domain + scheduler invariants)
- `Hush/HushProviders/AGENTS.md` (provider protocol + streaming terminal contract)
- `Hush/HushRendering/AGENTS.md` (two-phase rendering + cache/scheduler constraints)
- `Hush/HushStorage/AGENTS.md` (GRDB repositories + migrations + credential persistence)
- `Hush/Views/AGENTS.md` (UI conventions + view-layer constraints)
- `Hush/Views/Chat/AppKit/AGENTS.md` (hot-scene pool + table view lifecycle)
- `HushTests/AGENTS.md` (Swift Testing conventions + test isolation)

## Build & Run

```bash
make setup       # Install tools (swiftformat, swiftlint, fswatch) + resolve SPM deps
make build       # Debug build via xcodebuild
make test        # Run ALL unit tests
make fmt         # Format with SwiftFormat, then lint with SwiftLint
make run         # Launch the built .app
make dev         # Watch mode: rebuild + relaunch on file changes
make clean       # Remove .build/ and build/
make version     # Show MARKETING_VERSION + CURRENT_PROJECT_VERSION
make release     # Ad-hoc signed .app + DMG
```

### Running a Single Test

```bash
# Single test class:
xcodebuild test \
  -project Hush.xcodeproj -scheme Hush -configuration Debug \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -only-testing:"HushTests/SSEParserTests"

# Single test method:
xcodebuild test \
  -project Hush.xcodeproj -scheme Hush -configuration Debug \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -only-testing:"HushTests/SSEParserTests/multilineDataPayload"
```

### Dependencies

- **GRDB** 7.0+ — SQLite via DatabasePool (WAL mode).
- **Markdown** 0.4+ — Swift Markdown parsing (AST -> NSAttributedString).
- **SwiftMath** 1.0+ — LaTeX math rendering.
- **Homebrew tools**: swiftformat, swiftlint, fswatch (installed via `make setup` / `Brewfile`).

## Architecture

```
Hush/
  HushApp.swift              # @main entry, WindowGroup + Quick Bar bootstrap
  HushAppDelegate.swift      # NSApplicationDelegate, status bar + Quick Bar panel lifecycle
  AppContainer.swift         # Root ObservableObject (DI container, @MainActor, 2833 lines)
  RequestCoordinator.swift   # Multi-conversation concurrent request lifecycle & scheduling
  QuickBarPanelController.swift  # Floating NSPanel for system-wide Quick Bar
  QuickBarHotkeyController.swift # Global hotkey registration (Carbon HIToolbox)
  StatusBarController.swift  # Menu bar status item
  HushCore/                  # Domain models: ChatMessage, RequestLifecycle, RequestScheduler, RuntimeConstants, QuickBarSessionState, etc.
  HushNetworking/            # HTTPClient protocol + URLSession impl, SSEParser
  HushProviders/             # LLMProvider protocol + OpenAI (chat + image gen), Mock impls, ProviderRegistry
  HushRendering/             # Two-phase markdown render pipeline, math/table rendering, row height cache
  HushSettings/              # JSONSettingsStore (file-based JSON persistence)
  HushStorage/               # GRDB repositories, DatabaseManager, credential persistence, FileMessageAssetStore
  HushTheme/                 # HushColors, HushSpacing, HushTypography, ConversationSurfaceStyle, HushFontResolver
  Views/                     # SwiftUI views (Chat/, Sidebar/, TopBar/, Settings/, QuickBar/)
HushTests/                   # Swift Testing framework (@Suite, @Test, #expect) — 77 test files
openspec/                    # Spec-driven design docs (proposals, specs, tasks)
```

### Key Patterns

- **AppContainer**: Central `@MainActor final class ObservableObject`. Bootstrap via `AppContainer.bootstrap()`. Testing via `AppContainer.forTesting(...)`.
- **RequestCoordinator**: Owns multi-conversation stream lifecycle. `@MainActor`, holds `unowned let container`. Uses `RequestScheduler` for deterministic scheduling with global concurrency limit `N` (default 3), per-conversation running limit 1, active-priority + round-robin + aged-quota fairness.
- **RequestScheduler**: Pure-function scheduling logic. `SchedulerState` holds running sessions, active/background queues, round-robin cursor. Static methods: `selectNext`, `enqueue`, `rebalanceForActiveSwitch`, `canAcceptSubmission`.
- **Message Buckets**: `AppContainer.messagesByConversationId` stores per-conversation message arrays; `messages` is the active conversation projection. All request deltas route by owning `conversationId`, never by `activeConversationId`.
- **Protocol-driven storage**: `ConversationRepository`, `MessageRepository`, `SyncOutboxRepository` protocols with GRDB implementations (`GRDB*Repository`).
- **Credential flow**: Provider API keys persist in `providerConfigurations` SQLite table. Generic JSON settings encoding omits `apiKey`; `CredentialResolver` validates/normalizes at request time.
- **Two-phase init**: AppContainer creates itself, then calls `configureCoordinator()` to resolve the circular `RequestCoordinator <-> AppContainer` dependency.
- **Quick Bar**: System-wide floating panel (`QuickBarPanelController`) with global hotkey (`QuickBarHotkeyController`). Manages its own `QuickBarSessionState` for ephemeral conversations. Status bar via `StatusBarController`.
- **Image generation**: `OpenAIProvider` supports DALL-E image generation via `sendImageGeneration()`. Generated images stored via `FileMessageAssetStore`.

## Code Style

### Formatting (enforced)

- **SwiftFormat** config (`.swiftformat`): 4-space indent, LF line breaks, always trim whitespace, inline commas.
- **SwiftLint** config (`.swiftlint.yml`): Line length warning 140 / error 180. Function body warning 80 / error 120. File length warning 600 / error 900.
- Run `make fmt` before committing. Both tools must pass clean.

### Naming

- Types: `UpperCamelCase` — `ChatMessage`, `RequestCoordinator`, `ProviderConfiguration`.
- Properties/methods: `lowerCamelCase` — `activeRequest`, `sendDraft()`, `fetchMostRecent()`.
- Enums: `UpperCamelCase` type, `lowerCamelCase` cases — `enum ChatRole { case system, user, assistant }`.
- Constants: `static let lowerCamelCase` in an `enum` namespace — `enum RuntimeConstants { static let pendingQueueCapacity = 5 }`.
- Acronyms: natural casing in the middle of words — `providerID`, `modelID`, `requestID`, `userMessageID`.
- Test files: `<Module>Tests.swift`. No `Test` prefix on the struct.

### Imports

- Sorted (enforced by `sorted_imports` SwiftLint rule).
- `@testable import Hush` for test files. `import Testing` for the test framework.
- System frameworks first (`Foundation`, `SwiftUI`, `Security`), then third-party (`GRDB`), then `@testable`.

### Types & Concurrency

- Domain models: `struct` with `Sendable`, `Equatable`, `Codable` as needed. Prefer value types.
- Mutable state holders: `final class` with `@MainActor` — e.g. `AppContainer`, `RequestCoordinator`.
- Protocols: suffix with capability noun — `LLMProvider`, `HTTPClient`, `ConversationRepository`.
- Mark all public types and protocols `Sendable`. Use `nonisolated` explicitly when crossing actor boundaries.
- Use `any Protocol` for existential types (e.g. `private let httpClient: any HTTPClient`).
- Use Swift concurrency throughout: `async/await`, `Task`, `AsyncThrowingStream`. No Combine for new code except `@Published`.

### MARK Comments

Use `// MARK: -` sections consistently to organize files:
```swift
// MARK: - Dependencies
// MARK: - Init
// MARK: - Public Interface
// MARK: - Private
```

### Error Handling

- Define domain-specific error enums — `RequestError`, `HTTPError`, `CredentialResolutionError`.
- Conform errors to `Error`, `Sendable`, `Equatable`. Add `LocalizedError` with `errorDescription`.
- Use typed catch clauses: `catch let error as RequestError { ... }`.
- Non-critical persistence failures: `try?` with no swallowed context (acceptable for streaming flushes).
- Critical failures: propagate with `throws`. Never use `fatalError()` or `try!` in production code.

### Views

- SwiftUI views are plain `struct View`. Use `@EnvironmentObject` for `AppContainer`.
- Theme constants from `HushColors`, `HushSpacing`, `HushTypography` — never hardcode colors/spacing.
- Dark mode only (single `AppTheme.dark` case). Custom color palette, not system colors.
- `ConversationSurfaceStyle` controls per-surface rendering (main window vs Quick Bar).

### Testing

- Framework: **Swift Testing** (`import Testing`), NOT XCTest.
- Annotations: `@Suite("Description")` on struct, `@Test("Description")` on methods.
- Assertions: `#expect(...)`, `#expect(throws:)`. NOT `XCTAssert*`.
- Test setup: factory methods like `makeRepo()` or `makeClient()` returning tuples — no `setUp()`/`tearDown()`.
- Database tests: use `DatabaseManager.inMemory()` for isolated, disposable databases.
- DI for tests: `AppContainer.forTesting(...)` with injectable dependencies.
- Use `StubURLProtocol` pattern for HTTP tests. Mark serialized suites with `.serialized`.

## Versioning

- Version truth source: `Config/Versions.xcconfig` — `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION`.
- CI: `.github/workflows/release-dmg.yml` — builds DMG on push to master/tag, runs tests, uploads artifacts.

## Spec-Driven Development

This project uses **openspec** for feature planning. Specs live in `openspec/specs/` and changes in `openspec/changes/`. Agent tooling is in `.claude/`, `.cursor/`, `.codex/`, `.factory/` directories (commands + skills for openspec workflows). Read the relevant spec before implementing a feature.
