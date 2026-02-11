## Why

Current settings and model selection flows are optimized for a single provider and lightweight model metadata. With upcoming multi-provider support, live-fetching model lists on demand is too fragile: it adds switching latency, fails hard on transient network errors, and cannot represent richer metadata (model type, supported input/output, limits) in a stable way.

We need a clear separation between provider profile configuration and provider model catalog data, so users can switch providers quickly while the app keeps a durable, refreshable model capability view.

## What Changes

- Introduce multi-provider profile management as first-class settings data (non-secret fields only), so users can create and switch across multiple providers.
- Keep provider profile source-of-truth in `settings.json` for user-editable configuration, while adding SQLite-backed cache tables for provider model catalogs and capability metadata.
- Add provider model catalog refresh flow triggered by provider save/enable, provider switch when no usable cache exists, and explicit user refresh, with persisted refresh status (`lastSuccessAt`, `lastError`) for UI feedback.
- Expand model metadata beyond current coarse capabilities to include normalized model type and supported input/output modalities, plus optional limits/features when providers expose them.
- Update model selection to read from provider-scoped cached catalog first, with explicit stale/empty-catalog handling and clear error states when generation cannot proceed.
- Preserve current secret policy: API keys remain in Keychain only; settings and SQLite persist only non-secret data and `credentialRef`.
- Phase rollout:
  - Phase 1: full path for OpenAI (profile + catalog cache + metadata normalization).
  - Phase 2+: add additional providers using the same catalog and capability schema (no data model redesign required).
- Non-goals for this change:
  - No cross-device model catalog sync.
  - No provider-side billing/quota dashboards.
  - No credential storage outside Keychain.

## Scope Clarifications (Reduce Ambiguity)

### Terminology
- **Provider profile**: user-editable configuration for a provider instance (enabled flag, endpoint/base URL if applicable, non-secret fields, and `credentialRef`).
- **Provider ID**: stable identifier for a provider profile. It MUST be persisted in `settings.json` and used as the scope key for all catalog cache rows.
- **Model ID**: provider-scoped identifier for a model. The pair `(providerID, modelID)` is the uniqueness boundary; overlapping `modelID`s across providers are expected.
- **Catalog cache**: SQLite-persisted model records and refresh state for a single provider profile.
- **Refresh state**: persisted diagnostics for the most recent successful refresh (`lastSuccessAt`) and most recent error (`lastError`) on a per-provider basis.

### Storage Ownership & Source of Truth
- `settings.json` remains the SSOT for provider profiles and active provider/model selection. SQLite is NOT user-editable configuration.
- SQLite stores only provider-scoped catalog cache data (models + refresh state). It may contain stale/outdated snapshots by design; the app must be explicit about that in UX.
- When a provider profile is removed, the app SHOULD remove provider-scoped catalog cache rows for that `providerID` (best-effort cleanup; no secret data is involved).
- Secrets MUST never be written to either `settings.json` or SQLite; only `credentialRef` is persisted outside Keychain.

### Refresh Lifecycle (UX + Reliability)
- Provider save MUST NOT be blocked on a successful refresh. Refresh is best-effort and observable (UI reads persisted `lastSuccessAt` / `lastError`).
- Refresh SHOULD be single-flight per provider profile (coalesce concurrent triggers) to avoid races and partial UI updates.
- If a provider has no usable cache (first run, or cache cleared) the app MAY attempt a refresh on provider switch, but if refresh fails the UI must surface an explicit “catalog unavailable” state rather than silently falling back to a different provider/model.
- On refresh failure, the last successful catalog snapshot (if any) remains readable and is used for selection + strict validation.

