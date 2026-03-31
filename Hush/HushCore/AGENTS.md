# HushCore

Pure domain models and deterministic scheduling logic. No I/O, no side effects, no framework dependencies beyond Foundation.

## Structure

```
AgentPreset.swift          # Saved agent configurations (system prompt, model, temperature)
AppSettings.swift          # App-level preference model (QuickBarConfiguration nested)
ChatMessage.swift          # Core message model (id, role, content, conversationId, timestamps, imageAssetIds)
ChatWindowing.swift        # Windowed message loading for large conversations
ConversationSidebarThread.swift # Sidebar display model (title, preview, timestamp, activity state)
ModelDescriptor.swift      # Provider model metadata (id, name, capabilities)
ModelParameters.swift      # Temperature, topP, maxTokens, reasoning effort
PromptTemplate.swift       # Reusable prompt templates
ProviderConfiguration.swift# Provider endpoint + model + credential ref
QuickBarSessionState.swift # Quick Bar ephemeral conversation state (messages, draft, expansion)
RequestLifecycle.swift     # RequestID, StreamEvent, RequestError, ActiveRequestState, QueueItemSnapshot
RequestScheduler.swift     # Pure-function enum: selectNext, enqueue, rebalanceForActiveSwitch, canAcceptSubmission
RuntimeConstants.swift     # enum namespace with static lets for all magic numbers
SettingsDTOs.swift         # Data Transfer Objects for settings UI (OpenAISettingsSnapshot, DataStats, etc.)
TailFollowStateMachine.swift # Auto-scroll state machine (events: newContent, userScroll, conversationSwitched)
```

## Where to Look

| Task | File |
|------|------|
| Change scheduling behavior | `RequestScheduler.swift` — static methods on `SchedulerState` |
| Add new error case | `RequestLifecycle.swift` -> `RequestError` enum |
| Tune timeouts/limits | `RuntimeConstants.swift` — all magic numbers centralized here |
| Add message field | `ChatMessage.swift` — also update `MessageRecord` in HushStorage |
| Add conversation field | `Conversation` in `ConversationSidebarThread.swift` — also update `ConversationRecord` in HushStorage |
| Quick Bar state | `QuickBarSessionState.swift` — ephemeral session model |
| Tail-follow behavior | `TailFollowStateMachine.swift` — event-driven state transitions |
| Quick Bar shortcut config | `AppSettings.swift` -> `QuickBarConfiguration` |
| Settings UI Data Models | `SettingsDTOs.swift` — snapshots and input models for settings views |

## Conventions

- **Pure value types**: All models are `struct` with `Sendable`, `Equatable`, `Codable`.
- **RequestScheduler is a pure-function enum**: No state mutation — takes `SchedulerState`, returns new state. Static methods only.
- **SchedulerState**: `runningSessions`, `activeQueue`, `backgroundQueues`, `roundRobinCursor`. Deterministic for testing.
- **RuntimeConstants**: `enum` namespace (no cases) with `static let`. All tunables live here:
  - `pendingQueueCapacity = 5`
  - `defaultMaxConcurrentRequests = 3`
  - `agedThresholdSeconds = 15`, `agedQuotaInterval = 3`
  - `preflightTimeoutSeconds = 3.0`, `generationTimeoutSeconds = 60.0`
  - `settingsDebounceInterval = 1s`
- **RequestError taxonomy**: Rich typed errors — `networkFailure`, `providerError`, `timeout`, `cancelled`, `invalidConfiguration`, etc. All conform to `Error + Sendable + Equatable + LocalizedError`.
- **TailFollowStateMachine**: Event-driven with `.following`, `.detached`, `.locked` states. Consumed by `MessageTableView`.

## Anti-Patterns

- **Never add I/O to this module** — no networking, no disk, no Keychain. Pure domain only.
- **Never mutate SchedulerState in-place** — always return new state from static methods.
- **Never hardcode magic numbers** — put them in `RuntimeConstants`.
- **Never add framework imports** — Foundation only. No SwiftUI, GRDB, or AppKit.
