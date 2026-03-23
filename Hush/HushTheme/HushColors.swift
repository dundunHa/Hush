import SwiftUI

struct HushThemePalette {
    let rootBackground: Color
    let sidebarBackground: Color
    let workspaceChromeBackground: Color
    let cardBackground: Color
    let composerBackground: Color
    let composerEditorBackground: Color
    let separator: Color
    let subtleStroke: Color
    let splitPaneEdgeStroke: Color
    let splitPaneShadow: Color
    let sidebarGlassTint: Color
    let sidebarGlassStroke: Color
    let sidebarGlassHighlight: Color
    let sidebarGlassShadow: Color
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
    let quickBarSurface: Color
    let quickBarSurfaceStroke: Color
    let quickBarPrimaryText: Color
    let quickBarSecondaryText: Color
    let quickBarTertiaryText: Color
    let quickBarControlFill: Color
    let quickBarControlFillHover: Color
    let quickBarControlForeground: Color
    let quickBarControlMuted: Color
    let quickBarButtonFill: Color
    let quickBarButtonForeground: Color
    let quickBarDisabledButtonFill: Color
    let quickBarDisabledButtonForeground: Color
}

enum HushColors {
    static func palette(for theme: AppTheme) -> HushThemePalette {
        switch theme {
        case .graphiteGlass:
            return graphiteGlassPalette
        case .lightGlass:
            return lightGlassPalette
        case .ivoryGlass:
            return ivoryGlassPalette
        }
    }

    private static let graphiteGlassPalette = HushThemePalette(
        rootBackground: Color(hex: 0x2E2F31),
        sidebarBackground: Color(hex: 0x1F252D, opacity: 0.28),
        workspaceChromeBackground: Color(hex: 0x37383B),
        cardBackground: Color(hex: 0x252A32),
        composerBackground: Color(hex: 0x313741),
        composerEditorBackground: Color(hex: 0x363634),
        separator: Color(hex: 0x6C7179, opacity: 0.20),
        subtleStroke: Color(hex: 0x7A8591, opacity: 0.22),
        splitPaneEdgeStroke: Color(hex: 0xFFFFFF, opacity: 0.06),
        splitPaneShadow: Color(hex: 0x04060A, opacity: 0.28),
        sidebarGlassTint: Color(hex: 0x5E6A77, opacity: 0.06),
        sidebarGlassStroke: Color(hex: 0xFFFFFF, opacity: 0.12),
        sidebarGlassHighlight: Color(hex: 0xFFFFFF, opacity: 0.14),
        sidebarGlassShadow: Color(hex: 0x04060A, opacity: 0.20),
        primaryText: Color(hex: 0xF4F6F8),
        secondaryText: Color(hex: 0xB7BFC8),
        tertiaryText: Color(hex: 0x8C95A0),
        accent: Color(hex: 0x7EAEEA),
        accentMutedBackground: Color(hex: 0x415262, opacity: 0.46),
        accentMutedStroke: Color(hex: 0x9FBCDE, opacity: 0.30),
        hoverFill: Color(hex: 0xFFFFFF, opacity: 0.06),
        hoverStroke: Color(hex: 0xFFFFFF, opacity: 0.12),
        selectionFill: Color(hex: 0xFFFFFF, opacity: 0.10),
        selectionStroke: Color(hex: 0xFFFFFF, opacity: 0.22),
        softFill: Color(hex: 0xFFFFFF, opacity: 0.025),
        softFillStrong: Color(hex: 0xFFFFFF, opacity: 0.055),
        primaryActionBackground: Color(hex: 0x7EAEEA),
        primaryActionForeground: Color(hex: 0x101924),
        disabledActionBackground: Color(hex: 0xFFFFFF, opacity: 0.12),
        disabledActionForeground: Color(hex: 0x0C1016, opacity: 0.35),
        destructiveActionBackground: Color(hex: 0xD66F6A),
        destructiveActionForeground: Color(hex: 0xFFFFFF),
        controlForeground: Color(hex: 0xF0F4F8),
        controlForegroundMuted: Color(hex: 0xD0D7DE, opacity: 0.70),
        debugOverlayBackground: Color(hex: 0x11161E, opacity: 0.70),
        debugOverlayForeground: Color(hex: 0xF4F6F8),
        errorText: Color(hex: 0xF2A39E),
        successText: Color(hex: 0x82D9A1),
        badgeRunning: Color(hex: 0x82D9A1),
        badgeQueued: Color(hex: 0xE1B56A),
        badgeUnread: Color(hex: 0x7EAEEA),
        userBubble: Color(hex: 0x35495D, opacity: 0.50),
        userBubbleStroke: Color(hex: 0x8AAEDB, opacity: 0.18),
        toolBubble: Color(hex: 0x403730, opacity: 0.32),
        toolBubbleStroke: Color(hex: 0xA98D6B, opacity: 0.20),
        systemBubble: Color(hex: 0xFFFFFF, opacity: 0.045),
        systemBubbleStroke: Color(hex: 0xFFFFFF, opacity: 0.08),
        markdownBody: Color(hex: 0xE6EAEE),
        markdownHeading: Color(hex: 0xF8FAFC),
        markdownCode: Color(hex: 0xDDE5EF),
        markdownCodeBackground: Color(hex: 0x232C37),
        markdownLink: Color(hex: 0xB3CBE5),
        markdownBlockquote: Color(hex: 0xB8C0C8),
        markdownBlockquoteBar: Color(hex: 0x5B6775),
        markdownMathFallback: Color(hex: 0xB3CBE5),
        markdownTableHeader: Color(hex: 0xF0F4F8),
        markdownTableBorder: Color(hex: 0x596573),
        codeBlockBackground: Color(hex: 0x3E3E3B),
        codeBlockBorder: Color(hex: 0x556272),
        codeBlockSeparator: Color(hex: 0x647282),
        composerShellTop: Color(hex: 0x363634),
        composerShellBottom: Color(hex: 0x363634),
        composerShellStroke: Color(hex: 0xFFFFFF, opacity: 0.14),
        quickBarSurface: Color(hex: 0x2D333D),
        quickBarSurfaceStroke: Color(hex: 0x7E8B9C),
        quickBarPrimaryText: Color(hex: 0xF3F6FA),
        quickBarSecondaryText: Color(hex: 0xC2CBD4),
        quickBarTertiaryText: Color(hex: 0x95A2B0),
        quickBarControlFill: Color(hex: 0x445163, opacity: 0.48),
        quickBarControlFillHover: Color(hex: 0x536278, opacity: 0.76),
        quickBarControlForeground: Color(hex: 0xF3F6FA),
        quickBarControlMuted: Color(hex: 0xB5C0CB),
        quickBarButtonFill: Color(hex: 0x7295C3),
        quickBarButtonForeground: Color(hex: 0x0F1722),
        quickBarDisabledButtonFill: Color(hex: 0x404A56),
        quickBarDisabledButtonForeground: Color(hex: 0x93A0AE)
    )

