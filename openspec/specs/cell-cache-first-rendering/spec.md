## ADDED Requirements

### Requirement: Assistant message cell uses cached rich text when available
When configuring an assistant message cell, the system MUST check RenderCache before setting any text content. If a cached render output exists for the message's content, width, and style, the cell MUST display the cached rich text directly without first displaying plain text.

#### Scenario: Cache hit displays rich text immediately
- **WHEN** a MessageTableCellView is configured for an assistant message
- **AND** the RenderCache contains a cached output for that message's content hash, width, and style
- **THEN** the cell SHALL set the cached attributedString as its text content
- **AND** SHALL NOT first display a plain-text fallback

#### Scenario: Cache miss falls back to existing plain-then-rich path
- **WHEN** a MessageTableCellView is configured for an assistant message
- **AND** the RenderCache does not contain a cached output for that message
- **THEN** the cell SHALL display plain text as a fallback
- **AND** SHALL create a RenderController and request async rich rendering

#### Scenario: Streaming messages always use existing path
- **WHEN** a MessageTableCellView is configured for a streaming assistant message (isStreaming == true)
- **THEN** the cell SHALL NOT attempt cache-first lookup
- **AND** SHALL use the existing streaming render path with RenderController coalescing

#### Scenario: Non-assistant messages retain current rendering behavior
- **WHEN** a MessageTableCellView is configured for a user, system, or tool message
- **THEN** the cell SHALL render the message using its current rendering path (plain text)
- **AND** SHALL NOT perform any RenderCache lookup

### Requirement: SwiftUI MessageBubble achieves cache-first rendering via RenderController
The RenderController's non-streaming requestRender path MUST synchronously apply cached output when available, ensuring the first @Published currentOutput value is non-nil for cached content.

#### Scenario: RenderController applies cached output synchronously
- **WHEN** `requestRender` is called with non-streaming content that is in the RenderCache
- **THEN** `currentOutput` SHALL be set synchronously within the same call
- **AND** no scheduler work item SHALL be enqueued

#### Scenario: View observing currentOutput sees rich text on first read
- **WHEN** a view subscribes to RenderController's `$currentOutput` publisher
- **AND** the content was cache-hit during `requestRender`
- **THEN** the first emitted value SHALL be the cached rich output (not nil)

### Requirement: AppKit message cell configuration deduplicates identical render inputs
The system MUST deduplicate repeated `MessageTableCellView.configure` calls when render-relevant inputs are unchanged, to avoid redundant render subscriptions and requests.

#### Scenario: Identical configure input is skipped
- **WHEN** a cell receives a configure call with the same message identity, render generation, streaming state, content fingerprint, and width/style fingerprint as the previous configure call
- **THEN** the cell SHALL skip issuing a new render request
- **AND** SHALL preserve the currently displayed output

#### Scenario: Render-relevant change bypasses deduplication
- **WHEN** any render-relevant input changes (including content fingerprint, streaming flag, render generation, or width/style fingerprint)
- **THEN** the cell SHALL execute the normal configure path
- **AND** SHALL request or apply updated rendering output
