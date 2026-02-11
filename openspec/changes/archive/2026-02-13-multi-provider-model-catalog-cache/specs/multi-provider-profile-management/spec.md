## ADDED Requirements

### Requirement: Multiple Provider Profiles Are Persisted as User Settings
The system MUST persist multiple provider profiles in user-editable settings and MUST keep each profile scoped by a stable provider ID.

#### Scenario: Create and persist additional provider profile
- **WHEN** the user saves a new provider profile with required non-secret fields
- **THEN** the system SHALL append that profile to persisted settings
- **AND** the system SHALL preserve existing profiles unchanged

#### Scenario: Update existing provider profile in place
- **WHEN** the user edits an existing provider profile and saves
- **THEN** the system SHALL update that profile by provider ID
- **AND** the system SHALL NOT create a duplicate profile entry

#### Scenario: Profiles survive app restart
- **WHEN** the app restarts after provider profiles were saved
- **THEN** the system SHALL restore all persisted provider profiles from settings

### Requirement: Provider Activation and Selection Are Deterministic
The system MUST provide deterministic behavior when enabling, disabling, and selecting provider profiles.

#### Scenario: Enabled provider can become active selection
- **WHEN** the user selects an enabled provider profile
- **THEN** the system SHALL set `selectedProviderID` to that provider
- **AND** the system SHALL set `selectedModelID` to a valid model for that provider when available

#### Scenario: Disabling selected provider triggers deterministic fallback
- **WHEN** the currently selected provider is disabled
- **THEN** the system SHALL switch to a deterministic enabled fallback provider
- **AND** the system SHALL NOT keep the disabled provider as active selection

#### Scenario: Disabled provider cannot be selected for send
- **WHEN** a disabled provider is selected by stale UI or stale persisted state
- **THEN** the system SHALL fail request preflight explicitly
- **AND** the system SHALL NOT silently route to another provider

### Requirement: Provider Profile Identity Is Stable Across Renames
The system MUST treat provider display-name changes as metadata updates and MUST preserve provider identity and references.

#### Scenario: Renaming provider keeps identity
- **WHEN** the user changes a provider display name
- **THEN** the system SHALL keep the same provider ID and `credentialRef`
- **AND** existing selection and catalog bindings SHALL remain valid

### Requirement: Single-Provider Settings Upgrade Is Backward Compatible
The system MUST support existing single-provider settings without requiring manual migration.

#### Scenario: Existing settings load without data loss
- **WHEN** settings from a previous single-provider build are loaded
- **THEN** the system SHALL keep existing provider configuration values
- **AND** the system SHALL allow additional provider profiles to be added incrementally