    private static let lightGlassPalette = HushThemePalette(
        rootBackground: Color(hex: 0xEEF3F8),
        sidebarBackground: Color(hex: 0xF8FBFF, opacity: 0.44),
        workspaceChromeBackground: Color(hex: 0xF7FAFD),
        cardBackground: Color(hex: 0xFFFFFF, opacity: 0.86),
        composerBackground: Color(hex: 0xFFFFFF, opacity: 0.80),
        composerEditorBackground: Color(hex: 0xF8FBFF),
        separator: Color(hex: 0xD6DEE9, opacity: 0.84),
        subtleStroke: Color(hex: 0xD4DDEA, opacity: 0.90),
        splitPaneEdgeStroke: Color(hex: 0xB8C8DA),
        splitPaneShadow: Color(hex: 0x081120, opacity: 0.08),
        sidebarGlassTint: Color(hex: 0xCFE0F5, opacity: 0.18),
        sidebarGlassStroke: Color(hex: 0xFFFFFF, opacity: 0.36),
        sidebarGlassHighlight: Color(hex: 0xFFFFFF, opacity: 0.42),
        sidebarGlassShadow: Color(hex: 0x334865, opacity: 0.14),
        primaryText: Color(hex: 0x172033),
        secondaryText: Color(hex: 0x5B677B),
        tertiaryText: Color(hex: 0x8B96A8),
        accent: Color(hex: 0x2E6FEA),
        accentMutedBackground: Color(hex: 0xDCE8FF),
        accentMutedStroke: Color(hex: 0xB9CEFF),
        hoverFill: Color(hex: 0x1A2538, opacity: 0.04),
        hoverStroke: Color(hex: 0x42506A, opacity: 0.12),
        selectionFill: Color(hex: 0xDCE8FF, opacity: 0.82),
        selectionStroke: Color(hex: 0x9CB9F7),
        softFill: Color(hex: 0x182339, opacity: 0.035),
        softFillStrong: Color(hex: 0x182339, opacity: 0.06),
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
        composerShellTop: Color(hex: 0xFFFFFF, opacity: 0.96),
        composerShellBottom: Color(hex: 0xEEF4FB, opacity: 0.92),
        composerShellStroke: Color(hex: 0xD6E0EC),
        quickBarSurface: Color(hex: 0xF6FAFE),
        quickBarSurfaceStroke: Color(hex: 0xD6E1EE),
        quickBarPrimaryText: Color(hex: 0x172235),
        quickBarSecondaryText: Color(hex: 0x59667A),
        quickBarTertiaryText: Color(hex: 0x8A97AA),
        quickBarControlFill: Color(hex: 0xDCE8F7, opacity: 0.72),
        quickBarControlFillHover: Color(hex: 0xCFE1F6, opacity: 0.92),
        quickBarControlForeground: Color(hex: 0x1C2940),
        quickBarControlMuted: Color(hex: 0x55657C),
        quickBarButtonFill: Color(hex: 0x2E6FEA),
        quickBarButtonForeground: Color(hex: 0xFFFFFF),
        quickBarDisabledButtonFill: Color(hex: 0xD8E0EA),
        quickBarDisabledButtonForeground: Color(hex: 0x728095)
    )

