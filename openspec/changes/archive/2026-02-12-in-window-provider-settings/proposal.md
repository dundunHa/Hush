## Why

Settings currently open in a modal sheet, which breaks the main-window flow and does not support a structured configuration workspace. We need an in-window settings experience with side navigation and detailed configuration content, starting with OpenAI provider configuration.

## What Changes

- Replace modal settings presentation with an in-window settings workspace rendered in the main content area.
- Add a two-pane settings layout: left navigation and right detail panel.
- Scope first iteration to one settings item: `Provider`.
- Implement OpenAI provider form with editable fields: `API Key`, `Endpoint`, `Default Model`, and `Enabled`.
- Persist only non-secret configuration in settings; write API key to Keychain.
- Automatically switch selected provider/model to OpenAI after successful save when OpenAI is enabled and credential is available.

## Capabilities

### New Capabilities
- `in-window-settings-provider-config`: Main-window settings workspace with provider-side navigation and OpenAI configuration form.

### Modified Capabilities
- `secure-provider-credential-storage`: Settings UI write path stores only `credentialRef` in settings and writes secret material exclusively to Keychain.

## Impact

- Affected code:
  - `Hush/Views/RootView.swift`
  - `Hush/Views/TopBar/UnifiedTopBar.swift`
  - `Hush/Views/Sidebar/ConversationSidebarView.swift`
  - `Hush/Views/Chat/ChatDetailPane.swift`
  - `Hush/Views/Settings/SettingsWorkspaceView.swift` (new)
  - `Hush/AppContainer.swift`
  - `Hush/HushStorage/KeychainAdapter.swift`
  - `HushTests/AppContainerProviderSettingsTests.swift` (new)
- Removed code:
  - `Hush/Views/Settings/SettingsModalView.swift`
- Validation:
  - Build + targeted tests + full test run with baseline-failure comparison.
