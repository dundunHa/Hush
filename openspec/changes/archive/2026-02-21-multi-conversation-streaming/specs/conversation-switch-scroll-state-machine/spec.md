## ADDED Requirements

### Requirement: Conversation switch auto-scroll is event-gated, not sleep-gated
Conversation switch bottom-scroll behavior MUST be driven by deterministic switch events and MUST NOT depend on fixed sleep delays.

#### Scenario: Switch scroll waits for snapshot and layout readiness
- **WHEN** a conversation switch generation starts
- **THEN** auto-scroll-to-bottom SHALL execute only after switch snapshot has been applied and target layout is ready for that generation

#### Scenario: No fixed suppression sleep is required
- **WHEN** switch auto-scroll logic is evaluated
- **THEN** the system SHALL NOT require a fixed 300ms sleep-based animation suppression gate to determine switch completion

### Requirement: Switching to any conversation animates to bottom
The system MUST animate to bottom on each conversation switch.

#### Scenario: Switch to conversation with existing messages
- **WHEN** user switches to a conversation containing messages
- **THEN** the scroll view SHALL animate to bottom for that conversation

#### Scenario: Switch to conversation receiving ongoing streaming
- **WHEN** user switches to a conversation that currently has a running request
- **THEN** the view SHALL animate to bottom and continue showing newest streamed content at tail position
