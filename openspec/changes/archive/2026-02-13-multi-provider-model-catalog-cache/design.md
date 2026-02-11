## Context

Hush currently stores user-editable configuration in `settings.json` (`JSONSettingsStore`) and chat data in SQLite (`DatabaseManager` + GRDB repositories). Provider secrets are stored only in Keychain (`KeychainAdapter`), and runtime preflight validates provider/model before send.

This works for one primary provider, but it does not scale cleanly to multi-provider switching with rich model metadata:
- `settings.json` is good for profile configuration, but not ideal for large/volatile model catalogs.
- UI model menus currently rely on live provider fetch + ad-hoc fallback, which increases latency and fragility.
- `ModelDescriptor` currently has minimal fields and cannot represent richer model capability data.

The change needs a durable model-catalog cache, explicit refresh lifecycle, and provider-scoped selection behavior while preserving existing secret handling.

## Goals / Non-Goals

**Goals:**
- Keep provider profile configuration in `settings.json` as user-managed source of truth.
- Add SQLite-backed provider model catalog cache with refresh metadata for low-latency reads and restart safety.
- Support multiple provider profiles and fast switching between enabled providers.
- Normalize provider model metadata into a consistent schema (model type, input/output support, optional limits/features).
- Make model selection validation provider-scoped and explicit when cache is stale/empty/unavailable.
- Preserve security invariant: secrets remain Keychain-only.

**Non-Goals:**
- No cross-device catalog sync.
- No provider quota/billing analytics.
- No background daemon-style refresh scheduler beyond app-triggered flows.
- No replacement of `settings.json` with SQLite for user-editable profile settings in this change.

## Decisions

### 1) Split storage responsibility by data volatility and editability

- Decision:
  - `settings.json`: provider profile definitions (id, name, type, endpoint, default model, enabled, credentialRef, selected provider/model).
  - SQLite: provider model catalog rows + refresh state (`lastSuccessAt`, `lastError`, versioning timestamps).
  - Keychain: API keys/secrets only.
- Rationale: aligns with current architecture and avoids coupling user-edited config with frequently refreshed catalog snapshots.
- Alternatives considered:
  - JSON-only (simple but poor for query/update scale and stale-state tracking).
  - SQLite-only for all settings (stronger consistency but bigger migration and UX risk for user-editable config).

### 2) Introduce explicit catalog cache domain model

- Decision: add provider-scoped catalog entities in storage layer:
  - `providerCatalogSnapshots` (providerID, fetchedAt, status, lastError).
  - `providerCatalogModels` (providerID, modelID, displayName, modelType, supportedInputs, supportedOutputs, rawMetadataJSON, updatedAt).
- Decision: expose repository protocols for read/upsert/query by provider and deterministic ordering.
- Rationale: enables stable reads for UI and strict validation without network dependency at send-time.
- Alternatives considered:
  - Store one opaque JSON blob per provider (easier write, harder query/filter/partial updates).

### 3) Define refresh lifecycle and triggers

- Decision:
  - Refresh triggers: provider save (enabled + credential available), explicit user refresh action, and provider switch when no usable cache exists.
  - Refresh is best-effort and non-blocking for settings save.
  - Persist refresh outcome for UI diagnostics (success timestamp/error message).
- Rationale: balances responsiveness and reliability while keeping refresh behavior observable.
- Alternatives considered:
  - Always block save until refresh succeeds (poor UX under network failures).
  - Refresh only on send (high latency and unpredictable first-use failures).

### 4) Normalize model capability metadata at provider boundary

- Decision: extend model metadata contract beyond current `ModelDescriptor.capabilities`:
  - normalized model type (e.g., `chat`, `embedding`, `image`, `audio`, `reasoning`, `unknown`)
  - supported input modalities
  - supported output modalities
  - optional limits/features when available (e.g., context window, max output tokens, tool support)
- Decision: each provider adapter maps remote schema to normalized schema; unknown fields are preserved in raw metadata for debugging/forward compatibility.
- Rationale: makes cross-provider UI/validation consistent while avoiding loss of provider-specific details.
- Alternatives considered:
  - Keep current minimal descriptor and ignore richer metadata (insufficient for upcoming UX and validation needs).

### 5) Make strict model selection cache-aware and deterministic

- Decision: strict preflight validates selected model against provider-scoped catalog cache first.
- Decision: if cache is missing/stale and refresh fails, request fails with explicit diagnostic rather than implicit model fallback.
- Decision: no cross-provider fallback when selected provider is enabled but catalog invalid.
- Rationale: preserves strictness principle and avoids hidden behavior drift.
- Alternatives considered:
  - fallback to provider default/first model silently (non-deterministic and user-hostile).

### 6) Backward-compatible migration strategy

- Decision: additive DB migrations only; existing users keep current `settings.json` layout and provider IDs.
- Decision: existing OpenAI settings are reused; first refresh populates catalog tables.
- Decision: if no catalog rows exist yet, UI uses current safe fallback list while surfacing refresh status.
- Rationale: minimize rollout risk and avoid forced manual migration.

## Risks / Trade-offs

- [Catalog schema over-normalization may not fit all providers] -> Keep extensible enums + `rawMetadataJSON` passthrough.
- [Stale cache can block send under strict mode] -> Provide explicit refresh UX and actionable errors with last refresh status.
- [More storage complexity across JSON + SQLite + Keychain] -> Keep clear ownership boundaries and dedicated repository interfaces.
- [Refresh during provider switch may increase perceived latency] -> Use cached snapshot immediately; perform refresh asynchronously where possible.
- [Future providers expose incompatible metadata fields] -> Normalize required subset only, preserve original payload for evolution.

## Migration Plan

1. Add OpenSpec delta specs for new/modified capabilities.
2. Add SQLite migrations for provider catalog snapshot/model tables.
3. Add storage protocols + GRDB repositories for catalog persistence.
4. Extend domain model for normalized capability metadata and provider profile list behavior.
5. Update `AppContainer` orchestration:
   - multi-provider profile save/update
   - catalog refresh triggers
   - provider/model selection updates
6. Update provider implementations (OpenAI first) to map remote model data to normalized metadata.
7. Update UI surfaces (`SettingsWorkspaceView`, `ComposerDock`) to read cache and show refresh/error state.
8. Add tests:
   - repository and migration tests
   - container orchestration tests
   - provider metadata mapping tests
   - strict selection behavior tests
9. Validate with `make build`, targeted tests, then `make test` (no new failures).

Rollback strategy:
- Disable catalog-backed strict checks behind guard in container/coordinator path and continue using existing fallback model behavior.
- Keep new DB tables additive so rollback does not require destructive migration.

## Open Questions

- Should stale-catalog threshold be global or provider-specific? (default proposal: global default with optional per-provider override later)
- Should refresh be manual-only for providers without credentials at app launch, or retried automatically after credential availability changes?
