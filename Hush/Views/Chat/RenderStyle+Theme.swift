import AppKit
import SwiftUI

extension RenderStyle {
    // MARK: - Theme Bridge

    static func fromTheme() -> RenderStyle {
        let bodySize: CGFloat = NSFont.systemFontSize
        let body = NSFont.systemFont(ofSize: bodySize)
        let bodyBold = NSFont.boldSystemFont(ofSize: bodySize)
        let bodyItalic: NSFont = {
            let descriptor = body.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: bodySize) ?? body
        }()
        let monoSize = bodySize * 0.9
        let mono = NSFont.monospacedSystemFont(ofSize: monoSize, weight: .regular)
        let monoSmall = NSFont.monospacedSystemFont(ofSize: monoSize * 0.85, weight: .regular)

        return RenderStyle(
            bodyFont: body,
            bodyBoldFont: bodyBold,
            bodyItalicFont: bodyItalic,
            heading1Font: NSFont.systemFont(ofSize: bodySize * 1.6, weight: .semibold),
            heading2Font: NSFont.systemFont(ofSize: bodySize * 1.3, weight: .semibold),
            heading3Font: NSFont.systemFont(ofSize: bodySize * 1.1, weight: .semibold),
            codeFont: mono,
            codeFontSmall: monoSmall,
            bodyColor: NSColor(HushColors.markdownBody),
            headingColor: NSColor(HushColors.markdownHeading),
            codeColor: NSColor(HushColors.markdownCode),
            codeBackgroundColor: NSColor(HushColors.markdownCodeBackground),
            linkColor: NSColor(HushColors.markdownLink),
            blockquoteColor: NSColor(HushColors.markdownBlockquote),
            blockquoteBarColor: NSColor(HushColors.markdownBlockquoteBar),
            mathFallbackColor: NSColor(HushColors.markdownMathFallback),
            tableHeaderColor: NSColor(HushColors.markdownTableHeader),
            tableBorderColor: NSColor(HushColors.markdownTableBorder),
            paragraphSpacing: HushSpacing.sm,
            headingSpacing: HushSpacing.md,
            codeBlockSpacing: HushSpacing.xl,
            listIndent: HushSpacing.xl
        )
    }
}
