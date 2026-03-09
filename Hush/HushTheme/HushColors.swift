import SwiftUI

struct HushThemePalette {
    let rootBackground: Color
    let sidebarBackground: Color
    let cardBackground: Color
    let composerBackground: Color
    let composerEditorBackground: Color
    let separator: Color
    let subtleStroke: Color
    let splitPaneEdgeStroke: Color
    let splitPaneShadow: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let accent: Color
    let accentMutedBackground: Color
    let accentMutedStroke: Color
    let hoverFill: Color
    let hoverStroke: Color
    let selectionFill: Color
    let selectionStroke: Color
    let softFill: Color
    let softFillStrong: Color
    let primaryActionBackground: Color
    let primaryActionForeground: Color
    let disabledActionBackground: Color
    let disabledActionForeground: Color
    let destructiveActionBackground: Color
    let destructiveActionForeground: Color
    let controlForeground: Color
    let controlForegroundMuted: Color
    let debugOverlayBackground: Color
    let debugOverlayForeground: Color
    let errorText: Color
    let successText: Color
    let badgeRunning: Color
    let badgeQueued: Color
    let badgeUnread: Color
    let userBubble: Color
    let userBubbleStroke: Color
    let toolBubble: Color
    let toolBubbleStroke: Color
    let systemBubble: Color
    let systemBubbleStroke: Color
    let markdownBody: Color
    let markdownHeading: Color
    let markdownCode: Color
    let markdownCodeBackground: Color
    let markdownLink: Color
    let markdownBlockquote: Color
    let markdownBlockquoteBar: Color
    let markdownMathFallback: Color
    let markdownTableHeader: Color
    let markdownTableBorder: Color
    let codeBlockBackground: Color
    let codeBlockBorder: Color
    let codeBlockSeparator: Color
    let composerShellTop: Color
    let composerShellBottom: Color
    let composerShellStroke: Color
}

enum HushColors {
    private static var currentTheme: AppTheme = .dark

    static func apply(theme: AppTheme) {
        currentTheme = theme
    }

    static func palette(for theme: AppTheme) -> HushThemePalette {
        switch theme {
        case .dark:
            return darkPalette
        case .light:
            return lightPalette
        case .readPaper:
            return readPaperPalette
        }
    }

    private static let darkPalette = HushThemePalette(
        rootBackground: Color(hex: 0x0B0D12),
        sidebarBackground: Color(hex: 0x10141B),
        cardBackground: Color(hex: 0x171C26),
        composerBackground: Color(hex: 0x121720),
        composerEditorBackground: Color(hex: 0x0A0D12, opacity: 0.58),
        separator: Color(hex: 0x323A47, opacity: 0.65),
        subtleStroke: Color(hex: 0x445063, opacity: 0.58),
        splitPaneEdgeStroke: Color(hex: 0x5A667B, opacity: 0.58),
        splitPaneShadow: Color(hex: 0x000000, opacity: 0.30),
        primaryText: Color(hex: 0xF5F7FB),
        secondaryText: Color(hex: 0xC0C8D6),
        tertiaryText: Color(hex: 0x8893A5),
        accent: Color(hex: 0x5AA2FF),
        accentMutedBackground: Color(hex: 0x183459, opacity: 0.80),
        accentMutedStroke: Color(hex: 0x4D86CB, opacity: 0.85),
        hoverFill: Color(hex: 0xFFFFFF, opacity: 0.06),
        hoverStroke: Color(hex: 0xFFFFFF, opacity: 0.14),
        selectionFill: Color(hex: 0xFFFFFF, opacity: 0.10),
        selectionStroke: Color(hex: 0x7BAAF2, opacity: 0.42),
        softFill: Color(hex: 0xFFFFFF, opacity: 0.05),
        softFillStrong: Color(hex: 0xFFFFFF, opacity: 0.08),
        primaryActionBackground: Color(hex: 0x5AA2FF),
        primaryActionForeground: Color(hex: 0x07111F),
        disabledActionBackground: Color(hex: 0xFFFFFF, opacity: 0.18),
        disabledActionForeground: Color(hex: 0x000000, opacity: 0.38),
        destructiveActionBackground: Color(hex: 0xE05C58),
        destructiveActionForeground: Color(hex: 0xFFFFFF),
        controlForeground: Color(hex: 0xE7ECF5),
        controlForegroundMuted: Color(hex: 0xC5CFDE, opacity: 0.72),
        debugOverlayBackground: Color(hex: 0x06080C, opacity: 0.70),
        debugOverlayForeground: Color(hex: 0xF5F7FB),
        errorText: Color(hex: 0xF28E8A),
        successText: Color(hex: 0x63D08D),
        badgeRunning: Color(hex: 0x63D08D),
        badgeQueued: Color(hex: 0xE0A24A),
        badgeUnread: Color(hex: 0x5AA2FF),
        userBubble: Color(hex: 0x204C81, opacity: 0.58),
        userBubbleStroke: Color(hex: 0x5AA2FF, opacity: 0.46),
        toolBubble: Color(hex: 0x6B4C22, opacity: 0.36),
        toolBubbleStroke: Color(hex: 0xC58E49, opacity: 0.40),
        systemBubble: Color(hex: 0x7F8CA0, opacity: 0.18),
        systemBubbleStroke: Color(hex: 0xE0E6F1, opacity: 0.18),
        markdownBody: Color(hex: 0xE8ECF3),
        markdownHeading: Color(hex: 0xF8FAFD),
        markdownCode: Color(hex: 0xD9E5FA),
        markdownCodeBackground: Color(hex: 0x202937),
        markdownLink: Color(hex: 0x7CB8FF),
        markdownBlockquote: Color(hex: 0xAFB8C6),
        markdownBlockquoteBar: Color(hex: 0x546072),
        markdownMathFallback: Color(hex: 0x9BC2FF),
        markdownTableHeader: Color(hex: 0xF4F7FB),
        markdownTableBorder: Color(hex: 0x505C6E),
        codeBlockBackground: Color(hex: 0x1A2230),
        codeBlockBorder: Color(hex: 0x3E495B),
        codeBlockSeparator: Color(hex: 0x455165),
        composerShellTop: Color(hex: 0x1A202B),
        composerShellBottom: Color(hex: 0x131923),
        composerShellStroke: Color(hex: 0xFFFFFF, opacity: 0.14)
    )

