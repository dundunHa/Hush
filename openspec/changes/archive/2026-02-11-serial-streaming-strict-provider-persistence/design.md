## Context

Hush currently routes chat sends through `quickBarSubmit -> sendDraft -> processAssistantReply` and appends the user message before running a single async provider call. This achieves a minimal flow but does not define deterministic behavior for additional sends while a request is in flight, stop/cancel semantics, or incremental streaming updates. Provider selection currently allows fallback to another provider, which masks misconfiguration instead of surfacing explicit failure. Settings persistence currently writes immediately on each settings mutation, which can cause unnecessary I/O churn during frequent UI edits.

This change crosses `HushApp`, `HushProviders`, `HushCore`, and `HushSettings` and introduces behavioral contracts that must be testable before real provider integrations are added.

## Goals / Non-Goals

**Goals:**
- Define a single-runner request lifecycle with streaming-first semantics.
- Guarantee deterministic handling of user sends during an active request via a bounded FIFO queue.
- Define explicit stop/cancel behavior and state transitions.
- Enforce strict provider/model validation with no fallback behavior.
- Surface remote provider errors and timeouts transparently to the user.
- Replace write-through settings persistence with debounced persistence and explicit flush points.
- Establish complete tests for lifecycle, validation, error propagation, and persistence policy.

**Non-Goals:**
- Adding real OpenAI/Anthropic/Ollama provider implementations.
- Implementing global hotkey capture internals.
- Multi-window orchestration or long-term conversation storage redesign.
- UI redesign beyond controls needed to represent queue/stream/error states.

## Decisions

### 1) Request execution model: single active stream + pending queue

- Decision: Introduce a serialized request runner with at most one active remote stream at a time. Additional sends while busy are enqueued in a bounded FIFO queue with default max size `5`.
- Decision: Queue-full rejection is atomic. When pending queue is full, the new send is rejected with a visible queue-full error, and no user message or queue entry is appended.
- Rationale: Preserves user intent order and avoids race conditions in message patching.
- Alternatives considered:
  - Reject sends while busy (simpler, but degrades UX for rapid prompts).
  - Run multiple concurrent streams (higher throughput but complex state reconciliation).

### 2) Stop behavior and queue progression

- Decision: `stop` cancels only the currently active request and does not clear pending queue entries.
- Decision: After the active request transitions to a terminal stopped state, the next queued request auto-starts if one exists.
- Decision: Triggering `stop` when there is no active request is a no-op for message/queue state with a status update for user feedback.
- Rationale: Keeps stop semantics narrow and predictable while preserving FIFO request intent.
- Alternatives considered:
  - `stop` clears entire queue (highly destructive to already-captured intent).
  - `stop` pauses queue until explicit resume (adds control complexity not needed in init milestone).

### 3) Streaming provider contract

- Decision: Provider interaction becomes event-driven and cancellation-aware via stream events (`started`, `delta`, `completed`, `failed`).
- Decision: Each stream event carries request correlation identity so stale events can be ignored after cancellation/terminal transitions.
- Decision: Exactly one terminal event (`completed` or `failed`) is accepted per request.
- Rationale: Streaming is required for target UX and request ID correlation is required for race-free state updates.
- Alternatives considered:
  - Keep one-shot `send` only (insufficient for streaming and partial output).
  - Callback-based streaming (harder to reason about under Swift concurrency than async sequences).

### 4) Queue payload captures request snapshot at enqueue time

- Decision: Each queued entry stores normalized prompt + provider/model/parameter snapshot captured when the user submits.
- Decision: Dequeued execution uses the captured snapshot, not mutable live settings at dequeue time.
- Rationale: Deterministic execution that reflects what the user saw at submission time.
- Alternatives considered:
  - Resolve settings at dequeue time (more dynamic, but can silently change intent).

### 5) Strict provider/model validation with hard failure

