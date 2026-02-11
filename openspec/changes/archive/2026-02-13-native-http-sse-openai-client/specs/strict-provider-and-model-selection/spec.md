## MODIFIED Requirements

### Requirement: Strict Model Validation
The system MUST require the selected model ID to be valid for the selected provider before starting generation for every send attempt.
Model validation MUST execute against the coordinator-resolved provider invocation context at request time.

#### Scenario: Selected model is invalid for provider
- **WHEN** the selected model ID is not available from the selected provider
- **THEN** the system SHALL fail the request immediately and SHALL NOT substitute another model

#### Scenario: Model preflight validation timeout is explicit
- **WHEN** selected-model preflight validation does not complete within the configured timeout budget
- **THEN** the system SHALL fail the request as timeout and SHALL NOT start generation

#### Scenario: Preflight failure prevents generation start
- **WHEN** strict provider or model preflight validation fails
- **THEN** the system SHALL NOT invoke generation stream start for that request

#### Scenario: Coordinator-resolved invocation context is authoritative
- **WHEN** a request starts preflight for a non-mock provider
- **THEN** the system SHALL use coordinator-resolved endpoint and credential context for provider preflight and generation, without provider-side fallback to external global state
