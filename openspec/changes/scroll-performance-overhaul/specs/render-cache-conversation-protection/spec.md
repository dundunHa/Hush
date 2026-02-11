## MODIFIED Requirements

### Requirement: RenderCache capacity supports multi-conversation workloads
The RenderCache MUST have a capacity of at least 256 entries to sustain render results across multiple recently-visited conversations without excessive eviction. The internal LRU data structure MUST provide O(1) time complexity for all cache operations (get, set, touch, evict). The cache MUST provide a `peek` method that returns a cached value without updating LRU ordering.

#### Scenario: Capacity accommodates 4 conversations with 15 assistant messages each
- **WHEN** 4 different conversations each contribute 15 cached render outputs at the same width and style
- **THEN** the RenderCache SHALL retain all 60 entries without eviction

#### Scenario: Capacity is configurable at construction time
- **WHEN** a RenderCache is constructed with a custom capacity value
- **THEN** the cache SHALL use that value as its maximum entry count

#### Scenario: Cache get operation is O(1)
- **WHEN** `get(_:)` is called on a cache with N entries
- **THEN** the lookup and LRU touch SHALL complete in O(1) time
- **AND** SHALL NOT use linear search over an array

#### Scenario: Cache set operation is O(1) amortized
- **WHEN** `set(_:output:)` is called on a cache at capacity
- **THEN** the insertion and any necessary eviction SHALL complete in O(1) amortized time
- **AND** SHALL NOT use linear search to find eviction candidates

#### Scenario: Peek returns value without updating LRU order
- **WHEN** `peek(_:)` is called with a key that exists in the cache
- **THEN** the cached value SHALL be returned
- **AND** the entry's position in the LRU eviction order SHALL NOT change

#### Scenario: Peek returns nil for missing keys
- **WHEN** `peek(_:)` is called with a key that does not exist in the cache
- **THEN** nil SHALL be returned

### Requirement: RenderCache provides conversation-aware eviction protection
The RenderCache MUST support marking cache entries as protected for a given conversation ID. When eviction is necessary, the cache MUST prefer evicting unprotected entries before protected entries.

#### Scenario: Protected entries survive eviction when unprotected entries exist
- **WHEN** the cache is at capacity and a new entry is inserted
- **AND** the least-recently-used entry is protected for a conversation
- **AND** there exists an unprotected entry in the cache
- **THEN** the cache SHALL evict the least-recently-used unprotected entry instead

#### Scenario: Protected entries are evicted when no unprotected entries remain
- **WHEN** the cache is at capacity and all entries are protected
- **AND** a new entry is inserted
- **THEN** the cache SHALL evict the least-recently-used entry regardless of protection status

#### Scenario: An entry protected by multiple conversations remains protected until all protections are removed
- **WHEN** an entry is marked protected for conversation A and conversation B
- **AND** protection is removed for conversation A
- **THEN** the entry SHALL still be considered protected (by conversation B)

#### Scenario: Protection can be cleared for a conversation
- **WHEN** `clearProtection(conversationID:)` is called
- **THEN** all entries protected solely by that conversation SHALL lose their protection
- **AND** entries also protected by other conversations SHALL remain protected

### Requirement: All RenderCache and prewarm access runs on @MainActor
All access to RenderCache (read, write, protection operations) and all prewarm rendering MUST execute on `@MainActor` to prevent data races. Prewarm work MUST use cooperative priority (`Task(priority: .utility)`) to avoid blocking user interaction.

#### Scenario: Prewarm executes on @MainActor
- **WHEN** any prewarm path is triggered
- **THEN** the render work SHALL execute on the `@MainActor`
- **AND** SHALL NOT use `Task.detached` or any non-MainActor-isolated execution context

#### Scenario: Prewarm at utility priority yields to user interaction
- **WHEN** prewarm is running and a user-initiated action occurs (typing, clicking, switching)
- **THEN** the user action SHALL be processed without waiting for prewarm to complete

## ADDED Requirements

### Requirement: MathRenderCache provides O(1) LRU operations
The MathRenderCache MUST use an internal data structure that provides O(1) time complexity for get, set, touch, and evict operations. It MUST also provide a `peek` method.

#### Scenario: Math cache get operation is O(1)
- **WHEN** `get(_:)` is called on a MathRenderCache with N entries
- **THEN** the lookup and LRU touch SHALL complete in O(1) time

#### Scenario: Math cache peek returns value without updating LRU order
- **WHEN** `peek(_:)` is called with a key that exists in the MathRenderCache
- **THEN** the cached image SHALL be returned
- **AND** the entry's position in the LRU eviction order SHALL NOT change

### Requirement: Lookahead prewarm scan uses peek instead of get
When `makeLookaheadPrewarmCandidates()` checks whether messages are already cached, it MUST use `peek` (or `cachedOutput` via a non-touching path) to avoid updating LRU order during scroll-driven scans. The peek path MUST be exposed through the full call chain: `RenderCache.peek` → `MessageContentRenderer.peekCachedOutput` → `MessageRenderRuntime.peekCachedOutput`.

#### Scenario: Prewarm candidate scan does not touch LRU order
- **WHEN** `makeLookaheadPrewarmCandidates()` checks multiple messages against the cache
- **THEN** it SHALL use a cache lookup method that does NOT update LRU ordering
- **AND** frequently-scrolled-past messages SHALL NOT be artificially promoted in eviction order

#### Scenario: Peek is available via MessageRenderRuntime
- **WHEN** any caller needs to check cache existence without updating LRU
- **THEN** `MessageRenderRuntime.peekCachedOutput(for:)` SHALL delegate to `MessageContentRenderer.peekCachedOutput(for:)` which delegates to `RenderCache.peek(_:)`
