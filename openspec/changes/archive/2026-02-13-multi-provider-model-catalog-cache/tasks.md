## 1. Domain Model and Settings Contracts

- [x] 1.1 Extend provider profile domain types to support multi-provider management without breaking existing settings decoding.
- [x] 1.2 Introduce normalized model capability metadata types (model type, input/output modalities, optional limits/features).
- [x] 1.3 Update `AppSettings` read/write behavior to preserve backward compatibility for existing single-provider users.

## 2. SQLite Catalog Cache Foundation

- [x] 2.1 Add GRDB migrations for provider catalog snapshot and provider catalog model tables.
- [x] 2.2 Add storage protocols for provider catalog persistence and refresh-status reads/writes.
- [x] 2.3 Implement GRDB repositories for provider-scoped upsert/query of catalog models and refresh metadata.
- [x] 2.4 Add repository tests for deterministic ordering, provider scoping, and restart persistence.

## 3. Provider Metadata Introspection Pipeline

- [x] 3.1 Extend provider model discovery mapping to emit normalized metadata and raw metadata passthrough.
- [x] 3.2 Update OpenAI model discovery mapping to support both ID-only payloads and richer metadata payloads.
- [x] 3.3 Persist discovery results through catalog repositories and record refresh success/error state.
- [x] 3.4 Add tests for mapping defaults, unknown-field preservation, and failure-path refresh status updates.

## 4. AppContainer Orchestration and Selection Rules

- [x] 4.1 Add multi-provider profile save/update/remove flows in `AppContainer` with deterministic ID-scoped behavior.
- [x] 4.2 Implement catalog refresh triggers for provider save/enable, explicit refresh action, and missing-catalog-on-switch.
- [x] 4.3 Update strict model validation path to use provider-scoped catalog state and explicit catalog-unavailable failure.
- [x] 4.4 Preserve credential storage rules: Keychain-only secrets, settings/SQLite only `credentialRef` and non-secret metadata.
- [x] 4.5 Add container-level tests for fallback selection, refresh trigger behavior, and strict validation error cases.

## 5. Settings and Composer UI Integration

- [x] 5.1 Extend settings workspace provider section to manage multiple provider profiles and active selection.
- [x] 5.2 Add model catalog refresh status presentation (`lastSuccessAt`, `lastError`) in provider settings detail UI.
- [x] 5.3 Update composer model menu to read provider-scoped cached catalog first, with deterministic fallback and clear error states.

## 6. Verification and Regression

- [x] 6.1 Add/refresh OpenSpec-linked tests for modified capabilities (`strict-provider-and-model-selection`, `secure-provider-credential-storage`, `native-openai-http-sse-provider`).
- [x] 6.2 Run targeted tests for new catalog/repository/container flows.
- [x] 6.3 Run `make build` and `make test`, and confirm no new failures relative to existing baseline.