    private static let lightPalette = HushThemePalette(
        rootBackground: Color(hex: 0xF5F7FB),
        sidebarBackground: Color(hex: 0xEDF2F7),
        cardBackground: Color(hex: 0xFFFFFF),
        composerBackground: Color(hex: 0xFFFFFF),
        composerEditorBackground: Color(hex: 0xF6F9FC),
        separator: Color(hex: 0xDCE3EC),
        subtleStroke: Color(hex: 0xD2DAE6),
        splitPaneEdgeStroke: Color(hex: 0xC6D1DE),
        splitPaneShadow: Color(hex: 0x081120, opacity: 0.08),
        primaryText: Color(hex: 0x172033),
        secondaryText: Color(hex: 0x5B677B),
        tertiaryText: Color(hex: 0x8B96A8),
        accent: Color(hex: 0x2E6FEA),
        accentMutedBackground: Color(hex: 0xDCE8FF),
        accentMutedStroke: Color(hex: 0xB9CEFF),
        hoverFill: Color(hex: 0x1A2538, opacity: 0.04),
        hoverStroke: Color(hex: 0x42506A, opacity: 0.12),
        selectionFill: Color(hex: 0xDCE8FF),
        selectionStroke: Color(hex: 0x9CB9F7),
        softFill: Color(hex: 0x182339, opacity: 0.04),
        softFillStrong: Color(hex: 0x182339, opacity: 0.07),
        primaryActionBackground: Color(hex: 0x2E6FEA),
        primaryActionForeground: Color(hex: 0xFFFFFF),
        disabledActionBackground: Color(hex: 0xD7DEE8),
        disabledActionForeground: Color(hex: 0x6E7787),
        destructiveActionBackground: Color(hex: 0xD95A57),
        destructiveActionForeground: Color(hex: 0xFFFFFF),
        controlForeground: Color(hex: 0x1A2436),
        controlForegroundMuted: Color(hex: 0x49566C),
        debugOverlayBackground: Color(hex: 0x0B1628, opacity: 0.58),
        debugOverlayForeground: Color(hex: 0xFFFFFF),
        errorText: Color(hex: 0xC44545),
        successText: Color(hex: 0x1C8A4A),
        badgeRunning: Color(hex: 0x1C8A4A),
        badgeQueued: Color(hex: 0xD38A27),
        badgeUnread: Color(hex: 0x2E6FEA),
        userBubble: Color(hex: 0xDCE8FF),
        userBubbleStroke: Color(hex: 0xB6CBF9),
        toolBubble: Color(hex: 0xF8E6D4),
        toolBubbleStroke: Color(hex: 0xE7C59E),
        systemBubble: Color(hex: 0xEAEFF6),
        systemBubbleStroke: Color(hex: 0xD2DCE7),
        markdownBody: Color(hex: 0x243144),
        markdownHeading: Color(hex: 0x101A2C),
        markdownCode: Color(hex: 0x7C451D),
        markdownCodeBackground: Color(hex: 0xF3F7FB),
        markdownLink: Color(hex: 0x2E6FEA),
        markdownBlockquote: Color(hex: 0x556273),
        markdownBlockquoteBar: Color(hex: 0xD6DFEA),
        markdownMathFallback: Color(hex: 0x355BC6),
        markdownTableHeader: Color(hex: 0x344154),
        markdownTableBorder: Color(hex: 0xD8E0EA),
        codeBlockBackground: Color(hex: 0xF3F7FB),
        codeBlockBorder: Color(hex: 0xD8E0EA),
        codeBlockSeparator: Color(hex: 0xD3DCE7),
        composerShellTop: Color(hex: 0xFFFFFF),
        composerShellBottom: Color(hex: 0xF4F7FB),
        composerShellStroke: Color(hex: 0xD7E0EB)
    )

