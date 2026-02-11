## MODIFIED Requirements

### Requirement: Rendering never crashes and degrades gracefully
The system MUST NOT crash due to malformed Markdown, invalid Unicode, or unsupported constructs. When a construct cannot be rendered, the system MUST fall back to a readable representation of the original source. During dual-track streaming, fast-track plain text updates MUST NOT interfere with slow-track rich rendering. The RenderController's own `streamingCoalesceInterval` SHALL remain at 50ms (unchanged); the 200ms throttle is applied only at the RequestCoordinator input layer.

#### Scenario: Malformed Markdown does not crash
- **WHEN** an assistant message contains malformed Markdown (e.g. unclosed fences, broken tables, unmatched delimiters)
- **THEN** the system SHALL still render a readable message and SHALL NOT crash

#### Scenario: Partial streaming content does not crash
- **WHEN** an assistant message is updated during streaming and the current partial content ends with incomplete constructs (e.g. an unclosed code fence or an unclosed math delimiter)
- **THEN** the system SHALL still render a readable message and SHALL NOT crash

#### Scenario: RenderController coalesce interval unchanged
- **WHEN** a streaming render request arrives at RenderController
- **THEN** RenderController SHALL coalesce using its existing 50ms `streamingCoalesceInterval`
- **AND** this interval SHALL NOT be modified by the dual-track change

#### Scenario: Slow-track rich render replaces fast-track plain text
- **WHEN** the slow-track triggers cell.configure during streaming
- **AND** the RenderController completes a rich render
- **THEN** the rendered rich output SHALL replace any fast-track plain text currently displayed via the Combine sink
- **AND** no visual glitch or crash SHALL occur

#### Scenario: Fast-track plain text does not block slow-track rich render
- **WHEN** the fast-track has set plain text on the cell body label
- **AND** the slow-track triggers a rich render via RenderController
- **THEN** the RenderController's Combine sink SHALL overwrite the plain text with the rich attributed string
- **AND** the sink callback SHALL verify the render result matches the current message (fingerprint/messageID guard)

#### Scenario: Configure respects anti-regression during streaming
- **WHEN** slow-track's cell.configure Phase 1 runs during streaming
- **AND** the incoming model content is shorter than what fast-track has already displayed (`content.count < streamingDisplayedLength`)
- **AND** both current and incoming `isStreaming` are true
- **THEN** the Phase 1 plain text write SHALL be skipped
- **AND** RenderController SHALL still be triggered for rich rendering

#### Scenario: Configure allows final-state overwrite
- **WHEN** slow-track's cell.configure runs with `isStreaming == false`
- **THEN** the Phase 1 plain text write SHALL proceed unconditionally
- **AND** `streamingDisplayedLength` SHALL be reset to 0
