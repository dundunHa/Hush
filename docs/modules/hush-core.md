# HushCore Module

> Pure domain models. No UI, no I/O. Zero dependencies.

## Purpose

HushCore defines the shared vocabulary for the entire Hush application. All other modules depend on it. It contains value types, enums, and protocols that model the chat domain, provider configuration, request lifecycle, and runtime defaults.

## Dependencies

None.

## Public Types

### Chat Domain

| Type | Kind | File | Description |
|------|------|------|-------------|
| `ChatRole` | enum | `ChatMessage.swift` | `.system`, `.user`, `.assistant`, `.tool` |
| `ChatMessage` | struct | `ChatMessage.swift` | Identifiable, Codable message with role, content, timestamp |

### Provider Configuration

| Type | Kind | File | Description |
|------|------|------|-------------|
| `ProviderType` | enum | `ProviderConfiguration.swift` | `.mock`, `.openAI`, `.anthropic`, `.ollama`, `.custom` |
| `ProviderConfiguration` | struct | `ProviderConfiguration.swift` | Provider endpoint, API key env var, enabled state |
| `ModelDescriptor` | struct | `ModelDescriptor.swift` | Model ID, display name, capabilities |
| `ModelCapability` | enum | `ModelDescriptor.swift` | `.text`, `.image` |
| `ModelParameters` | struct | `ModelParameters.swift` | Temperature, topP, maxTokens, penalties |

### App Settings

| Type | Kind | File | Description |
|------|------|------|-------------|
| `AppSettings` | struct | `AppSettings.swift` | Top-level settings: providers, selected IDs, parameters, quick bar |
| `QuickBarConfiguration` | struct | `AppSettings.swift` | Keyboard shortcut key + modifiers |

### Request Lifecycle

| Type | Kind | File | Description |
|------|------|------|-------------|
| `RequestID` | struct | `RequestLifecycle.swift` | UUID-based request correlation identity |
| `StreamEvent` | enum | `RequestLifecycle.swift` | `.started`, `.delta`, `.completed`, `.failed` — each carries `RequestID` |
| `RequestError` | enum | `RequestLifecycle.swift` | Error taxonomy: provider missing/disabled/unregistered, model invalid, timeouts, remote error, queue full, cancelled |
| `ActiveRequestState` | struct | `RequestLifecycle.swift` | Tracks request status, accumulated text, assistant message ID |
| `ActiveRequestStatus` | enum | `RequestLifecycle.swift` | `.preflight`, `.streaming`, `.completed`, `.failed`, `.stopped` |
| `QueueItemSnapshot` | struct | `RequestLifecycle.swift` | Immutable snapshot of prompt + provider/model/parameters at submission time |

### Runtime Constants

| Type | Kind | File | Description |
|------|------|------|-------------|
| `RuntimeConstants` | enum | `RuntimeConstants.swift` | Centralized defaults: queue capacity (5), preflight timeout (3s), generation timeout (60s), debounce interval (1s) |

## Conventions

- All types conform to `Sendable` (Swift 6 strict concurrency).
- Persisted types conform to `Codable, Equatable, Sendable`.
- UI-list types conform to `Identifiable`.
- Enums conform to `String, Codable, CaseIterable, Sendable`.
- All public API has explicit `public init`.

## Test Coverage

Tests in `Tests/HushCoreTests/DomainModelTests.swift` cover:
- `RequestID` uniqueness, hashing, codable round-trip
- `ActiveRequestState` terminal state classification
- `QueueItemSnapshot` field capture and equality
- `StreamEvent` equality semantics
- `RequestError` localized descriptions for all cases
- `RuntimeConstants` default value verification
- `ChatMessage` codable round-trip and role coverage
