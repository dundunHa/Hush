## MODIFIED Requirements

### Requirement: OpenAI Model Discovery via Provider Context
The system MUST allow the OpenAI provider to resolve available models from the configured endpoint using invocation context.
OpenAI model discovery MUST map response payloads to normalized model capability metadata used by provider catalog persistence and strict model validation.

#### Scenario: OpenAI provider lists models from configured endpoint
- **WHEN** OpenAI provider preflight runs with a context endpoint and bearer token
- **THEN** it SHALL call `<endpoint>/models` and map returned model identifiers into provider model descriptors

#### Scenario: OpenAI model discovery maps normalized metadata
- **WHEN** OpenAI model discovery returns capability-relevant metadata fields
- **THEN** the provider SHALL map available fields into normalized model type and input/output support
- **AND** unknown extra fields SHALL be preserved as raw metadata for forward compatibility

#### Scenario: OpenAI ID-only responses remain valid
- **WHEN** OpenAI model discovery returns only minimal fields (for example model ID)
- **THEN** the provider SHALL still emit valid normalized model entries with deterministic defaults

#### Scenario: Missing bearer token fails OpenAI preflight
- **WHEN** OpenAI provider preflight is invoked without a bearer token in context
- **THEN** it SHALL fail preflight and SHALL NOT silently fallback to unauthenticated calls