- Decision: Remove fallback provider/model behavior. Validation failures and remote failures are terminal for that request and surfaced to UI.
- Decision: Provider resolution is strict and requires all of:
  - selected provider configuration exists in `AppSettings.providerConfigurations`
  - selected provider configuration is enabled
  - selected provider ID resolves to a registered runtime provider implementation
- Decision: Model validation runs before every generation attempt against the selected provider.
- Decision: Model validation uses a default preflight timeout of `3s` and fails the request on timeout.
- Rationale: Avoid hidden behavior and reduce debugging ambiguity while preserving deterministic failure semantics.
- Alternatives considered:
  - Fallback to first available provider/model (higher apparent resiliency but masks config errors).
  - Cache-only model validation (faster, but risks stale acceptance/rejection semantics).

### 6) Error and timeout transparency

- Decision: Represent queue-full, strict validation failures, remote failures, timeout failures, and stopped outcomes explicitly in user-visible status output.
- Decision: Generation timeout uses default budget `60s` per request and fails as timeout when exceeded.
- Decision: If stop/failure happens after partial assistant deltas, partial text remains in transcript; if no delta was received, append an explicit assistant failure/stopped message.
- Rationale: User asked for no silent downgrade and direct visibility into failure causes while keeping transcript continuity.
- Alternatives considered:
  - Generic "request failed" status only (simpler but insufficiently actionable).
  - Removing partial assistant output on stop/failure (hides already-delivered model output).

### 7) Settings persistence policy: trailing debounce + explicit flush

- Decision: Persist settings with a default 1-second trailing debounce and force flush at lifecycle boundaries (app background and inactive scene phase transitions).
- Decision: Flush immediately persists latest dirty snapshot and cancels pending debounce timer if one exists.
- Decision: Persistence failure keeps latest snapshot dirty for retry on next debounce cycle or flush trigger, and each failure is surfaced to user-visible status.
- Rationale: Reduces write amplification while keeping bounded durability lag and avoiding silent data loss on transient I/O errors.
- Alternatives considered:
  - Immediate write-through for every change (highest durability, worse stability/perf under typing).
  - Manual save only (high risk of accidental loss and extra UX friction).

## Risks / Trade-offs

- [Queue cap can reject bursty sends] -> Mitigate with visible queue-full feedback and clear retry guidance in UI status.
- [Stop/cancel race with late stream chunks] -> Mitigate with request IDs and ignoring stale events.
- [Snapshot-at-enqueue can run with older settings] -> Mitigate via explicit design contract and queue transparency in UI state.
- [Strict preflight adds latency] -> Mitigate with tight preflight timeout (3s) and optional local caching that does not alter failure semantics.
- [Debounce introduces short durability gap] -> Mitigate with 1-second default plus lifecycle flush on background/inactive scene phase transitions and retry-on-failure dirty tracking.

## Migration Plan

1. Introduce request lifecycle types (request ID, active state, queue item snapshot, stream event, error taxonomy) and tests.
2. Add streaming-compatible provider path (including cancellation support and deterministic mock stream behavior).
3. Migrate `AppContainer` send pipeline to single-runner + FIFO queue (max 5) + atomic queue-full rejection.
4. Implement explicit stop semantics (cancel active only, stale-event suppression, auto-advance pending queue).
5. Replace provider/model fallback with strict provider resolution and per-send model preflight validation (3s timeout).
6. Add generation timeout enforcement (60s default) and structured user-visible error/status mapping.
7. Introduce debounced settings persistence with lifecycle flush and retry-on-failure dirty tracking.
8. Expand test suite to cover serialization, queue semantics, cancellation, strict validation, timeout/error propagation, and persistence behavior.

Rollback strategy:
- If queue rejection rate is unacceptable, increase default queue capacity while preserving single-active invariant.
- If strict preflight timeout proves too aggressive, tune timeout values without reintroducing fallback behavior.
- If debounce behavior causes unacceptable data loss in practice, reduce debounce interval or temporarily restore immediate writes.

## Open Questions

- None for this change. Queue capacity, stop progression policy, and timeout budgets are fixed by this design.
