# AGENTS.md — Hush

> Native macOS 14+ LLM chat client. SwiftUI + Swift 6 strict concurrency.
> Current phase: **init foundation** (app shell, domain models, provider abstraction, JSON settings).

## SSOT

`docs/specs/init-spec.md` is the single source of truth for scope and acceptance criteria.
Update the spec **before** changing code when scope shifts.

## Build & Test

```bash
# Full test suite (from repo root)
swift test

# Build only (no tests)
swift build

# Run a single test class
swift test --filter HushCoreTests.SettingsStoreTests

# Run a single test method
swift test --filter HushCoreTests.SettingsStoreTests/testSaveAndLoadRoundTrip

# If SwiftPM cache issues occur in sandboxed environments:
mkdir -p .cache/clang .cache/swiftpm
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" \
SWIFTPM_CUSTOM_LIBCACHE_PATH="$PWD/.cache/swiftpm" \
swift test
```

No external linter or formatter is configured. No `.swiftlint.yml`, `.swiftformat`, or `.editorconfig` exists.
Rely on the conventions documented below and match existing code style.

## Project Structure

```
Sources/
  HushApp/              # SwiftUI app shell, state container, views
    HushApp.swift       # @main entry point
    AppContainer.swift  # @MainActor ObservableObject — app state + send pipeline
    Views/
      RootView.swift    # NavigationSplitView layout (sidebar + chat + quick bar sheet)
      QuickBarView.swift
  HushCore/             # Pure domain models (no UI, no I/O)
    ChatMessage.swift
    ModelDescriptor.swift
    ModelParameters.swift
    ProviderConfiguration.swift
    AppSettings.swift
  HushProviders/        # Provider protocol, registry, mock implementation
    LLMProvider.swift   # protocol LLMProvider: Sendable
    ProviderRegistry.swift
    MockProvider.swift
  HushSettings/         # JSON persistence layer
    JSONSettingsStore.swift
Tests/
  HushCoreTests/        # All tests live here for now
    SettingsStoreTests.swift
    ProviderRegistryTests.swift
```

### Module Dependency Graph

```
HushApp → HushCore, HushProviders, HushSettings
HushProviders → HushCore
HushSettings → HushCore
HushCore → (none)
```

**Do not introduce cross-dependencies that violate this graph.**

## Code Style

### Swift Version & Concurrency

- Swift tools version: **6.0**. Strict concurrency is enabled by default.
- All domain models conform to `Sendable`.
- `AppContainer` is `@MainActor final class: ObservableObject`.
- Provider protocol requires `Sendable`: `protocol LLMProvider: Sendable`.
- Use `async/await` for asynchronous work. No Combine, no callbacks.

### Formatting

- **Indent**: 4 spaces (no tabs).
- **Line length**: ~120 chars soft limit (inferred from existing code).
- **Trailing newline**: Every file ends with a single blank line after the last declaration.
- **Braces**: Opening brace on same line. Closing brace on its own line.
- **Commas**: Trailing commas are NOT used in parameter lists or array literals.

### Imports

- `Foundation` first, then system frameworks (`SwiftUI`), then internal modules (`HushCore`, `HushProviders`, `HushSettings`).
- One import per line. No `@_exported`.
- Tests use `@testable import` for internal modules.

### Naming

- **Types**: `UpperCamelCase` — `ChatMessage`, `ProviderRegistry`, `ModelParameters`.
- **Properties/methods**: `lowerCamelCase` — `selectedProviderID`, `availableModels()`.
- **Enum cases**: `lowerCamelCase` — `.user`, `.openAI`, `.mock`.
- **Acronyms**: Uppercase when standalone (`ID`, `URL`), mixed in compounds (`selectedProviderID`, `fileURL`).
- **Static defaults**: `.default`, `.standard`, `.mockDefault()` — use descriptive factory names.

### Types & Protocols

- Domain models are `struct` with explicit `public init`.
- Conform to `Codable, Equatable, Sendable` for all persisted models.
- Conform to `Identifiable` when used in SwiftUI lists.
- Enums conform to `String, Codable, CaseIterable, Sendable`.
- Use `any LLMProvider` (existential) when storing heterogeneous providers.
- Protocols are minimal — only the methods actually needed.

### Error Handling

- Use `throws` / `try` for recoverable errors (file I/O, encoding).
- Use `do { ... } catch { ... }` — never leave catch blocks empty.
- On failure in UI-facing code, set `statusMessage` with a human-readable error.
- Provider errors produce a fallback `ChatMessage(role: .assistant, ...)` so the conversation stays intact.

### SwiftUI Patterns

- State container: single `@StateObject` `AppContainer` injected via `.environmentObject`.
- Views access container through `@EnvironmentObject private var container: AppContainer`.
- File-private sub-views (`private struct`) for components only used in one file.
- `@ViewBuilder` helper methods for reusable card/row patterns.
- Use `some View` return types, not `AnyView`.

### Access Control

- `HushCore`, `HushProviders`, `HushSettings`: all public API is explicitly `public`.
- `HushApp`: internal by default (app target, not imported elsewhere).
- Private helpers use `private` (not `fileprivate` unless needed by extensions in same file).

### Testing

- Test target: `HushCoreTests`. Tests import `@testable import HushCore` (and other modules as needed).
- Test class naming: `<Feature>Tests: XCTestCase`.
- Test method naming: `test<Behavior>` — e.g., `testSaveAndLoadRoundTrip`, `testRegisterAndLookupProvider`.
- Use temp directories for file I/O tests with `defer { cleanup }`.
- Async tests use `async throws` signature.

## Architecture Invariants

1. **Send pipeline is shared**: Quick bar and main chat both flow through `quickBarSubmit → sendDraft → processAssistantReply`. Do not create separate paths.
2. **Settings persist on mutation**: `AppContainer.settings.didSet` triggers `persistSettingsIfNeeded`. This is intentional.
3. **Provider fallback**: If `selectedProviderID` doesn't match a registered provider, fall back to `firstProvider()`. Always preserve this.
4. **Module boundaries**: Domain models live in `HushCore`. Provider logic in `HushProviders`. Persistence in `HushSettings`. UI in `HushApp`. Don't leak responsibilities.

## Init Phase Boundaries

### In Scope

- Package structure, module boundaries, core models.
- `LLMProvider` protocol + `ProviderRegistry` + `MockProvider`.
- JSON settings persistence with roundtrip tests.
- SwiftUI shell (sidebar, chat workspace, quick bar placeholder).

### Out of Scope (defer to future milestones)

- Real API provider implementations (OpenAI, Anthropic, Ollama).
- Keychain / secure secret storage.
- System-global hotkey capture.
- Streaming token rendering.
- Multi-window orchestration.
- Rust FFI integration.

## Foot-Guns

- SwiftPM cache can fail in sandboxed environments — use the cache env vars shown above.
- `selectedProviderID` can become stale after provider removal — always check existence.
- Swift 6 strict concurrency: all types crossing actor boundaries must be `Sendable`.
- No `.swiftlint.yml` exists — do not add one without explicit request.
