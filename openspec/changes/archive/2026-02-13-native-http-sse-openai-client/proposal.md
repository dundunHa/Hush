## Why

Hush has already standardized request lifecycle, queue semantics, and strict provider validation, but it still lacks a real network-backed LLM provider. We need a native HTTP + SSE foundation now to enable real OpenAI streaming without introducing unnecessary third-party networking complexity.

## What Changes

- Add a reusable native networking layer based on `URLSession` for JSON request/response and SSE stream consumption.
- Add bearer-token authentication support for provider requests.
- Add an `OpenAIProvider` runtime implementation for model preflight (`/v1/models`) and streaming generation (`/v1/chat/completions`).
- Extend provider invocation boundaries so runtime request context (endpoint + bearer token) is passed explicitly by the coordinator.
- Keep existing queue/timeout/stop semantics unchanged; only switch provider transport path from mock-only to mock + OpenAI.
- Keep provider settings UI and multi-provider protocol unification out of scope in this change.

## Capabilities

### New Capabilities
- `native-openai-http-sse-provider`: Native URLSession-based HTTP/SSE transport with bearer auth, plus OpenAI provider integration for preflight and streaming chat generation.

### Modified Capabilities
- `strict-provider-and-model-selection`: Preflight model validation and generation invocation MUST execute against provider runtime context built by coordinator (configured endpoint and resolved credential), without fallback.

## Impact

- Affected code:
  - `Hush/HushProviders/LLMProvider.swift`
  - `Hush/RequestCoordinator.swift`
  - `Hush/HushProviders/MockProvider.swift`
  - `Hush/AppContainer.swift`
  - New networking module under `Hush/HushNetworking/*`
  - New provider implementation `Hush/HushProviders/OpenAIProvider.swift`
- Dependencies:
  - No new third-party package dependencies.
  - Uses Foundation `URLSession` streaming APIs.
- Testing:
  - New unit tests for SSE parsing, HTTP client behavior, OpenAI provider mapping, and lifecycle regressions with updated provider interface.
