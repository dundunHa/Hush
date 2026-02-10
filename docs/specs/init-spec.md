# Hush Init Spec

Status: Draft  
Last updated: 2026-02-10

## 1. Goal

Initialize a native macOS LLM chat app foundation using SwiftUI with a clear path to:

- Multi-provider text/image model integrations
- Provider/model parameter configuration and persistence
- Quick bar invocation + main chat window workflow
- High-performance, modern UI architecture

## 2. In Scope (Init Phase)

1. Swift package structure and module boundaries
2. Core domain models for chat, provider config, model parameters, and app settings
3. Provider abstraction (`LLMProvider`) and registry
4. Mock provider to validate end-to-end flow without network dependency
5. Local JSON settings persistence
6. SwiftUI app shell:
   - Settings sidebar
   - Chat workspace
   - Quick bar sheet placeholder
7. Minimal tests for config persistence and provider registration

## 3. Out of Scope (Init Phase)

1. Real provider API implementations
2. Keychain integration for secrets
3. System-global shortcut event capture implementation details
4. Streaming token rendering
5. Multi-window session orchestration
6. Rust integration

## 4. Acceptance Criteria

1. Repository has a clear Swift module structure for app/core/providers/settings
2. App shell can compile in a normal local macOS Swift toolchain environment
3. Mock provider can respond to user message flow inside app state
4. Parameter changes and provider selection are represented in settings model
5. Settings store supports save/load roundtrip with tests
6. Quick bar path exists in UI and reuses the same send pipeline

## 5. Risks / Notes

1. Swift toolchain cache path issues may occur under strict sandboxed environments
2. Global hotkey capture requires additional AppKit/Carbon integration and permissions decisions
3. Provider secret handling must move to Keychain before production usage

## 6. Next Milestone Suggestion

- M1: Add real `OpenAI` provider + secure key storage + streaming UI
- M2: Add `Anthropic` and `Ollama`, provider health checks, and image message support
