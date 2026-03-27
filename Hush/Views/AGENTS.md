# Views

SwiftUI + AppKit hybrid view layer. Chat uses NSTableView (AppKit) for performance; everything else is SwiftUI. Includes Quick Bar (floating panel) with its own conversation surface.

## Structure

```
Views/
  RootView.swift                        # Main window root (sidebar + chat detail)
  ThemeChrome.swift                     # Window chrome + theme application (832 lines)
  AppThemeEnvironment.swift             # Theme environment key injection
  Chat/
    ChatDetailPane.swift                # Active conversation view container
    ComposerDock.swift                  # Message input area (text field + send button, 519 lines)
    ChatConfigPopover.swift             # Model/temperature config popover (512 lines)
    TypingIndicator.swift               # Animated typing dots
    RenderStyle+Theme.swift             # RenderStyle theme bridge
    AppKit/                             # NSTableView-based chat (see AppKit/AGENTS.md)
    QuickBar/
      QuickBarPanelView.swift           # Quick Bar SwiftUI root view
      QuickBarComposer.swift            # Quick Bar message input (604 lines)
      QuickBarComposerSupport.swift     # Composer helper types
      QuickConversationSurface.swift    # Quick Bar message display surface
  Sidebar/
    ConversationSidebarView.swift       # Conversation list sidebar
  TopBar/
    UnifiedTopBar.swift                 # Window top bar controls
  Settings/
    SettingsWorkspaceView.swift         # Settings window root
    SettingsContentColumn.swift         # Settings content layout
    AgentSettingsView.swift             # Agent preset management (718 lines)
    ProviderSettingsView.swift          # Provider configuration + credential entry (1735 lines)
    PromptLibraryView.swift             # Prompt template editor
    GeneralSettingsView.swift           # App-level preferences
    DataSettingsView.swift              # Data export/import/erase
    ArchivedThreadsSettingsView.swift   # Archived conversation management
    QuickBarShortcutRecorder.swift      # Hotkey recording UI for Quick Bar
  Previews/
    PreviewSupport.swift                # SwiftUI preview fixtures
    ChatComponentPreviews.swift         # Chat component preview definitions
```

## Where to Look

| Task | File |
|------|------|
| Message display/layout | `Chat/AppKit/MessageTableView.swift` (see AppKit/AGENTS.md) |
| Scroll behavior | `Chat/AppKit/MessageTableView.swift` + `TailFollowStateMachine` |
| Message input (main) | `Chat/ComposerDock.swift` |
| Message input (Quick Bar) | `Chat/QuickBar/QuickBarComposer.swift` |
| Quick Bar UI | `Chat/QuickBar/QuickBarPanelView.swift` + `QuickConversationSurface.swift` |
| Settings UI | `Settings/<Feature>SettingsView.swift` |
| Window chrome/theme | `ThemeChrome.swift` |
| Preview data | `Previews/PreviewSupport.swift` — shared fixtures for all previews |

## Conventions

- **@EnvironmentObject**: All views access `AppContainer` via `@EnvironmentObject`.
- **Theme tokens only**: Colors from `HushColors`, spacing from `HushSpacing`, fonts from `HushTypography`. Never hardcode.
- **Dark mode only**: Single `AppTheme.dark`. No light mode support.
- **ConversationSurfaceStyle**: Distinguishes main window (`.mainChat`) vs Quick Bar (`.quickBar`) rendering contexts.
- **AppKit for chat**: Chat conversation rendering is AppKit single-path through `HotScenePoolRepresentable` and pooled `ConversationViewController` scenes.
- **Tail follow**: Auto-scroll/follow semantics handled by `TailFollowStateMachine` in `MessageTableView`.
- **Quick Bar**: Separate composer (`QuickBarComposer`) and conversation surface (`QuickConversationSurface`) optimized for compact floating panel.

## Anti-Patterns

- **Never hardcode colors/spacing/fonts** — always use `HushColors`, `HushSpacing`, `HushTypography`.
- **Never use system colors** — custom dark palette only.
- **Never replace NSTableView with SwiftUI List** for chat — performance critical with streaming.
- **Never access AppContainer directly** — use `@EnvironmentObject`, not init injection in views.
