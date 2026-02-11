## 1. OpenSpec Artifacts

- [x] 1.1 Create change scaffold for `2026-02-12-in-window-provider-settings`.
- [x] 1.2 Add proposal/design/spec deltas for in-window provider settings.

## 2. UI Routing and Layout

- [x] 2.1 Replace modal settings sheet with in-window content routing in `RootView`.
- [x] 2.2 Update top bar behavior to support settings mode.
- [x] 2.3 Add two-pane `SettingsWorkspaceView` with `Back to app` and `Provider` navigation.
- [x] 2.4 Remove `SettingsModalView` and related wiring.

## 3. Provider Configuration Save Pipeline

- [x] 3.1 Add OpenAI settings snapshot + save API to `AppContainer`.
- [x] 3.2 Add writable credential store abstraction in Keychain adapter.
- [x] 3.3 Implement validation/defaulting and selection fallback rules.

## 4. Verification

- [x] 4.1 Add unit tests for AppContainer OpenAI settings save semantics.
- [x] 4.2 Run `make build`.
- [x] 4.3 Run targeted test for `AppContainerProviderSettingsTests`.
- [x] 4.4 Run `make test` and confirm no new failures beyond known baseline.
