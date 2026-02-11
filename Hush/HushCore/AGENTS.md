# HushCore

Pure domain models and deterministic scheduling logic. No I/O, no side effects, no framework dependencies beyond Foundation.

## Structure

```
ChatMessage.swift          # Core message model (id, role, content, conversationId, timestamps)
ChatRole.swift             # enum: system, user, assistant
Conversation.swift         # Conversation model (id, title, timestamps, provider/model config)
RequestLifecycle.swift     # RequestID, StreamEvent, RequestError, ActiveRequestState, QueueItemSnapshot
RequestScheduler.swift     # Pure-function enum: selectNext, enqueue, rebalanceForActiveSwitch, canAcceptSubmission
RuntimeConstants.swift     # enum namespace with static lets for all magic numbers
ProviderConfiguration.swift# Provider endpoint + model + credential ref
AgentPreset.swift          # Saved agent configurations
PromptTemplate.swift       # Reusable prompt templates
```

## Where to Look

| Task | File |
|------|------|
| Change scheduling behavior | `RequestScheduler.swift` — static methods on `SchedulerState` |
| Add new error case | `RequestLifecycle.swift` → `RequestError` enum |
| Tune timeouts/limits | `RuntimeConstants.swift` — all magic numbers centralized here |
| Add message field | `ChatMessage.swift` — also update `MessageRecord` in HushStorage |
| Add conversation field | `Conversation.swift` — also update `ConversationRecord` in HushStorage |

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

## Anti-Patterns

- **Never add I/O to this module** — no networking, no disk, no Keychain. Pure domain only.
- **Never mutate SchedulerState in-place** — always return new state from static methods.
- **Never hardcode magic numbers** — put them in `RuntimeConstants`.
- **Never add framework imports** — Foundation only. No SwiftUI, GRDB, or AppKit.
