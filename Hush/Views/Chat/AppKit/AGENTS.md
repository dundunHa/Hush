# Views/Chat/AppKit

AppKit hot-path for chat rendering/switching. `NSTableView`-based message scene + hot-scene pool for fast conversation switch. Includes fast-track streaming and message tracing.

## Structure

```
ConversationViewController.swift  # Per-conversation controller; applies snapshot + marks layout-ready once
MessageTableView.swift            # NSTableView host; tail-follow state machine + prewarm metrics + teardown safety (4979 lines)
MessageTableView+FastTrack.swift  # Fast-track streaming extension — minimal-latency delta application
MessageTraceSheet.swift           # Debug sheet showing per-message render trace info
HotScenePool.swift                # @MainActor LRU pool; switch hit/miss + eviction
HotScenePoolController.swift      # Parent controller; attaches/hides scenes + resize cleanup debounce
HotScenePoolRepresentable.swift   # SwiftUI bridge for pool controller
```

## Where to Look

| Task | File |
|------|------|
| Switch A->B render path | `HotScenePoolController.switchToActiveConversation` |
| Hot/cold hit policy | `HotScenePool.switchTo` + `evictColdest` |
| Visible row rendering + follow-tail | `MessageTableView.apply` + tail-follow helpers |
| Fast-track streaming deltas | `MessageTableView+FastTrack.swift` — low-latency streaming path |
| One-time switch layout-ready signal | `ConversationViewController.applyConversationState` |
| Message trace debugging | `MessageTraceSheet.swift` |

## Conventions

- **MainActor confinement**: Controllers/pool/table run on `@MainActor`.
- **Hide, don't destroy, on switch**: Previous hot scene stays attached but hidden unless evicted.
- **Eviction safety**: Before removal, call `cancelVisibleRenderWorkForEviction()` and clear render-runtime protection.
- **Table teardown safety**: `deinit` explicitly nils `dataSource/delegate/documentView` to avoid callback-after-teardown crashes.
- **Switch generation discipline**: Generation changes trigger `.conversationSwitched` tail-follow event and one-time layout-ready mark.
- **Fast-track path**: `MessageTableView+FastTrack` provides minimal-latency streaming updates, bypassing full table reload for append-only deltas.
- **Surface style awareness**: `MessageTableView` adapts layout based on `ConversationSurfaceStyle` (main window vs Quick Bar).

## Anti-Patterns

- **Never replace this path with SwiftUI `List`** for chat stream/switch flows.
- **Never clear active scene output before replacement is ready** (causes flash/regression).
- **Never perform AppKit scene mutations off main actor**.
- **Never keep stale scene attached after eviction** — remove from superview and parent.
