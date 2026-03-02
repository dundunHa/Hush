import SwiftUI

enum HushColors {
    // Backgrounds
    static let rootBackground = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let sidebarBackground = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let cardBackground = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let composerBackground = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let composerEditorBackground = Color.black.opacity(0.24)

    // Borders & Separators
    static let separator = Color.white.opacity(0.10)
    static let subtleStroke = Color.white.opacity(0.12)

    // Shadows
    static let splitPaneEdgeStroke = Color.white.opacity(0.14)
    static let splitPaneShadow = Color.black.opacity(0.28)

    /// Text
    static let secondaryText = Color.white.opacity(0.62)

    // Feedback
    static let errorText = Color.red.opacity(0.90)
    static let successText = Color.green.opacity(0.90)

    // Activity Badges
    static let badgeRunning = Color.green.opacity(0.90)
    static let badgeQueued = Color.orange.opacity(0.80)
    static let badgeUnread = Color.blue.opacity(0.80)

    // Bubbles
    static let userBubble = Color.blue.opacity(0.30)
    static let userBubbleStroke = Color.blue.opacity(0.46)
    static let toolBubble = Color.orange.opacity(0.20)
    static let toolBubbleStroke = Color.orange.opacity(0.32)
    static let systemBubble = Color.gray.opacity(0.24)
    static let systemBubbleStroke = Color.white.opacity(0.16)

    // Markdown Rendering
    static let markdownBody = Color.white
    static let markdownHeading = Color.white
    static let markdownCode = Color(red: 0.90, green: 0.85, blue: 0.75)
    static let markdownCodeBackground = Color.white.opacity(0.08)
    static let markdownLink = Color.cyan
    static let markdownBlockquote = Color.white.opacity(0.62)
    static let markdownBlockquoteBar = Color.white.opacity(0.20)
    static let markdownMathFallback = Color(red: 0.70, green: 0.80, blue: 0.95)
    static let markdownTableHeader = Color.white.opacity(0.85)
    static let markdownTableBorder = Color.white.opacity(0.20)
}