    private static let readPaperPalette = HushThemePalette(
        rootBackground: Color(hex: 0xF4EFE6),
        sidebarBackground: Color(hex: 0xECE4D7),
        cardBackground: Color(hex: 0xFAF5EC),
        composerBackground: Color(hex: 0xF8F1E5),
        composerEditorBackground: Color(hex: 0xFFFDF8),
        separator: Color(hex: 0xD9CFBE),
        subtleStroke: Color(hex: 0xD1C5B1),
        splitPaneEdgeStroke: Color(hex: 0xC5B8A3),
        splitPaneShadow: Color(hex: 0x6A543A, opacity: 0.10),
        primaryText: Color(hex: 0x2D2822),
        secondaryText: Color(hex: 0x6A6156),
        tertiaryText: Color(hex: 0x94897C),
        accent: Color(hex: 0xC67843),
        accentMutedBackground: Color(hex: 0xF1E0CB),
        accentMutedStroke: Color(hex: 0xE1BE98),
        hoverFill: Color(hex: 0x5F4A31, opacity: 0.05),
        hoverStroke: Color(hex: 0x8B7257, opacity: 0.16),
        selectionFill: Color(hex: 0xE9DAC7),
        selectionStroke: Color(hex: 0xD0AF8A),
        softFill: Color(hex: 0x6A543B, opacity: 0.05),
        softFillStrong: Color(hex: 0x6A543B, opacity: 0.08),
        primaryActionBackground: Color(hex: 0xC67843),
        primaryActionForeground: Color(hex: 0xFFF8F1),
        disabledActionBackground: Color(hex: 0xDDD4C7),
        disabledActionForeground: Color(hex: 0x8E8477),
        destructiveActionBackground: Color(hex: 0xB85B45),
        destructiveActionForeground: Color(hex: 0xFFF8F1),
        controlForeground: Color(hex: 0x3B3229),
        controlForegroundMuted: Color(hex: 0x72665A),
        debugOverlayBackground: Color(hex: 0x493826, opacity: 0.62),
        debugOverlayForeground: Color(hex: 0xFFF8F1),
        errorText: Color(hex: 0xB75642),
        successText: Color(hex: 0x3E895A),
        badgeRunning: Color(hex: 0x3E895A),
        badgeQueued: Color(hex: 0xB9833A),
        badgeUnread: Color(hex: 0xC67843),
        userBubble: Color(hex: 0xE6D8C8),
        userBubbleStroke: Color(hex: 0xD8BFA5),
        toolBubble: Color(hex: 0xF2E5D5),
        toolBubbleStroke: Color(hex: 0xE3C8AA),
        systemBubble: Color(hex: 0xEEE6DA),
        systemBubbleStroke: Color(hex: 0xD7CAB9),
        markdownBody: Color(hex: 0x322C25),
        markdownHeading: Color(hex: 0x211C17),
        markdownCode: Color(hex: 0x7B4A20),
        markdownCodeBackground: Color(hex: 0xF0E6D8),
        markdownLink: Color(hex: 0xB56A36),
        markdownBlockquote: Color(hex: 0x746A5F),
        markdownBlockquoteBar: Color(hex: 0xD5C8B7),
        markdownMathFallback: Color(hex: 0xA35E31),
        markdownTableHeader: Color(hex: 0x3A332C),
        markdownTableBorder: Color(hex: 0xD2C3AF),
        codeBlockBackground: Color(hex: 0xF0E6D8),
        codeBlockBorder: Color(hex: 0xD7C8B4),
        codeBlockSeparator: Color(hex: 0xD2C4B1),
        composerShellTop: Color(hex: 0xFBF5EB),
        composerShellBottom: Color(hex: 0xF4ECDF),
        composerShellStroke: Color(hex: 0xD8CCBB)
    )

    private static var currentPalette: HushThemePalette {
        palette(for: currentTheme)
    }

