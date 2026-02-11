## ADDED Requirements

### Requirement: Sidebar shows per-conversation generation activity badges
The sidebar thread list MUST expose per-conversation activity state without requiring users to enter each conversation.

#### Scenario: Running badge for background generation
- **WHEN** a conversation has at least one running request
- **THEN** sidebar row for that conversation SHALL show a running indicator badge

#### Scenario: Queued badge for pending generation
- **WHEN** a conversation has queued requests but no running request
- **THEN** sidebar row for that conversation SHALL show a queued indicator badge

### Requirement: Sidebar displays unread completion for background-finished requests
The system MUST mark background completions as unread until user revisits that conversation and reaches tail.

#### Scenario: Background request completion sets unread completion
- **WHEN** a request completes for a non-active conversation
- **THEN** that conversation SHALL be marked with unread completion indicator in sidebar

#### Scenario: Reading conversation tail clears unread completion
- **WHEN** user switches to that conversation and reaches conversation tail after switch animation
- **THEN** unread completion indicator SHALL be cleared

### Requirement: Sidebar does not provide direct stop action in this change
The sidebar MUST remain status-only for generation control in this iteration.

#### Scenario: Sidebar context menu excludes stop operation
- **WHEN** user opens sidebar thread actions
- **THEN** no stop-generation action SHALL be provided from sidebar
