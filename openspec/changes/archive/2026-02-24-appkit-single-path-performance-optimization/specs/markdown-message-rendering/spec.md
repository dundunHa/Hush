## ADDED Requirements

### Requirement: Streaming render optimization preserves responsiveness without changing render semantics
The system MUST reduce redundant streaming render work and main-thread layout churn while preserving existing Markdown, LaTeX, and table rendering semantics.

#### Scenario: Streaming updates avoid full-list relayout bursts
- **WHEN** streaming assistant content updates arrive for an existing message row
- **THEN** the system SHALL update only the necessary row rendering path where safe
- **AND** SHALL avoid unconditional full-list refresh on every streaming tick

#### Scenario: Optimized path preserves rendered output behavior
- **WHEN** performance optimizations are applied to streaming render scheduling
- **THEN** rendered output SHALL remain behaviorally consistent with existing Markdown/LaTeX/table contracts
- **AND** fallback behavior SHALL remain available when optimization preconditions are not met

### Requirement: Prefetch-style prewarm improves near-viewport render readiness
The system MUST support prewarming of near-viewport assistant rows so that entering viewport rows have high cache-hit probability.

#### Scenario: Near-viewport row is prewarmed before visible
- **WHEN** scroll telemetry indicates rows are approaching the visible window
- **THEN** the system SHALL schedule low-priority prewarm for eligible non-streaming assistant rows
- **AND** SHALL skip rows that are already cached
