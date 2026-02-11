## ADDED Requirements

### Requirement: Native HTTP JSON Request Support
The system MUST provide a reusable native HTTP client built on Foundation `URLSession` that supports JSON request/response interactions and bearer token authentication.

#### Scenario: Bearer-authenticated JSON request succeeds
- **WHEN** a provider sends a JSON request with a bearer token via the native HTTP client
- **THEN** the client SHALL include `Authorization: Bearer <token>` and return decoded response payload for 2xx status

#### Scenario: Non-2xx response surfaces structured transport error
- **WHEN** the remote endpoint returns a non-2xx status for a JSON request
- **THEN** the client SHALL fail with status code, response body (if present), and request URL context

### Requirement: Native SSE Stream Consumption
The system MUST provide SSE streaming support that parses line-based server-sent events and emits events incrementally.

#### Scenario: SSE event assembled from multi-line data
- **WHEN** a streamed SSE event contains multiple `data:` lines before a blank-line delimiter
- **THEN** the parser SHALL combine those lines into one event payload separated by newline characters

#### Scenario: Parser tolerates unknown fields
- **WHEN** an SSE frame contains unknown fields other than `data`, `event`, `id`, or `retry`
- **THEN** the parser SHALL ignore unknown fields and continue parsing subsequent events

### Requirement: OpenAI Model Discovery via Provider Context
The system MUST allow the OpenAI provider to resolve available models from the configured endpoint using invocation context.

#### Scenario: OpenAI provider lists models from configured endpoint
- **WHEN** OpenAI provider preflight runs with a context endpoint and bearer token
- **THEN** it SHALL call `<endpoint>/models` and map returned model identifiers into provider model descriptors

#### Scenario: Missing bearer token fails OpenAI preflight
- **WHEN** OpenAI provider preflight is invoked without a bearer token in context
- **THEN** it SHALL fail preflight and SHALL NOT silently fallback to unauthenticated calls

### Requirement: OpenAI Streaming Chat Event Mapping
The system MUST map OpenAI chat-completions SSE payloads into request lifecycle stream events.

#### Scenario: OpenAI delta chunks map to incremental stream events
- **WHEN** OpenAI SSE emits payloads containing `choices[].delta.content`
- **THEN** the provider SHALL emit `StreamEvent.delta` for each non-empty content fragment

#### Scenario: Non-content OpenAI deltas are ignored
- **WHEN** OpenAI SSE emits delta payloads that do not contain `choices[].delta.content` (e.g. role/tool metadata)
- **THEN** the provider SHALL ignore those deltas and continue consuming the stream

#### Scenario: OpenAI done sentinel finalizes stream
- **WHEN** OpenAI SSE emits `data: [DONE]`
- **THEN** the provider SHALL emit exactly one terminal completed stream event for the request
