## ADDED Requirements

### Requirement: Strict Provider Resolution
The system MUST require the selected provider ID to resolve to an enabled configured provider and a registered runtime provider implementation before sending.

#### Scenario: Selected provider is missing
- **WHEN** the selected provider ID does not resolve to a registered enabled provider
- **THEN** the system SHALL fail the request immediately and SHALL NOT fallback to any other provider

#### Scenario: Selected provider is disabled
- **WHEN** the selected provider configuration exists but is disabled
- **THEN** the system SHALL fail the request immediately and SHALL NOT fallback to any other provider

#### Scenario: Selected provider has no runtime implementation
- **WHEN** the selected provider configuration is enabled but no provider is registered for that ID
- **THEN** the system SHALL fail the request immediately and SHALL NOT fallback to any other provider

### Requirement: Strict Model Validation
The system MUST require the selected model ID to be valid for the selected provider before starting generation for every send attempt.

#### Scenario: Selected model is invalid for provider
- **WHEN** the selected model ID is not available from the selected provider
- **THEN** the system SHALL fail the request immediately and SHALL NOT substitute another model

#### Scenario: Model preflight validation timeout is explicit
- **WHEN** selected-model preflight validation does not complete within the configured timeout budget
- **THEN** the system SHALL fail the request as timeout and SHALL NOT start generation

#### Scenario: Preflight failure prevents generation start
- **WHEN** strict provider or model preflight validation fails
- **THEN** the system SHALL NOT invoke generation stream start for that request

### Requirement: Transparent Remote Error Reporting
The system MUST surface remote provider failures to the user without silent downgrade.

#### Scenario: Remote provider returns explicit error
- **WHEN** the provider returns an error response with remote details
- **THEN** the system SHALL surface the failure and include remote error details in user-visible diagnostics

#### Scenario: Remote provider fails without detailed payload
- **WHEN** generation fails without structured remote detail fields
- **THEN** the system SHALL still emit user-visible diagnostics with provider identity and failure category

### Requirement: Explicit Timeout Failure
The system MUST treat timeout as a first-class failure type and surface it explicitly.

#### Scenario: Generation exceeds timeout budget
- **WHEN** the active generation exceeds the configured timeout
- **THEN** the system SHALL terminate the request as timeout failure and SHALL display timeout-specific error information

### Requirement: Defined Default Timeout Budgets
The system MUST define deterministic default timeout budgets for preflight and generation paths.

#### Scenario: Default timeout budgets apply
- **WHEN** no override is configured
- **THEN** the model preflight timeout SHALL default to `3s`
- **AND** the generation timeout SHALL default to `60s`