### Stale vs Missing vs Empty (Selection Rules)
- **Missing/empty catalog**: no persisted model rows for the provider. The system must attempt refresh via explicit triggers and fail preflight with clear diagnostics if still unavailable.
- **Stale catalog**: has persisted rows but is older than a freshness threshold. Initially, “stale” affects UI messaging and refresh prompting only; strict validation remains based on the cached snapshot (no hidden substitution).
- The initial freshness threshold needs to be defined (see Open Questions). Until defined, staleness MUST NOT introduce new hard failures by itself; only missing/empty catalog blocks strict validation.

### Normalized Metadata Scope (Avoid Overreach)
- Normalization MUST define a small required core: `modelType`, supported input modalities, supported output modalities.
- Optional limits/features (context window, max output tokens, tool support, etc.) are best-effort and MUST be safe-defaulted when unknown.
- Provider-specific fields MUST be preserved (e.g., opaque JSON payload) for debugging/forward-compatibility, but MUST NOT be required for core UI/validation.

### Backward Compatibility Expectations
- Existing single-provider users must continue working without manual migration.
- Existing OpenAI configuration is upgraded in-place to a provider profile with a stable `providerID`; first successful refresh populates SQLite cache.
- Until the first successful refresh, OpenAI may present a safe fallback model list (clearly marked as fallback) while showing refresh status and encouraging refresh.

## Capabilities

### New Capabilities
- `multi-provider-profile-management`: Manage multiple provider configurations in settings and support fast active-provider switching.
- `provider-model-catalog-cache`: Persist provider model catalogs and refresh metadata in SQLite for restart-safe and low-latency reads.
- `provider-model-capability-introspection`: Fetch and normalize provider model metadata (model type, input/output support, optional limits/features).

### Modified Capabilities
- `strict-provider-and-model-selection`: Selection validation now depends on provider-scoped catalog state (cached or refreshed) with explicit stale/empty-catalog handling.
- `secure-provider-credential-storage`: Extend write-path guarantees so provider profile and catalog persistence never store secret values, only `credentialRef`.
- `native-openai-http-sse-provider`: OpenAI model discovery requirements expand from ID-only mapping to normalized rich metadata mapping when response fields are available.

## Impact

- Affected code:
  - `Hush/HushCore/AppSettings.swift`
  - `Hush/HushCore/ProviderConfiguration.swift`
  - `Hush/HushCore/ModelDescriptor.swift` (or replacement metadata model)
  - `Hush/HushSettings/JSONSettingsStore.swift`
  - `Hush/HushStorage/DatabaseManager.swift` (new migrations/tables for model catalog cache)
  - `Hush/HushStorage/` (new catalog repository interfaces/implementations)
  - `Hush/AppContainer.swift`
  - `Hush/HushProviders/OpenAIProvider.swift` (and future providers)
  - `Hush/Views/Settings/SettingsWorkspaceView.swift`
  - `Hush/Views/Chat/ComposerDock.swift`
- Affected tests:
  - `HushTests/` for settings persistence, catalog cache repository, refresh flow, and strict selection validation.
- Data/storage impact:
  - `settings.json` remains for user-editable provider profiles.
  - SQLite adds provider-model catalog cache and refresh-state persistence.
  - Keychain remains the only secret store.
- Compatibility:
  - Existing single-provider users continue to work without manual migration; existing OpenAI configuration is upgraded in place when catalog cache is first populated.

## Success Criteria (Definition of Done)

- After one successful refresh, model selection UI reads provider-scoped models from SQLite and remains usable after app restart with no immediate network call.
- Switching between enabled provider profiles does not require live-fetching models to populate the menu; cached data is sufficient and any refresh can run in the background (missing/empty cache remains an explicit state).
- Refresh success/failure is visible in settings via `lastSuccessAt` / `lastError` and does not leak secrets.
- Strict provider/model preflight never silently substitutes a model; it either validates against provider-scoped cached data or fails explicitly when the catalog is unavailable.

## Open Questions

- What is the initial “stale catalog” threshold (global default vs per-provider override)?
- When credentials become available (e.g., user adds a key), should refresh be auto-triggered immediately or remain manual unless the provider is enabled/switch-selected?
