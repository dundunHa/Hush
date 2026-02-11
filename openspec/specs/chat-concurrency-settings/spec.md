## ADDED Requirements

### Requirement: Concurrency limit setting is user-configurable with safe defaults
The system MUST provide a settings control for global concurrent running request limit `N` with default value 3.

#### Scenario: Fresh install uses default concurrency
- **WHEN** app settings are initialized without prior persisted value
- **THEN** global concurrent running request limit SHALL default to 3

#### Scenario: User updates concurrency setting
- **WHEN** user changes concurrency limit in settings
- **THEN** scheduler SHALL apply the new limit for subsequent scheduling decisions

### Requirement: Concurrency setting is durably persisted and restored
The system MUST persist the configured `N` and restore it after restart.

#### Scenario: Restart restores configured N
- **WHEN** user sets a non-default `N`, exits app, and reopens app
- **THEN** restored settings SHALL contain that configured `N`

### Requirement: Only N is exposed in this iteration
Advanced scheduler constants are out of scope for settings UI in this change.

#### Scenario: Settings UI omits T/K controls
- **WHEN** user opens settings related to concurrency
- **THEN** UI SHALL expose only `N`
- **AND** SHALL NOT expose anti-starvation parameters `T` or `K`
