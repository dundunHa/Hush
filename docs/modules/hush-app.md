# HushApp Module

> SwiftUI app shell, state container, and views.

## Purpose

HushApp is the executable target that wires together all modules into a running macOS application. It contains the `AppContainer` state machine, SwiftUI views, and lifecycle management.

## Dependencies

- `HushCore` — domain models, request lifecycle types, runtime constants
- `HushProviders` — `LLMProvider` protocol, `ProviderRegistry`, `MockProvider`
- `HushSettings` — `JSONSettingsStore`
- `SwiftUI` — UI framework

## Key Types

### AppContainer

`@MainActor final class AppContainer: ObservableObject`

The central state container and request execution engine. All UI state flows through it.

#### Published State

| Property | Type | Description |
|----------|------|-------------|
| `settings` | `AppSettings` | Current app configuration (triggers debounced persistence on change) |
| `messages` | `[ChatMessage]` | Full conversation transcript |
| `draft` | `String` | Current text input |
| `statusMessage` | `String` | User-visible status feedback |
| `activeRequest` | `ActiveRequestState?` | Currently executing request (nil when idle) |
| `pendingQueue` | `[QueueItemSnapshot]` | FIFO queue of pending requests (max 5) |

#### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| `isSending` | `Bool` | `activeRequest != nil` |
| `isQueueFull` | `Bool` | `pendingQueue.count >= 5` |

#### Send Pipeline

```
sendDraft() / quickBarSubmit(_:)
  ├─ Queue full? → Atomic rejection (no side effects)
  ├─ No active request? → startRequest(snapshot)
  └─ Active request? → pendingQueue.append(snapshot)

startRequest(snapshot)
  └─ Task { executeRequest(snapshot) }

executeRequest(snapshot)
  ├─ Strict provider resolution (missing/disabled/unregistered → fail)
  ├─ Preflight model validation with timeout (invalid/timeout → fail)
  └─ consumeStream(stream, requestID, providerID)
       ├─ Generation timeout watcher (parallel task)
       ├─ .delta → handleDelta (incremental message assembly)
       ├─ .completed → completeActiveRequest → advanceQueue
       └─ .failed → failActiveRequest → advanceQueue
```

#### Stop Semantics

- `stopActiveRequest()` cancels the active stream task, preserves pending queue, auto-advances to next.
- Stop without active request is a no-op with status feedback.
- Stale events are ignored via `requestID` correlation checks.

#### Settings Persistence

- `persistSettingsIfNeeded` → `scheduleDebouncedSave()` (1s trailing debounce)
- `flushSettings()` → immediate save, cancels pending debounce
- Failures keep `isDirty = true` for retry

### Views

| File | Description |
|------|-------------|
| `RootView.swift` | `NavigationSplitView` with settings sidebar + chat workspace + quick bar sheet |
| `QuickBarView.swift` | Modal prompt launcher that delegates to `quickBarSubmit(_:)` |

#### UI State Wiring

- Send button disabled when `isSending && isQueueFull`
- Stop button appears when `isSending`
- Queue count indicator shown during active generation
- Streaming assistant message updates in real-time via `handleDelta`

### HushApp Entry Point

`@main struct HushApp: App` — creates `AppContainer.bootstrap()` as `@StateObject`, wires lifecycle flush via `scenePhase` observation.

## Test Coverage

Tests in `Tests/HushCoreTests/`:
- `RequestLifecycleTests.swift` — single active stream, FIFO queue, snapshot integrity, queue-full rejection, stop/cancel, strict provider resolution, preflight validation, generation timeout, remote error transparency, partial output preservation
- `DebouncedPersistenceTests.swift` — debounce coalescing, spaced writes, flush behavior
- `PersistenceFailureTests.swift` — failure visibility, dirty retry

Total: 84 tests, 0 failures.
