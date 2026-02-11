## 1. OpenSpec and Provider Contract Updates

- [x] 1.1 Add proposal/design/spec/task artifacts for `native-http-sse-openai-client`.
- [x] 1.2 Extend `LLMProvider` API with `ProviderInvocationContext` and context-aware method signatures.
- [x] 1.3 Update existing providers and test doubles to compile with the new provider interface.

## 2. Native Networking Foundation

- [x] 2.1 Add networking primitives (`HTTPError`, `HTTPRequest`, `HTTPClient`, `SSEEvent`) under `HushNetworking`.
- [x] 2.2 Implement native `URLSessionHTTPClient` for JSON requests, bearer auth, and non-2xx error mapping.
- [x] 2.3 Implement `SSEParser` and stream API (`URLSession.bytes(for:)`) that emits parsed SSE events.

## 3. OpenAI Provider Integration

- [x] 3.1 Implement `OpenAIProvider.availableModels(context:)` using `<endpoint>/models`.
- [x] 3.2 Implement `OpenAIProvider.sendStreaming(..., context:)` using `<endpoint>/chat/completions` and SSE mapping.
- [x] 3.3 Register `OpenAIProvider` in app bootstrap without changing default selected provider.
- [x] 3.4 Update `RequestCoordinator` to build invocation context from provider config + credential resolver and pass it to provider calls.
- [x] 3.5 Add streaming assembly safeguards (avoid O(n^2) string growth; throttle/coalesce UI updates under high-frequency deltas).

## 4. Verification and Regression Coverage

- [x] 4.1 Add SSE parser tests for multiline payload, unknown fields, and done sentinel handling.
- [x] 4.2 Add HTTP client tests for bearer header usage and non-2xx error mapping.
- [x] 4.3 Add OpenAI provider tests with fake HTTP client for success and failure flows.
- [x] 4.4 Update lifecycle/provider tests to validate credential failure, timeout behavior, and no regression in queue/stop semantics.
- [x] 4.5 Run test suite and confirm all new tasks are complete.
