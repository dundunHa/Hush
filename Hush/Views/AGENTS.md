# Views

SwiftUI + AppKit hybrid view layer. Chat uses NSTableView (AppKit) for performance; everything else is SwiftUI.

## Structure

```
Views/
  Chat/
    AppKit/
      HotScenePoolRepresentable.swift   # SwiftUI bridge to the AppKit hot-scene-pool host
      HotScenePoolController.swift      # AppKit parent controller managing attached hot scenes
      HotScenePool.swift                # LRU pool for conversation scenes
      ConversationViewController.swift  # NSViewController hosting NSTableView for messages
      MessageTableView.swift            # NSTableView subclass for message list
    ComposerDock.swift                  # Message input area (text field + send button)
  Sidebar/                              # Conversation list sidebar
  TopBar/                               # Window top bar controls
  Settings/
    AgentSettingsView.swift             # Agent preset management
    ProviderSettingsView.swift          # Provider configuration + credential entry
    PromptSettingsView.swift            # Prompt template editor
    GeneralSettingsView.swift           # App-level preferences
    DataSettingsView.swift              # Data export/import/erase
  PreviewSupport.swift                  # SwiftUI preview fixtures (316 lines)
```

## Where to Look

| Task | File |
|------|------|
| Message display/layout | `Chat/AppKit/MessageTableView.swift` + `MessageTableCellView` |
| Scroll behavior | `Chat/AppKit/MessageTableView.swift` + `TailFollowStateMachine` |
| Message input | `ComposerDock.swift` |
| AppKit message list | `Chat/AppKit/HotScenePoolRepresentable.swift` + `HotScenePoolController.swift` + `ConversationViewController.swift` |
| Settings UI | `Settings/<Feature>SettingsView.swift` |
| Preview data | `PreviewSupport.swift` — shared fixtures for all previews |

## Conventions

- **@EnvironmentObject**: All views access `AppContainer` via `@EnvironmentObject`.
- **Theme tokens only**: Colors from `HushColors`, spacing from `HushSpacing`, fonts from `HushTypography`. Never hardcode.
- **Dark mode only**: Single `AppTheme.dark`. No light mode support.
- **AppKit for chat**: chat conversation rendering is AppKit single-path through `HotScenePoolRepresentable` and pooled `ConversationViewController` scenes.
- **Tail follow**: auto-scroll/follow semantics are handled by `TailFollowStateMachine` in `MessageTableView`.

## Anti-Patterns

- **Never hardcode colors/spacing/fonts** — always use `HushColors`, `HushSpacing`, `HushTypography`.
- **Never use system colors** — custom dark palette only.
- **Never replace NSTableView with SwiftUI List** for chat — performance critical with streaming.
- **Never access AppContainer directly** — use `@EnvironmentObject`, not init injection in views.
