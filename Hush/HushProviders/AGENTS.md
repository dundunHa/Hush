# HushProviders

LLM provider abstraction layer. Protocol-driven with runtime registration.

## Structure

```
LLMProvider.swift          # Protocol: id, availableModels, send(), sendStreaming()
ProviderInvocationContext.swift # Endpoint URL + bearer token for a single request
OpenAIProvider.swift       # OpenAI-compatible API impl (537 lines) — chat completions, streaming SSE
MockProvider.swift         # Deterministic test provider with canned responses
ProviderRegistry.swift     # Runtime provider registration + lookup by ID
CatalogRefreshService.swift# Fetches/updates available model catalogs from providers
```

## Where to Look

| Task | File |
|------|------|
| Add new LLM provider | Implement `LLMProvider` protocol, register in `ProviderRegistry` |
| Modify API request format | `OpenAIProvider.swift` — request body construction |
| Modify streaming parse | `OpenAIProvider.swift` + `HushNetworking/SSEParser.swift` |
| Test with fake provider | `MockProvider.swift` — configure canned responses |
| Model catalog refresh | `CatalogRefreshService.swift` |

## Conventions

- **LLMProvider protocol**: `Sendable`. Must implement `id`, `availableModels`, `send()`, `sendStreaming()`.
- **ProviderInvocationContext**: Passed per-request — contains resolved endpoint + bearer token. Never stored long-term.
- **Terminal event contract**: `sendStreaming()` must yield exactly one terminal `StreamEvent` — either `.completed` or `.failed`. Never both, never neither.
- **OpenAI-compatible**: `OpenAIProvider` works with any OpenAI-compatible API (OpenAI, Anthropic via proxy, local LLMs).
- **Registration**: Providers register in `ProviderRegistry` at bootstrap. Lookup by `providerID`.

## Anti-Patterns

- **Never skip the terminal event** — every stream must end with exactly one `.completed` or `.failed`.
- **Never store credentials in provider** — receive via `ProviderInvocationContext` per-request.
- **Never import GRDB or storage** — providers are pure networking. Credential resolution happens upstream.
