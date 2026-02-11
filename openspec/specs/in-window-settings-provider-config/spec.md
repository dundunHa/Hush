## Requirements

### Requirement: Settings Render In Main Window Content
The system MUST render settings inside the main application window content area instead of using a modal sheet.

#### Scenario: Enter settings from sidebar
- **WHEN** the user activates `Settings` from the sidebar
- **THEN** the app SHALL display the in-window settings workspace
- **AND** the app SHALL NOT present a modal settings sheet

#### Scenario: Exit settings to chat
- **WHEN** the user activates `Back to app` in settings navigation
- **THEN** the app SHALL return to the normal chat workspace in the same window

### Requirement: Two-Pane Provider Settings Workspace
The settings workspace MUST provide left navigation and right detail panels.

#### Scenario: Provider-only navigation in first iteration
- **WHEN** settings workspace is displayed
- **THEN** the left panel SHALL include a `Provider` navigation item
- **AND** no other settings sections SHALL be required in this change

#### Scenario: Provider detail panel
- **WHEN** `Provider` is selected
- **THEN** the right panel SHALL display an OpenAI provider configuration form

### Requirement: OpenAI Configuration Fields And Save Feedback
The OpenAI settings form MUST expose only operational fields for this phase.

#### Scenario: Editable field scope
- **WHEN** provider settings are shown
- **THEN** the form SHALL allow editing `API Key`, `Endpoint`, `Default Model`, and `Enabled`
- **AND** the form SHALL NOT expose raw config fields such as `id`, `type`, or `credentialRef`

#### Scenario: Save clears transient secret input
- **WHEN** settings save succeeds
- **THEN** the API key input field SHALL be cleared
- **AND** success feedback SHALL be shown in the UI

### Requirement: OpenAI Save Validation And Selection Behavior
The system MUST validate OpenAI settings before persisting and apply deterministic provider selection behavior.

#### Scenario: Endpoint defaulting and model validation
- **WHEN** the user saves OpenAI settings
- **THEN** empty endpoint input SHALL default to `OpenAIProvider.defaultEndpoint`
- **AND** empty default model SHALL fail with explicit validation error

#### Scenario: Enabled provider requires credential availability
- **WHEN** OpenAI is saved as enabled
- **THEN** save SHALL require either a non-empty API key in the current submission or an existing Keychain secret referenced by `credentialRef`

#### Scenario: Successful enabled save auto-selects OpenAI
- **WHEN** OpenAI settings save succeeds and OpenAI is enabled with available credential
- **THEN** the app SHALL set `selectedProviderID` to `openai`
- **AND** the app SHALL set `selectedModelID` to the configured default model

#### Scenario: Disabling selected OpenAI falls back deterministically
- **WHEN** OpenAI is disabled and current selection is `openai`
- **THEN** the app SHALL switch to the first enabled provider
- **AND** SHALL prefer `mock` when available
