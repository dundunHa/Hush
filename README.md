# Hush

Native macOS LLM chat client built with SwiftUI.

## Project Intent

Hush targets a high-performance, modern macOS experience with:

- Multi-provider text/image model support
- Provider configuration management
- Tunable model parameters with persistence
- Quick bar invocation via shortcut and full chat window
- Native SwiftUI-first architecture with clear extension points

## SSOT (Current)

For this initialization stage, the single source of truth is:

- `docs/specs/init-spec.md`

If scope/acceptance changes, update that file first.

## Stack Direction

- UI: SwiftUI (`macOS 14+`)
- Core domain: Swift modules (`HushCore`, `HushProviders`, `HushSettings`)
- Future options:
  - Pure Swift provider integrations
  - Rust sidecar/core via FFI when performance hotspots are proven

## Repository Layout

```text
docs/specs/init-spec.md      # Scope + acceptance + boundaries
Package.swift                # Swift package entry
Sources/HushApp              # SwiftUI app shell
Sources/HushCore             # Shared domain models
Sources/HushProviders        # Provider protocol + registry + mock provider
Sources/HushSettings         # Settings persistence
Tests/HushCoreTests          # Initialization-level tests
```

## Run / Verify

Because this environment can sandbox Swift toolchain caches, run with local cache paths when needed:

```bash
mkdir -p .cache/clang .cache/swiftpm
CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang" \
SWIFTPM_CUSTOM_LIBCACHE_PATH="$PWD/.cache/swiftpm" \
swift test
```

If the package is opened in Xcode, use `HushApp` as the executable target.

## Roadmap (Short)

1. Wire real providers (`OpenAI`, `Anthropic`, `Ollama`) behind `LLMProvider`
2. Add secure API key storage via Keychain
3. Implement system-wide hotkey and floating quick bar panel
4. Add streaming responses and richer message rendering (markdown/images)

