import AppKit
import SwiftMath

/// Renders LaTeX math strings to images via SwiftMath.
/// Falls back to styled source text on failure.
final class MathRenderer {
    // MARK: - Dependencies

    private let cache: MathRenderCache

    // MARK: - Init

    init(cache: MathRenderCache) {
        self.cache = cache
    }

    // MARK: - Public Interface

    /// Render a LaTeX math string to an `NSTextAttachment` image.
    /// Returns `nil` if rendering fails (caller should use fallback).
    func renderToAttachment(
        latex: String,
        displayMode: Bool,
        fontSize: CGFloat,
        textColor: NSColor,
        maxWidth: CGFloat
    ) -> NSTextAttachment? {
        let normalizedLatex = normalizeLatex(latex)
        guard !normalizedLatex.isEmpty else {
            RenderDebug.log("[Math] Skip empty latex segment")
            return nil
        }

        let key = MathRenderCache.makeKey(
            latex: normalizedLatex,
            displayMode: displayMode,
            fontSize: fontSize,
            color: textColor,
            maxWidth: maxWidth
        )

        if let cached = cache.get(key) {
            let modeStr = displayMode ? "block" : "inline"
            RenderDebug.log("[Math] Cache hit mode=\(modeStr) latex=\(RenderDebug.preview(normalizedLatex, limit: 160))")
            return makeAttachment(image: cached, displayMode: displayMode, fontSize: fontSize)
        }

        guard let image = renderToImage(
            latex: normalizedLatex,
            displayMode: displayMode,
            fontSize: fontSize,
            textColor: textColor,
            maxWidth: maxWidth
        ) else {
            return nil
        }

        cache.set(key, image: image)
        return makeAttachment(image: image, displayMode: displayMode, fontSize: fontSize)
    }

    /// Build a styled fallback for failed math rendering.
    func fallbackAttributedString(
        latex: String,
        displayMode: Bool,
        style: RenderStyle
    ) -> NSAttributedString {
        let prefix = displayMode ? "⚠︎ " : ""
        let display = "\(prefix)\(latex)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: style.codeFont,
            .foregroundColor: style.mathFallbackColor,
            .backgroundColor: style.codeBackgroundColor
        ]
        return NSAttributedString(string: display, attributes: attrs)
    }

    // MARK: - Private

    private func normalizeLatex(_ latex: String) -> String {
        var normalized = latex.trimmingCharacters(in: .whitespacesAndNewlines)

        // SwiftMath does not recognize \dots aliases; normalize to plain ellipsis.
        let replacements: [(String, String)] = [
            ("\\dots", "..."),
            ("\\ldots", "..."),
            ("\\cdots", "..."),
            ("−", "-"),
            ("–", "-"),
            ("—", "-")
        ]
        for (from, to) in replacements {
            normalized = normalized.replacingOccurrences(of: from, with: to)
        }

        if normalized != latex.trimmingCharacters(in: .whitespacesAndNewlines) {
            RenderDebug.log(
                "[Math] Normalized latex from=\(RenderDebug.preview(latex, limit: 180)) to=\(RenderDebug.preview(normalized, limit: 180))"
            )
        }
        return normalized
    }

    private func renderToImage(
        latex: String,
        displayMode: Bool,
        fontSize: CGFloat,
        textColor: NSColor,
        maxWidth: CGFloat
    ) -> NSImage? {
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.fontSize = fontSize
        label.textColor = textColor
        label.labelMode = displayMode ? .display : .text
        label.latex = latex

        if let error = label.error {
            let modeStr = displayMode ? "block" : "inline"
            let msg = "[Math] Parse failed mode=\(modeStr) error=\(error.localizedDescription) "
                + "latex=\(RenderDebug.preview(latex, limit: 200))"
            RenderDebug.log(msg)
            return nil
        }

        label.layoutSubtreeIfNeeded()

        // MTMathUILabel on macOS reports size via fittingSize.
        var measured = label.fittingSize
        if measured.width <= 0 || measured.height <= 0 {
            measured = label.intrinsicContentSize
        }
        guard measured.width > 0, measured.height > 0 else {
            let modeStr = displayMode ? "block" : "inline"
            let fitting = "\(label.fittingSize.width)x\(label.fittingSize.height)"
            let intrinsic = "\(label.intrinsicContentSize.width)x\(label.intrinsicContentSize.height)"
            RenderDebug.log("[Math] Invalid size mode=\(modeStr) fitting=\(fitting) intrinsic=\(intrinsic)")
            return nil
        }

        let widthCap = min(max(maxWidth, 1), 2000)
        let size = NSSize(
            width: min(measured.width, widthCap),
            height: min(measured.height, 500)
        )
        label.frame = NSRect(origin: .zero, size: size)

        // Render to bitmap
        guard let bitmapRep = label.bitmapImageRepForCachingDisplay(in: label.bounds) else {
            RenderDebug.log("[Math] Failed to build bitmap rep for latex=\(RenderDebug.preview(latex, limit: 200))")
            return nil
        }
        label.cacheDisplay(in: label.bounds, to: bitmapRep)

        let image = NSImage(size: size)
        image.addRepresentation(bitmapRep)
        let modeStr = displayMode ? "block" : "inline"
        let sizeStr = "\(Int(size.width))x\(Int(size.height))"
        RenderDebug.log("[Math] Rendered mode=\(modeStr) size=\(sizeStr) latex=\(RenderDebug.preview(latex, limit: 120))")
        return image
    }

    private func makeAttachment(
        image: NSImage,
        displayMode: Bool,
        fontSize: CGFloat
    ) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.image = image

        // Align baseline for inline math
        let height = image.size.height
        let width = image.size.width
        let yOffset = displayMode ? 0 : -(height - fontSize) / 2
        attachment.bounds = CGRect(x: 0, y: yOffset, width: width, height: height)

        return attachment
    }
}
