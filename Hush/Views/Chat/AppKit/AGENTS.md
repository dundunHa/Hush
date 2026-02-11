# Views/Chat/AppKit

AppKit hot-path for chat rendering/switching. `NSTableView`-based message scene + hot-scene pool for fast conversation switch.

## Structure

```
ConversationViewController.swift  # Per-conversation controller; applies snapshot + marks layout-ready once
MessageTableView.swift            # NSTableView host; tail-follow state machine + prewarm metrics + teardown safety
HotScenePool.swift                # @MainActor LRU pool; switch hit/miss + eviction
HotScenePoolController.swift      # Parent controller; attaches/hides scenes + resize cleanup debounce
HotScenePoolRepresentable.swift   # SwiftUI bridge for pool controller
```

## Where to Look

| Task | File |
|------|------|
| Switch A→B render path | `HotScenePoolController.switchToActiveConversation` |
| Hot/cold hit policy | `HotScenePool.switchTo` + `evictColdest` |
| Visible row rendering + follow-tail | `MessageTableView.apply` + tail-follow helpers |
| One-time switch layout-ready signal | `ConversationViewController.applyConversationState` |

## Conventions

- **MainActor confinement**: controllers/pool/table run on `@MainActor`.
- **Hide, don’t destroy, on switch**: previous hot scene stays attached but hidden unless evicted.
- **Eviction safety**: before removal, call `cancelVisibleRenderWorkForEviction()` and clear render-runtime protection.
- **Table teardown safety**: `deinit` explicitly nils `dataSource/delegate/documentView` to avoid callback-after-teardown crashes.
- **Switch generation discipline**: generation changes trigger `.conversationSwitched` tail-follow event and one-time layout-ready mark.

## Anti-Patterns

- **Never replace this path with SwiftUI `List`** for chat stream/switch flows.
- **Never clear active scene output before replacement is ready** (causes flash/regression).
- **Never perform AppKit scene mutations off main actor**.
- **Never keep stale scene attached after eviction** — remove from superview and parent.
