## ADDED Requirements

### Requirement: Provider Model Metadata Is Normalized to a Common Schema
The system MUST normalize provider-specific model metadata into a common schema that includes model type and supported input/output modalities.

#### Scenario: Provider metadata maps into normalized fields
- **WHEN** a provider returns model metadata payloads
- **THEN** the system SHALL map each model to normalized fields including `modelType`, supported inputs, and supported outputs

#### Scenario: Missing remote fields use safe defaults
- **WHEN** provider metadata omits optional capability fields
- **THEN** the system SHALL assign deterministic default values (for example `unknown`) rather than failing mapping

### Requirement: Normalization Preserves Provider-Specific Details
The system MUST preserve non-normalized provider metadata for forward compatibility and diagnostics.

#### Scenario: Unknown metadata fields are retained
- **WHEN** provider payload contains additional fields not represented in the normalized schema
- **THEN** the system SHALL preserve those fields in provider-scoped raw metadata storage
- **AND** normalized mapping SHALL continue without failure

### Requirement: Capability Introspection Is Provider-Scoped
The system MUST fetch and map model capabilities in the context of a specific provider profile.

#### Scenario: Same model ID across providers is not conflated
- **WHEN** two providers expose the same model identifier string
- **THEN** the system SHALL keep metadata records scoped by provider ID
- **AND** capability mapping for one provider SHALL NOT override the other

### Requirement: OpenAI Capability Mapping Is Backward Compatible
The system MUST map OpenAI model discovery responses to the normalized schema without regressing existing model list functionality.

#### Scenario: OpenAI ID-only payload still yields usable model entry
- **WHEN** OpenAI model discovery response provides only model identifiers
- **THEN** the system SHALL still produce valid normalized model entries with deterministic defaults

#### Scenario: OpenAI richer payload populates normalized fields
- **WHEN** OpenAI model discovery response includes additional capability-relevant metadata
- **THEN** the system SHALL map available fields into normalized model type and modality support
