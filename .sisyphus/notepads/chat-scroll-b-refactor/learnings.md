# Tail-Follow StateMachine Refactor - Learnings

## Architecture Reference Pattern

From `ChatWindowing.swift`:
- Input struct with all context parameters
- Output struct for results
- `enum Namespace { static func reduce(...) }` pattern
- All structs: `Equatable, Sendable`
- Pure functions, no side effects

## Current Thresholds (Must Preserve)

| Constant | Value | Location |
|----------|-------|----------|
| `pinnedDistanceThreshold` | 80pt | ChatScrollStage:25 |
| `streamingBreakawayThreshold` | 260pt | ChatScrollStage:26 |
| `postStreamingPinnedGraceInterval` | 0.6s | ChatScrollStage:27 |
| `streamingScrollCoalesceInterval` | 0.1s | RenderConstants:53 |

## Key Constraints

1. **No sleep/TTL**: Use event latches only (generation-based)
2. **Keep Task.yield()**: `requestScrollToBottom` must retain `pendingScrollTask` cancel + `await Task.yield()` pattern
3. **User messages ALWAYS scroll**: Even when scrolled up
4. **User scroll up → stop following**: Immediately

## Scroll Event Sources

### SwiftUI Route
- `BottomAnchorPreferenceKey` → `updatePinnedState()` (geometric distance)
- `onChange(of: messages.count)` → `handleMessagesChanged()`
- `onChange(of: messages.last?.content)` → streaming updates
- `onChange(of: isActiveConversationSending)` → streaming finished

### AppKit Route (MessageTableView)
- `boundsDidChangeNotification` on `scrollView.contentView`
- Only 80pt threshold, missing streaming protection/grace period

## NSViewRepresentable Pattern for Telemetry Bridge

From `WindowCloseObserver` (HushApp.swift):
- Coordinator holds `observation: Any?`
- `DispatchQueue.main.async` to get enclosing view/window
- `deinit { removeObserver }`

From `MessageTableView`:
- `clipView.postsBoundsChangedNotifications = true`
- Observe `NSView.boundsDidChangeNotification`
- Calculate `distanceFromBottom = docHeight - (bounds.origin.y + bounds.height)`

## Test Patterns

From `ChatScrollStageAutoScrollPolicyTests.swift`:
- Test `resolveCountChangeAutoScrollAction` pure function
- Cover: switchLoad, newAssistant, newUser, prependedOlder, scrolledUp suppression
- Use `#expect(action == .expected)` assertions

## Migration Strategy

1. Extract state machine as pure value type (following ChatWindowing pattern)
2. Keep `requestScrollToBottom` in View layer (needs SwiftUI proxy)
3. State machine outputs `ScrollAction` enum → View executes
4. AppKit route later aligns to same state machine
