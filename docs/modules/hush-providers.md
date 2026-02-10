# HushProviders Module

> Provider protocol, registry, and mock implementation.

## Purpose

HushProviders defines the abstraction layer between the app and LLM backends. It declares the `LLMProvider` protocol, provides a registry for runtime provider lookup, and includes a fully controllable `MockProvider` for testing.

## Dependencies

- `HushCore` — domain types (`ChatMessage`, `ModelDescriptor`, `ModelParameters`, `RequestID`, `StreamEvent`)

## Public Types

### Protocol

| Type | Kind | File | Description |
|------|------|------|-------------|
| `LLMProvider` | protocol | `LLMProvider.swift` | `Sendable` provider contract: `availableModels()`, `send(...)`, `sendStreaming(...)` |

#### LLMProvider Requirements

```swift
var id: String { get }
func availableModels() async throws -> [ModelDescriptor]
func send(messages:modelID:parameters:) async throws -> ChatMessage
func sendStreaming(messages:modelID:parameters:requestID:) -> AsyncThrowingStream<StreamEvent, Error>
```

- `send` — one-shot request/response (legacy path, retained for compatibility)
- `sendStreaming` — streaming generation with request-correlated events; must yield exactly one terminal event (`.completed` or `.failed`)

### Registry

| Type | Kind | File | Description |
|------|------|------|-------------|
| `ProviderRegistry` | struct | `ProviderRegistry.swift` | Thread-safe dictionary of `[String: any LLMProvider]` |

Methods: `register(_:)`, `provider(for:)`, `allProviderIDs()`, `firstProvider()`

### Mock

| Type | Kind | File | Description |
|------|------|------|-------------|
| `MockProvider` | struct | `MockProvider.swift` | Deterministic `LLMProvider` with configurable streaming behavior |
| `MockStreamBehavior` | struct | `MockProvider.swift` | Controls chunks, delay per chunk, failure point, failure error |

#### MockStreamBehavior Presets

- `.default` — 3 chunks ("Mock", " response", " streaming") at 50ms each
- `.failing(after:error:)` — fails after N chunks with specified error

## Architecture Notes

- `LLMProvider` requires `Sendable` so provider instances can be stored across actor boundaries.
- `sendStreaming` uses `AsyncThrowingStream` — the caller drives consumption and can cancel via task cancellation.
- The stream producer in `MockProvider` respects `Task.checkCancellation()` between chunks.
- `ProviderRegistry` uses value semantics (struct) — mutations require `mutating`.

## Test Coverage

Tests in `Tests/HushCoreTests/`:
- `ProviderRegistryTests.swift` — register, lookup, sorted IDs, first provider, empty registry, overwrite
- `MockProviderStreamTests.swift` — default streaming, failing behavior, zero-chunk failure, cancellation, available models, send response, custom chunks
