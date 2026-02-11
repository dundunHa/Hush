import AppKit

/// AppKit-based style snapshot used by the renderer.
/// Bridged from HushTypography / HushColors at the SwiftUI layer.
struct RenderStyle: Equatable, Sendable {
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

    static func appDefault() -> RenderStyle {
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

    /// Style identity hash for cache keying.
    nonisolated var cacheKey: Int {
        var hasher = Hasher()
        hasher.combine(bodyFont.pointSize)
        hasher.combine(bodyBoldFont.pointSize)
        hasher.combine(bodyItalicFont.pointSize)
        hasher.combine(heading1Font.pointSize)
        hasher.combine(heading2Font.pointSize)
        hasher.combine(heading3Font.pointSize)
        hasher.combine(codeFont.pointSize)
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
