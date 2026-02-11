## ADDED Requirements

### Requirement: Messages are stored and updated in conversation-scoped buckets
The in-memory transcript model MUST maintain message collections scoped by conversation ID and MUST project only the active conversation bucket into the chat view.

#### Scenario: Active chat view reads active conversation projection only
- **WHEN** active conversation changes
- **THEN** the chat message list SHALL render messages from the active conversation bucket only

#### Scenario: Background conversation updates do not overwrite active view projection
- **WHEN** a non-active conversation receives request deltas
- **THEN** those deltas SHALL update only that conversation bucket
- **AND** SHALL NOT replace or mutate the currently displayed active conversation message list

### Requirement: Request output routing is bound to request conversation ownership
Each request session MUST carry a fixed `conversationId` captured at submission time, and all delta/persistence writes MUST route by this ownership.

#### Scenario: Deltas route to owning conversation regardless of active switch
- **WHEN** user switches active conversation while a request is still streaming
- **THEN** subsequent deltas for that request SHALL continue writing to the request’s owning conversation bucket and durable records

#### Scenario: First delta creates assistant draft in owning conversation
- **WHEN** a request receives its first delta
- **THEN** the assistant draft message SHALL be created under the request’s owning conversation
- **AND** subsequent deltas SHALL update the same assistant message correlated by request ID
