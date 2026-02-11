# Capability: appkit-chat-single-path

## Purpose
TBD: Consolidation of chat rendering to a single AppKit path.

## Requirements

### Requirement: Chat detail pane uses AppKit single rendering path
The system MUST render conversation content in `ChatDetailPane` through the AppKit hot-scene pool path only, and MUST NOT branch between SwiftUI and AppKit chat routes at runtime.

#### Scenario: Active conversation renders through pool representable
- **WHEN** the chat detail pane is composed
- **THEN** the conversation list area SHALL be hosted by `HotScenePoolRepresentable`
- **AND** the composer area SHALL remain attached below the pool-hosted conversation view

#### Scenario: Runtime route switch is not available
- **WHEN** the app starts with any chat-related environment flags
- **THEN** the chat route SHALL remain AppKit single-path
- **AND** changing old route flags SHALL NOT switch rendering to a SwiftUI chat route

### Requirement: Legacy SwiftUI chat-route artifacts are removed from chat routing
The system MUST remove legacy SwiftUI chat-route entry points from chat routing so they cannot be selected by production code paths.

#### Scenario: Chat route does not reference SwiftUI stage or bubble path
- **WHEN** chat routing logic is evaluated
- **THEN** it SHALL NOT select `ChatScrollStage` as a conversation rendering route
- **AND** it SHALL NOT instantiate `MessageBubble` as the primary chat row rendering path

### Requirement: Operational docs and run scripts align with single-path behavior
The system MUST keep operator-facing docs and run scripts consistent with the single-path chat route contract.

#### Scenario: Run script output reflects current route behavior
- **WHEN** developers run project launch helpers
- **THEN** launch messaging SHALL NOT claim runtime chat route switching support
- **AND** debug guidance SHALL describe AppKit single-path behavior only
