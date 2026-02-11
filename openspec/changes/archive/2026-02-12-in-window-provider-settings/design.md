## Context

The app currently uses `.sheet(isPresented:)` in `RootView` to present `SettingsModalView`. This change moves settings into the main window content flow. The first version only exposes provider configuration and must preserve existing security guarantees: API keys never persist in settings JSON or SQLite.

## Goals / Non-Goals

**Goals**
- Render settings directly inside the main window.
- Keep top bar visible while settings are active.
- Provide left navigation + right detail layout.
- Implement OpenAI configuration editing and save flow.
- Ensure key persistence is Keychain-only and settings keep only `credentialRef`.
- Auto-select OpenAI after save when enabled and credential is available.

**Non-Goals**
- Multi-provider settings management UI.
- General/theme settings migration in this change.
- Provider connectivity test button.
- Additional provider types beyond OpenAI.

## Decisions

### 1) Main-window route toggle
- Decision: Keep `showSettings` in `RootView`, but switch from modal sheet to content routing.
- Behavior: `showSettings == true` renders `SettingsWorkspaceView`; `false` renders existing chat layout.

### 2) Top bar behavior in settings mode
- Decision: Keep the existing top bar visible.
- Decision: Hide sidebar toggle affordance and sidebar slot in settings mode to avoid inactive controls.

### 3) Settings information architecture
- Decision: Left pane contains one nav item (`Provider`) and a top `Back to app` action.
- Decision: Right pane renders OpenAI-only details in this phase.

### 4) OpenAI save pipeline
- Decision: OpenAI provider ID is fixed as `openai`.
- Decision: Save flow upserts one `ProviderConfiguration` entry for `openai`.
- Decision: `credentialRef` reuses existing value when present, otherwise defaults to `openai`.
- Decision: Non-empty API key input writes to Keychain using `credentialRef`.
- Decision: Settings persist only non-secret fields + `credentialRef`.

### 5) Validation and auto-selection
- Decision: `defaultModelID` is required.
- Decision: empty endpoint normalizes to `OpenAIProvider.defaultEndpoint`.
- Decision: when `enabled == true`, save requires either a non-empty API key in this request or an existing Keychain secret for `credentialRef`.
- Decision: after successful save, if OpenAI is enabled and credential exists, set:
  - `selectedProviderID = "openai"`
  - `selectedModelID = defaultModelID`
- Decision: if OpenAI is disabled while currently selected, fall back to first enabled provider, preferring `mock`.

## Risks / Trade-offs

- Existing settings modal is removed, so any future non-provider settings need a new section in the workspace.
- Keychain failures can block save when enabling provider; surfaced as explicit user-visible error string.
- The one-item navigation may look over-structured initially, but it keeps layout consistent for future expansion.

## Migration Plan

1. Add OpenSpec artifacts for this change.
2. Implement new settings workspace view and root routing changes.
3. Add AppContainer provider settings save/read API with Keychain write path.
4. Add tests for save semantics and selection fallback.
5. Run build and tests; compare full test result against current baseline failures.