    private static let ivoryGlassPalette = HushThemePalette(
        rootBackground: Color(hex: 0xF4EEE3),
        sidebarBackground: Color(hex: 0xFBF4E9, opacity: 0.46),
        workspaceChromeBackground: Color(hex: 0xF7F0E4),
        cardBackground: Color(hex: 0xFFF9F0, opacity: 0.88),
        composerBackground: Color(hex: 0xFCF5EA, opacity: 0.82),
        composerEditorBackground: Color(hex: 0xFFFDF8),
        separator: Color(hex: 0xD8CCBA, opacity: 0.86),
        subtleStroke: Color(hex: 0xD8CBB9, opacity: 0.92),
        splitPaneEdgeStroke: Color(hex: 0xC6B39B),
        splitPaneShadow: Color(hex: 0x6A543A, opacity: 0.10),
        sidebarGlassTint: Color(hex: 0xF0DDC3, opacity: 0.20),
        sidebarGlassStroke: Color(hex: 0xFFF8EE, opacity: 0.34),
        sidebarGlassHighlight: Color(hex: 0xFFFDF8, opacity: 0.40),
        sidebarGlassShadow: Color(hex: 0x7D6548, opacity: 0.16),
        primaryText: Color(hex: 0x2D2822),
        secondaryText: Color(hex: 0x6A6156),
        tertiaryText: Color(hex: 0x94897C),
        accent: Color(hex: 0xC67843),
        accentMutedBackground: Color(hex: 0xF1E0CB),
        accentMutedStroke: Color(hex: 0xE1BE98),
        hoverFill: Color(hex: 0x5F4A31, opacity: 0.05),
        hoverStroke: Color(hex: 0x8B7257, opacity: 0.16),
        selectionFill: Color(hex: 0xE9DAC7, opacity: 0.84),
        selectionStroke: Color(hex: 0xD0AF8A),
        softFill: Color(hex: 0x6A543B, opacity: 0.04),
        softFillStrong: Color(hex: 0x6A543B, opacity: 0.065),
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
        composerShellTop: Color(hex: 0xFFF9F1, opacity: 0.97),
        composerShellBottom: Color(hex: 0xF5ECE0, opacity: 0.93),
        composerShellStroke: Color(hex: 0xDCCFBE),
        quickBarSurface: Color(hex: 0xFBF3E7),
        quickBarSurfaceStroke: Color(hex: 0xE2D1BD),
        quickBarPrimaryText: Color(hex: 0x2E2923),
        quickBarSecondaryText: Color(hex: 0x6A6055),
        quickBarTertiaryText: Color(hex: 0x96897B),
        quickBarControlFill: Color(hex: 0xE9D9C5, opacity: 0.72),
        quickBarControlFillHover: Color(hex: 0xE1CDB5, opacity: 0.92),
        quickBarControlForeground: Color(hex: 0x3B3229),
        quickBarControlMuted: Color(hex: 0x75695D),
        quickBarButtonFill: Color(hex: 0xC67843),
        quickBarButtonForeground: Color(hex: 0xFFF8F1),
        quickBarDisabledButtonFill: Color(hex: 0xDED4C7),
        quickBarDisabledButtonForeground: Color(hex: 0x8D8275)
    )
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
