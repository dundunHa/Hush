## 1. Request Lifecycle Foundation

- [x] 1.1 Define request lifecycle domain types for request ID, active state, queue item snapshot, stream events, and error taxonomy.
- [x] 1.2 Extend the provider abstraction to support streaming events and request cancellation with request-correlation identity.
- [x] 1.3 Update `MockProvider` with deterministic streaming behavior for testability, including controllable delay/error paths.
- [x] 1.4 Define and centralize default runtime constants: pending queue capacity (5), preflight timeout (3s), generation timeout (60s), debounce interval (1s).

## 2. Serialized Runner in AppContainer

- [x] 2.1 Introduce single-active-request state and bounded FIFO pending queue in `AppContainer` (max 5 pending items).
- [x] 2.2 Capture prompt/provider/model/parameter snapshot at submission time and execute queued requests in order.
- [x] 2.3 Implement queue-full atomic rejection with visible status output and no user-message/queue append side effects.
- [x] 2.4 Implement explicit stop action that cancels active request, ignores stale events by request ID, and keeps pending queue intact.
- [x] 2.5 Auto-start next queued request after active request reaches completed, failed, or stopped terminal state.
- [x] 2.6 Treat stop-without-active-request as no-op for transcript/queue state with explicit status feedback.
- [x] 2.7 Update chat/quick-bar UI state wiring to reflect active, queued, stopped, and queue-full outcomes.

## 3. Strict Provider and Model Validation

- [x] 3.1 Remove provider fallback resolution and fail fast when selected provider is missing, disabled, or unregistered at runtime.
- [x] 3.2 Add preflight selected-model validation against the selected provider before generation starts (per send attempt).
- [x] 3.3 Enforce model preflight timeout (default 3s) and abort request on validation timeout.
- [x] 3.4 Enforce generation timeout (default 60s) and map timeout as a first-class request failure.
- [x] 3.5 Ensure preflight validation failure prevents generation from starting.
- [x] 3.6 Surface strict validation, timeout, and remote provider error details in user-visible status and assistant failure output.

## 4. Debounced Settings Persistence

- [x] 4.1 Replace immediate settings write-through with trailing debounce persistence (default 1 second).
- [x] 4.2 Add lifecycle flush hooks to force-save pending settings on configured app boundary events (background/inactive).
- [x] 4.3 Ensure lifecycle flush immediately persists latest dirty snapshot and cancels pending debounce timer.
- [x] 4.4 Preserve persistence failure visibility, keep dirty snapshot for retry, and ensure failed saves are not silently dropped.

## 5. Verification

- [x] 5.1 Add tests for single active stream enforcement and FIFO queue progression.
- [x] 5.2 Add tests for submission snapshot integrity (queued request uses captured provider/model/parameters).
- [x] 5.3 Add tests for queue-full atomic rejection behavior (no user-message/queue append).
- [x] 5.4 Add tests for stop/cancel behavior, stale-event suppression, and auto-advance of pending queue after stop.
- [x] 5.5 Add tests for strict provider resolution (missing/disabled/unregistered) with no fallback behavior.
- [x] 5.6 Add tests for preflight model validation timeout and no-generation-on-preflight-failure behavior.
- [x] 5.7 Add tests for generation timeout and remote error transparency.
- [x] 5.8 Add tests for debounced save coalescing, spaced writes, and lifecycle flush guarantees.
- [x] 5.9 Add tests for persistence failure visibility and retry-on-next-flush/debounce behavior.
- [x] 5.10 Run `swift test` and confirm all new behaviors are covered.
