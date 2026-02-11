## Requirements

### Requirement: Secrets Are Stored Only in Keychain
The system MUST store provider secrets only in Keychain and MUST NOT persist secret material in settings or the database.

#### Scenario: Persisted configuration stores only credential references
- **WHEN** the app persists provider configuration
- **THEN** the system SHALL store only a non-secret credential reference (e.g. `credential_ref`)
- **AND** the system SHALL NOT persist the provider secret value in `settings.json`
- **AND** the system SHALL NOT persist the provider secret value in the SQLite database

#### Scenario: Settings UI save path keeps secrets out of settings
- **WHEN** the user saves provider settings from the settings workspace
- **THEN** secret material entered in the form SHALL be written to Keychain only
- **AND** persisted app settings SHALL include only non-secret provider fields and `credentialRef`

#### Scenario: Model catalog cache stores no secrets
- **WHEN** provider model catalogs and refresh metadata are persisted to SQLite
- **THEN** persisted catalog records SHALL include no API key or other secret material
- **AND** provider authentication SHALL continue to resolve from Keychain via `credentialRef`

#### Scenario: Provider request resolves secret from Keychain
- **WHEN** the system prepares a provider request that requires a credential
- **THEN** the system SHALL resolve the secret from Keychain using the stored `credential_ref`

#### Scenario: Missing credential fails explicitly
- **WHEN** a required Keychain item is missing or inaccessible
- **THEN** the system SHALL fail the request with an explicit credential-resolution error
- **AND** the system SHALL NOT silently fall back to an insecure source
