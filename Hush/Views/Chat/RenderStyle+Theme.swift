import AppKit
import SwiftUI

extension RenderStyle {
    // MARK: - Theme Bridge

    static func fromTheme(
        _ theme: AppTheme = .dark,
        fontSettings: AppFontSettings = .default
    ) -> RenderStyle {
        fromPalette(HushColors.palette(for: theme), fontSettings: fontSettings)
    }

    static func fromPalette(
        _ palette: HushThemePalette,
        fontSettings: AppFontSettings = .default
    ) -> RenderStyle {
        let fonts = resolvedFonts(for: fontSettings)

        return RenderStyle(
            bodyFont: fonts.body,
            bodyBoldFont: fonts.bodyBold,
            bodyItalicFont: fonts.bodyItalic,
            heading1Font: fonts.heading1,
            heading2Font: fonts.heading2,
            heading3Font: fonts.heading3,
            codeFont: fonts.code,
            codeFontSmall: fonts.codeSmall,
            bodyColor: NSColor(palette.markdownBody),
            headingColor: NSColor(palette.markdownHeading),
            codeColor: NSColor(palette.markdownCode),
            codeBackgroundColor: NSColor(palette.markdownCodeBackground),
            linkColor: NSColor(palette.markdownLink),
            blockquoteColor: NSColor(palette.markdownBlockquote),
            blockquoteBarColor: NSColor(palette.markdownBlockquoteBar),
            mathFallbackColor: NSColor(palette.markdownMathFallback),
            tableHeaderColor: NSColor(palette.markdownTableHeader),
            tableBorderColor: NSColor(palette.markdownTableBorder),
            paragraphSpacing: HushSpacing.sm,
            headingSpacing: HushSpacing.md,
            codeBlockSpacing: HushSpacing.xl,
            listIndent: HushSpacing.xl
        )
    }
}
