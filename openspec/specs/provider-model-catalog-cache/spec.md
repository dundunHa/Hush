## ADDED Requirements

### Requirement: Provider Model Catalog Is Persisted in SQLite
The system MUST persist provider model catalogs in SQLite so model metadata remains available across app restarts.

#### Scenario: Refresh success upserts provider model catalog
- **WHEN** a provider catalog refresh succeeds
- **THEN** the system SHALL upsert provider-scoped model records in SQLite
- **AND** previously persisted records for that provider SHALL be replaced or updated deterministically

#### Scenario: Catalog data survives restart
- **WHEN** the app restarts after a successful catalog refresh
- **THEN** the system SHALL restore provider model catalog data from SQLite without requiring immediate network calls

### Requirement: Catalog Reads Are Provider-Scoped and Deterministic
The system MUST query model catalogs by provider ID and MUST return deterministic results for UI and validation.

#### Scenario: Query returns models only for requested provider
- **WHEN** the system requests catalog models for provider `P`
- **THEN** the query SHALL return only model records for provider `P`
- **AND** records from other providers SHALL NOT be included

#### Scenario: Query ordering is deterministic
- **WHEN** catalog models are returned for a provider
- **THEN** the system SHALL return them in deterministic order for stable UI rendering

### Requirement: Refresh State Is Persisted for Diagnostics
The system MUST persist provider catalog refresh state, including latest successful refresh time and latest refresh error.

#### Scenario: Successful refresh updates status
- **WHEN** provider catalog refresh succeeds
- **THEN** the system SHALL persist `lastSuccessAt`
- **AND** the system SHALL clear `lastError` for that provider

#### Scenario: Failed refresh updates error state
- **WHEN** provider catalog refresh fails
- **THEN** the system SHALL persist provider-scoped error details in `lastError`
- **AND** the system SHALL preserve the last successful catalog snapshot for reads

### Requirement: Refresh Triggers Are Explicit and Observable
The system MUST trigger catalog refresh on defined events and expose refresh outcome to settings and model-selection surfaces.

#### Scenario: Provider save with usable credential triggers refresh
- **WHEN** provider settings are saved with provider enabled and credential available
- **THEN** the system SHALL trigger provider catalog refresh

#### Scenario: Explicit user refresh triggers refresh
- **WHEN** the user triggers manual model refresh for a provider
- **THEN** the system SHALL run catalog refresh for that provider and update persisted refresh status
