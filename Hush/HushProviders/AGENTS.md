# HushProviders

LLM provider abstraction layer. Protocol-driven with runtime registration. Supports chat completions and image generation.

## Structure

```
LLMProvider.swift              # Protocol: id, availableModels, send(), sendStreaming(), sendImageGeneration()
OpenAIAPIModels.swift          # Request/response Codable models for OpenAI-compatible APIs
OpenAIProvider.swift           # OpenAI-compatible API impl — chat completions, image generation (DALL-E)
OpenAIProvider+Streaming.swift # SSE streaming extension for OpenAIProvider
MockProvider.swift             # Deterministic test provider with canned responses
ProviderRegistry.swift         # Runtime provider registration + lookup by ID
CatalogRefreshService.swift    # Fetches/updates available model catalogs from providers
```

## Where to Look

| Task | File |
|------|------|
| Add new LLM provider | Implement `LLMProvider` protocol, register in `ProviderRegistry` |
| Modify API request/response models | `OpenAIAPIModels.swift` — shared Codable types |
| Modify chat request flow | `OpenAIProvider.swift` — request body construction |
| Modify streaming parse | `OpenAIProvider+Streaming.swift` + `HushNetworking/SSEParser.swift` |
| Add image generation support | `OpenAIProvider.swift` -> `sendImageGeneration()` |
| Test with fake provider | `MockProvider.swift` — configure canned responses |
| Model catalog refresh | `CatalogRefreshService.swift` |

## Conventions

- **LLMProvider protocol**: `Sendable`. Must implement `id`, `availableModels`, `send()`, `sendStreaming()`. Optional `sendImageGeneration()`.
- **ProviderInvocationContext**: Passed per-request — contains resolved endpoint + bearer token. Never stored long-term.
- **Terminal event contract**: `sendStreaming()` must yield exactly one terminal `StreamEvent` — either `.completed` or `.failed`. Never both, never neither.
- **OpenAI-compatible**: `OpenAIProvider` works with any OpenAI-compatible API (OpenAI, Anthropic via proxy, local LLMs).
- **API models separated**: Request/response types live in `OpenAIAPIModels.swift`, not inline in the provider.
- **Streaming split**: Streaming logic lives in `OpenAIProvider+Streaming.swift` extension to keep file sizes manageable.
- **Registration**: Providers register in `ProviderRegistry` at bootstrap. Lookup by `providerID`.

## Anti-Patterns

- **Never skip the terminal event** — every stream must end with exactly one `.completed` or `.failed`.
- **Never store credentials in provider** — receive via `ProviderInvocationContext` per-request.
- **Never import GRDB or storage** — providers are pure networking. Credential resolution happens upstream.
