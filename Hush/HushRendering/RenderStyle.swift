import AppKit

/// AppKit-based style snapshot used by the renderer.
/// Bridged from HushTypography / HushColors at the SwiftUI layer.
struct RenderStyle: Equatable {
    let bodyFont: NSFont
    let bodyBoldFont: NSFont
    let bodyItalicFont: NSFont
    let heading1Font: NSFont
    let heading2Font: NSFont
    let heading3Font: NSFont
    let codeFont: NSFont
    let codeFontSmall: NSFont

    let bodyColor: NSColor
    let headingColor: NSColor
    let codeColor: NSColor
    let codeBackgroundColor: NSColor
    let linkColor: NSColor
    let blockquoteColor: NSColor
    let blockquoteBarColor: NSColor
    let mathFallbackColor: NSColor
    let tableHeaderColor: NSColor
    let tableBorderColor: NSColor

    // MARK: - Paragraph Spacing

    let paragraphSpacing: CGFloat
    let headingSpacing: CGFloat
    let codeBlockSpacing: CGFloat
    let listIndent: CGFloat

    // MARK: - Factory

    static func appDefault(fontSettings: AppFontSettings = .default) -> RenderStyle {
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
            bodyColor: .white,
            headingColor: .white,
            codeColor: NSColor(red: 0.90, green: 0.85, blue: 0.75, alpha: 1.0),
            codeBackgroundColor: NSColor(white: 1.0, alpha: 0.08),
            linkColor: NSColor.systemCyan,
            blockquoteColor: NSColor(white: 1.0, alpha: 0.62),
            blockquoteBarColor: NSColor(white: 1.0, alpha: 0.20),
            mathFallbackColor: NSColor(red: 0.70, green: 0.80, blue: 0.95, alpha: 1.0),
            tableHeaderColor: NSColor(white: 1.0, alpha: 0.85),
            tableBorderColor: NSColor(white: 1.0, alpha: 0.20),
            paragraphSpacing: 8,
            headingSpacing: 12,
            codeBlockSpacing: 20,
            listIndent: 20
        )
    }

    static func resolvedFonts(for fontSettings: AppFontSettings) -> ResolvedFonts {
        ResolvedFonts(
            body: HushFontResolver.contentFont(settings: fontSettings, referenceSize: 14),
            bodyBold: HushFontResolver.contentFont(settings: fontSettings, referenceSize: 14, weight: .bold),
            bodyItalic: HushFontResolver.contentFont(settings: fontSettings, referenceSize: 14, italic: true),
            heading1: HushFontResolver.contentFont(settings: fontSettings, referenceSize: 22.4, weight: .semibold),
            heading2: HushFontResolver.contentFont(settings: fontSettings, referenceSize: 18.2, weight: .semibold),
            heading3: HushFontResolver.contentFont(settings: fontSettings, referenceSize: 15.4, weight: .semibold),
            code: HushFontResolver.monospacedFont(settings: fontSettings, referenceSize: 12.6),
            codeSmall: HushFontResolver.monospacedFont(settings: fontSettings, referenceSize: 10.71)
        )
    }

    /// Style identity hash for cache keying.
    nonisolated var cacheKey: Int {
        var hasher = Hasher()
        hasher.combine(bodyFont.fontName)
        hasher.combine(bodyFont.pointSize)
        hasher.combine(bodyBoldFont.fontName)
        hasher.combine(bodyBoldFont.pointSize)
        hasher.combine(bodyItalicFont.fontName)
        hasher.combine(bodyItalicFont.pointSize)
        hasher.combine(heading1Font.fontName)
        hasher.combine(heading1Font.pointSize)
        hasher.combine(heading2Font.fontName)
        hasher.combine(heading2Font.pointSize)
        hasher.combine(heading3Font.fontName)
        hasher.combine(heading3Font.pointSize)
        hasher.combine(codeFont.fontName)
        hasher.combine(codeFont.pointSize)
        hasher.combine(codeFontSmall.fontName)
        hasher.combine(codeFontSmall.pointSize)

        hasher.combine(bodyColor)
        hasher.combine(headingColor)
        hasher.combine(codeColor)
        hasher.combine(codeBackgroundColor)
        hasher.combine(linkColor)
        hasher.combine(blockquoteColor)
        hasher.combine(blockquoteBarColor)
        hasher.combine(mathFallbackColor)
        hasher.combine(tableHeaderColor)
        hasher.combine(tableBorderColor)

        hasher.combine(paragraphSpacing)
        hasher.combine(headingSpacing)
        hasher.combine(codeBlockSpacing)
        hasher.combine(listIndent)
        return hasher.finalize()
    }
}

extension RenderStyle {
    struct ResolvedFonts {
        let body: NSFont
        let bodyBold: NSFont
        let bodyItalic: NSFont
        let heading1: NSFont
        let heading2: NSFont
        let heading3: NSFont
        let code: NSFont
        let codeSmall: NSFont
    }
}
