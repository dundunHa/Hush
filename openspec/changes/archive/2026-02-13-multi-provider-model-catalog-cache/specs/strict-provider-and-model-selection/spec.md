## MODIFIED Requirements

### Requirement: Strict Model Validation
The system MUST require the selected model ID to be valid for the selected provider before starting generation for every send attempt.
Validation MUST execute against provider-scoped catalog state (cached or freshly refreshed) and MUST remain strict under stale/empty catalog conditions.

#### Scenario: Selected model is invalid for provider
- **WHEN** the selected model ID is not available from the selected provider catalog
- **THEN** the system SHALL fail the request immediately and SHALL NOT substitute another model

#### Scenario: Missing provider catalog fails explicitly
- **WHEN** no provider catalog is available for the selected provider and refresh does not succeed
- **THEN** the system SHALL fail preflight with explicit catalog-unavailable diagnostics
- **AND** the system SHALL NOT start generation

#### Scenario: Model preflight validation timeout is explicit
- **WHEN** selected-model preflight validation does not complete within the configured timeout budget
- **THEN** the system SHALL fail the request as timeout and SHALL NOT start generation

#### Scenario: Preflight failure prevents generation start
- **WHEN** strict provider or model preflight validation fails
- **THEN** the system SHALL NOT invoke generation stream start for that request

#### Scenario: Validation remains provider-scoped
- **WHEN** model identifiers overlap across different providers
- **THEN** the system SHALL validate selected model only against the selected provider catalog
- **AND** the system SHALL NOT treat another provider's catalog entry as valid