    static var rootBackground: Color {
        currentPalette.rootBackground
    }

    static var sidebarBackground: Color {
        currentPalette.sidebarBackground
    }

    static var cardBackground: Color {
        currentPalette.cardBackground
    }

    static var composerBackground: Color {
        currentPalette.composerBackground
    }

    static var composerEditorBackground: Color {
        currentPalette.composerEditorBackground
    }

    static var separator: Color {
        currentPalette.separator
    }

    static var subtleStroke: Color {
        currentPalette.subtleStroke
    }

    static var splitPaneEdgeStroke: Color {
        currentPalette.splitPaneEdgeStroke
    }

    static var splitPaneShadow: Color {
        currentPalette.splitPaneShadow
    }

    static var primaryText: Color {
        currentPalette.primaryText
    }

    static var secondaryText: Color {
        currentPalette.secondaryText
    }

    static var tertiaryText: Color {
        currentPalette.tertiaryText
    }

    static var accent: Color {
        currentPalette.accent
    }

    static var accentMutedBackground: Color {
        currentPalette.accentMutedBackground
    }

    static var accentMutedStroke: Color {
        currentPalette.accentMutedStroke
    }

    static var hoverFill: Color {
        currentPalette.hoverFill
    }

    static var hoverStroke: Color {
        currentPalette.hoverStroke
    }

    static var selectionFill: Color {
        currentPalette.selectionFill
    }

    static var selectionStroke: Color {
        currentPalette.selectionStroke
    }

    static var softFill: Color {
        currentPalette.softFill
    }

    static var softFillStrong: Color {
        currentPalette.softFillStrong
    }

    static var primaryActionBackground: Color {
        currentPalette.primaryActionBackground
    }

    static var primaryActionForeground: Color {
        currentPalette.primaryActionForeground
    }

    static var disabledActionBackground: Color {
        currentPalette.disabledActionBackground
    }

    static var disabledActionForeground: Color {
        currentPalette.disabledActionForeground
    }

    static var destructiveActionBackground: Color {
        currentPalette.destructiveActionBackground
    }

    static var destructiveActionForeground: Color {
        currentPalette.destructiveActionForeground
    }

    static var controlForeground: Color {
        currentPalette.controlForeground
    }

    static var controlForegroundMuted: Color {
        currentPalette.controlForegroundMuted
    }

    static var debugOverlayBackground: Color {
        currentPalette.debugOverlayBackground
    }

    static var debugOverlayForeground: Color {
        currentPalette.debugOverlayForeground
    }

    static var errorText: Color {
        currentPalette.errorText
    }

    static var successText: Color {
        currentPalette.successText
    }

    static var badgeRunning: Color {
        currentPalette.badgeRunning
    }

    static var badgeQueued: Color {
        currentPalette.badgeQueued
    }

    static var badgeUnread: Color {
        currentPalette.badgeUnread
    }

    static var userBubble: Color {
        currentPalette.userBubble
    }

    static var userBubbleStroke: Color {
        currentPalette.userBubbleStroke
    }

    static var toolBubble: Color {
        currentPalette.toolBubble
    }

    static var toolBubbleStroke: Color {
        currentPalette.toolBubbleStroke
    }

    static var systemBubble: Color {
        currentPalette.systemBubble
    }

    static var systemBubbleStroke: Color {
        currentPalette.systemBubbleStroke
    }

    static var markdownBody: Color {
        currentPalette.markdownBody
    }

    static var markdownHeading: Color {
        currentPalette.markdownHeading
    }

    static var markdownCode: Color {
        currentPalette.markdownCode
    }

    static var markdownCodeBackground: Color {
        currentPalette.markdownCodeBackground
    }

    static var markdownLink: Color {
        currentPalette.markdownLink
    }

    static var markdownBlockquote: Color {
        currentPalette.markdownBlockquote
    }

    static var markdownBlockquoteBar: Color {
        currentPalette.markdownBlockquoteBar
    }

    static var markdownMathFallback: Color {
        currentPalette.markdownMathFallback
    }

    static var markdownTableHeader: Color {
        currentPalette.markdownTableHeader
    }

    static var markdownTableBorder: Color {
        currentPalette.markdownTableBorder
    }

    static var codeBlockBackground: Color {
        currentPalette.codeBlockBackground
    }

    static var codeBlockBorder: Color {
        currentPalette.codeBlockBorder
    }

    static var codeBlockSeparator: Color {
        currentPalette.codeBlockSeparator
    }

    static var composerShellTop: Color {
        currentPalette.composerShellTop
    }

    static var composerShellBottom: Color {
        currentPalette.composerShellBottom
    }

    static var composerShellStroke: Color {
        currentPalette.composerShellStroke
    }
}

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
