## Context

Hush already defines deterministic request execution: single active stream, bounded FIFO queue, strict provider/model preflight, explicit stop semantics, and explicit timeout failures. The runtime still only registers `MockProvider`, so the current architecture validates flow semantics but not real provider transport.

This change introduces a production transport path for OpenAI while preserving the existing request coordinator contract and persistence behavior. The transport must support:
- Bearer-authenticated HTTP requests
- JSON response parsing for model discovery
- SSE streaming for incremental generation

## Goals / Non-Goals

**Goals:**
- Add a reusable native HTTP client abstraction built on `URLSession`.
- Add SSE parsing and streaming support for OpenAI-style `data:` events with `[DONE]` terminal.
- Add `OpenAIProvider` implementation for `availableModels` and `sendStreaming`.
- Pass explicit invocation context (`endpoint`, `bearerToken`) from coordinator to providers.
- Preserve existing queue/full/stop/timeout semantics without behavior drift.
- Keep default app startup on `mock` provider unchanged.

**Non-Goals:**
- Adding Anthropic/Ollama runtime providers.
- Adding provider configuration UI in Settings.
- Adding automatic retry policies for generation streams.
- Introducing third-party HTTP frameworks.

## Decisions

### 1) Provider invocation context is explicit

- Decision: Add `ProviderInvocationContext` to provider API and require coordinator to construct it.
- Decision: Context includes `endpoint` and optional `bearerToken`.
- Rationale: Keeps credential resolution and endpoint policy in coordinator (existing strict-preflight authority) and prevents provider-side hidden coupling to settings/keychain.
- Alternatives considered:
  - Provider reads settings/keychain directly (harder to test, hidden dependency graph).
  - Global singleton networking context (implicit state, higher coupling).

### 2) Native URLSession transport (no third-party framework)

- Decision: Implement `HTTPClient` protocol + `URLSessionHTTPClient`.
- Decision: Support JSON request/response and SSE stream APIs in one client boundary.
- Rationale: Current requirements are narrow and fully covered by Foundation APIs; avoids unnecessary dependency surface.
- Alternatives considered:
  - Alamofire/Moya integration (extra dependency and abstraction cost with little immediate value).

### 3) SSE parsing model

- Decision: Implement line-based parser that supports SSE fields (`data`, `event`, `id`, `retry`) and emits event on blank line.
- Decision: Multi-line `data` fields are joined with newline.
- Decision: Unknown fields are ignored for forward compatibility.
- Rationale: Matches SSE spec and OpenAI `data-only` event format while retaining generic parsing utility.
- Alternatives considered:
  - Ad-hoc chunk string splitting by `\n\n` only (fragile with multi-line data and partial boundaries).

### 4) OpenAI provider behavior

- Decision: `availableModels` calls `{endpoint}/models` with bearer auth and maps `data[].id` to `ModelDescriptor`.
- Decision: `sendStreaming` calls `{endpoint}/chat/completions` with `stream=true`, `Accept: text/event-stream`.
- Decision: Stream event mapping:
  - `data: [DONE]` -> `StreamEvent.completed`
  - valid delta content -> `StreamEvent.delta`
  - transport/protocol decode failure -> `StreamEvent.failed(.remoteError(...))`
- Rationale: Aligns with current strict provider contract and incremental assembly semantics.
- Alternatives considered:
  - One-shot non-streaming response path first (does not satisfy existing stream-first execution model).

### 5) Endpoint and failure policy

- Decision: Endpoint policy is config-first with provider-type default fallback (OpenAI default base URL).
- Decision: OpenAI endpoint MUST be treated as an API base URL (recommended: `https://api.openai.com/v1`). Provider MUST construct request paths by appending `/models` and `/chat/completions`.
- Decision: If the configured endpoint includes an obviously-invalid OpenAI path suffix (e.g. `/chat/completions`), the system SHOULD fail fast with a clear error rather than guessing a normalized base URL.
- Decision: No auto-retry for stream generation.
- Rationale: Deterministic behavior and predictable transcript semantics; retries can duplicate output and require idempotency handling.
- Alternatives considered:
  - Auto retry once on transient failures (higher complexity and ambiguous UI semantics).

### 6) Streaming performance and cancellation

- Decision: The streaming consumer MUST not perform unbounded per-delta main-thread work. UI updates SHOULD be throttled/coalesced (for example, target 50-100ms cadence) while preserving deterministic final content.
- Decision: The implementation MUST avoid O(n^2) string growth from repeated `String` concatenation under high-frequency deltas (e.g. by buffering chunks and assembling on flush points).
- Decision: Cancellation MUST propagate to the underlying transport. When a request is stopped, the underlying `URLSessionTask` for streaming MUST be cancelled so the connection is released promptly.

## Risks / Trade-offs

- [SSE protocol variants differ across providers] -> Implement generic parser but only map OpenAI semantics in provider layer.
- [Malformed chunks can prematurely fail requests] -> Keep parser tolerant; only fail when payload cannot be safely interpreted.
- [Provider interface change touches tests and mocks] -> Update all provider test doubles and add focused regressions.
- [Endpoint fallback misuse] -> Keep fallback explicit and provider-scoped; still enforce strict preflight.

## Migration Plan

1. Create OpenSpec artifacts for proposal/design/specs/tasks.
2. Introduce networking module (`HTTPError`, `HTTPClient`, `URLSessionHTTPClient`, `SSEParser`).
3. Extend `LLMProvider` interface with invocation context and update existing implementations (`MockProvider`, test doubles).
4. Update `RequestCoordinator` to resolve credential + endpoint and pass context into preflight and generation.
5. Add `OpenAIProvider` and register it in `AppContainer.bootstrap()`.
6. Add/update unit tests for parser, client, provider mapping, and request lifecycle regression.
7. Run test suite and verify no behavior regressions on queue/stop/timeout contracts.

Rollback strategy:
- Keep `MockProvider` path untouched for default behavior.
- If OpenAI transport has critical issues, remove provider registration while keeping network module isolated for iterative fixes.

## Open Questions

- None for this change. Provider scope, endpoint policy, and retry policy are fixed.
