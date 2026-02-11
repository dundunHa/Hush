## ADDED Requirements

### Requirement: Row height pre-computation cache for assistant messages
The system MUST maintain a row height cache that stores pre-computed heights for rendered assistant messages. The cache key MUST be `(contentHash, width, styleKey)` — identical to `RenderCache.CacheKey`. Heights MUST be computed at render completion time using `NSAttributedString.boundingRect(with:options:context:)`, not during scroll.

#### Scenario: Height is cached when render completes
- **WHEN** a non-streaming render completes and the output is stored in RenderCache
- **THEN** the system SHALL also compute and store the row height for that content at the rendered width
- **AND** the height SHALL be computed using `NSAttributedString.boundingRect(with:options:context:)` with the same width constraint used by the cell

#### Scenario: Cell configure uses cached height on cache-first hit
- **WHEN** a MessageTableCellView is configured for a non-streaming assistant message
- **AND** the RenderCache contains a cached output
- **AND** the row height cache contains a cached height for the same key
- **THEN** the cell SHALL set `bodyLabel.cachedIntrinsicHeight` (via CachedHeightTextField subclass) to the cached value
- **AND** the NSTextField's `intrinsicContentSize` override SHALL return the cached height without triggering TextKit synchronous layout

#### Scenario: Height cache miss falls back to normal auto-sizing
- **WHEN** the row height cache does not contain a height for the current message
- **THEN** `bodyLabel.cachedIntrinsicHeight` SHALL be set to nil
- **AND** the cell SHALL rely on `usesAutomaticRowHeights` and NSTextField's default `intrinsicContentSize` as before

#### Scenario: Height cache is invalidated on width change
- **WHEN** the container width changes (window resize)
- **THEN** height cache entries at the old width SHALL be naturally invalid (different cache key)
- **AND** SHALL NOT be returned for queries at the new width

#### Scenario: Height cache lifecycle is tied to RenderCache
- **WHEN** a RenderCache entry is evicted
- **THEN** the corresponding height cache entry (same key) SHALL also be removed
- **AND** the height cache SHALL NOT accumulate stale entries beyond RenderCache capacity

### Requirement: Dead code removal — AttributedTextView.swift
The file `Hush/Views/Chat/AttributedTextView.swift` MUST be deleted as it has zero external references and is unused dead code from a prior SwiftUI-to-AppKit migration.

#### Scenario: AttributedTextView.swift is removed
- **WHEN** the change is applied
- **THEN** `Hush/Views/Chat/AttributedTextView.swift` SHALL be deleted from the project
- **AND** the Xcode project file SHALL not reference it
- **AND** the build SHALL succeed without it
