## Why

The current chat flow mixes optimistic message appends, non-streaming provider responses, and provider fallback behavior, which creates ambiguous runtime semantics when users send messages during an in-flight request. At the same time, settings persistence writes on every mutation, which is simple but not stable under frequent UI edits.

## What Changes

- Introduce a serialized chat execution pipeline with one active remote stream at a time.
- Add explicit stop/cancel semantics for the active stream. Stop cancels only the active request and queued requests continue in FIFO order.
- Define bounded queue behavior for additional user sends while busy, including an explicit default capacity of 5 pending requests.
- Define queue-full rejection as atomic: reject the submission with visible feedback and do not append user or queue records.
- Add streaming response handling so assistant messages are built incrementally from remote events.
- **BREAKING**: Remove provider/model fallback behavior. If the selected provider or model is invalid, fail fast and surface the error directly.
- Surface remote errors and timeout failures in a user-visible way without silent downgrade, with explicit default budgets (3s preflight validation, 60s generation).
- Replace per-mutation settings writes with debounced persistence (default 1 second), with explicit flush behavior at lifecycle boundaries.
- Add test coverage for serialization, queue/cancel behavior, strict provider/model validation, remote error propagation, and debounced persistence.

## Capabilities

### New Capabilities
- `serial-streaming-chat-execution`: Single-runner chat request lifecycle with streaming updates, stop control, and deterministic queue semantics.
- `strict-provider-and-model-selection`: Hard-fail validation for selected provider/model and transparent remote error/timeout reporting.
- `debounced-settings-persistence`: Stable settings persistence policy using debounce + explicit flush guarantees.

### Modified Capabilities
- None.

## Impact

- Affected modules: `HushApp`, `HushProviders`, `HushCore`, `HushSettings`.
- Affected runtime behavior: send pipeline, request lifecycle state machine, provider selection semantics, error handling semantics, and settings save cadence.
- Potential protocol impact: `LLMProvider` abstraction may need streaming-oriented APIs and cancellation support.
- Test impact: expand `Tests/HushCoreTests` to cover new lifecycle and persistence guarantees.
