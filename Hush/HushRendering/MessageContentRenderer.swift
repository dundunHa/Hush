import AppKit
import Markdown

/// Single entry point for rendering assistant message content.
///
/// Encapsulates the full pipeline: Markdown parsing → AST → attributed text,
/// with LaTeX math attachments, table fallbacks, caching, and guardrails.
///
/// Usage:
/// ```swift
/// let renderer = MessageContentRenderer()
/// let output = renderer.render(MessageRenderInput(content: "# Hello", availableWidth: 600))
/// textView.textStorage?.setAttributedString(output.attributedString)
/// ```
@MainActor
final class MessageContentRenderer {
    // MARK: - Dependencies

    private let renderCache: RenderCache
    private let mathCache: MathRenderCache
    private let rowHeightCache: RowHeightCache
    private lazy var mathRenderer = MathRenderer(cache: mathCache)

    #if DEBUG
        private(set) var nonStreamingMissRenderCountForTesting: Int = 0
    #endif

    // MARK: - Init

    init(
        renderCache: RenderCache = RenderCache(),
        mathCache: MathRenderCache = MathRenderCache(),
        rowHeightCache: RowHeightCache = RowHeightCache()
    ) {
        self.renderCache = renderCache
        self.mathCache = mathCache
        self.rowHeightCache = rowHeightCache
        self.renderCache.setOnRemove { [weak rowHeightCache] key in
            rowHeightCache?.remove(key)
        }
    }

    // MARK: - Public Interface

    /// Render message content to an attributed string.
    func render(_ input: MessageRenderInput) -> MessageRenderOutput {
        PerfTrace.measure(
            "render.message",
            fields: [
                "streaming": input.isStreaming ? "true" : "false",
                "chars": "\(input.content.count)",
                "width": "\(Int(input.availableWidth))"
            ]
        ) {
            RenderDebug.log(
                "[Render] Begin chars=\(input.content.count) width=\(Int(input.availableWidth)) streaming=\(input.isStreaming)"
            )
            RenderDebug.log("[Render] Raw: \(RenderDebug.preview(input.content, limit: 500))")

            // Empty content
            guard !input.content.isEmpty else {
                return MessageRenderOutput(
                    attributedString: NSAttributedString(),
                    plainText: "",
                    diagnostics: []
                )
            }

            // Check cache (skip for streaming since content changes rapidly)
            if !input.isStreaming {
                let key = RenderCache.makeKey(
                    content: input.content,
                    width: input.availableWidth,
                    style: input.style
                )
                if let cached = renderCache.get(key) {
                    return cached
                }
            }

            #if DEBUG
                if !input.isStreaming {
                    nonStreamingMissRenderCountForTesting += 1
                }
            #endif

            // Guardrail: content length
            let contentToRender: String
            var earlyDiagnostics: [RenderDiagnostic] = []

            if input.content.count > RenderConstants.maxRichRenderLength {
                contentToRender = String(input.content.prefix(RenderConstants.maxRichRenderLength))
                earlyDiagnostics.append(RenderDiagnostic(
                    kind: .guardrailTriggered,
                    message: "Content truncated at \(RenderConstants.maxRichRenderLength) characters"
                ))
            } else {
                contentToRender = input.content
            }

            // Parse → render
            let output = renderMarkdown(
                content: contentToRender,
                input: input,
                extraDiagnostics: earlyDiagnostics
            )

            RenderDebug.log(
                "[Render] End diagnostics=\(output.diagnostics.count) renderedChars=\(output.attributedString.length)"
            )
            let renderedPlain = output.attributedString.string
                .replacingOccurrences(of: "\u{FFFC}", with: "<att>")
            RenderDebug.log(
                "[Render] Plain output (attachments as <att>): \(RenderDebug.preview(renderedPlain, limit: 500))"
            )
            if !output.diagnostics.isEmpty {
                let details = output.diagnostics.map { "\($0.kind.rawValue): \($0.message)" }.joined(separator: " | ")
                RenderDebug.log("[Render] Diagnostics: \(RenderDebug.preview(details, limit: 800))")
            }

            // Cache result (non-streaming only)
            if !input.isStreaming {
                let key = RenderCache.makeKey(
                    content: input.content,
                    width: input.availableWidth,
                    style: input.style
                )
                renderCache.set(key, output: output)
                cacheRowHeight(
                    for: key,
                    attributedString: output.attributedString,
                    width: input.availableWidth
                )
            }

            return output
        }
    }

    /// Returns a cached render output for the given input if present.
    /// Does not trigger rendering work.
    func cachedOutput(for input: MessageRenderInput) -> MessageRenderOutput? {
        guard !input.isStreaming else { return nil }
        let key = RenderCache.makeKey(
            content: input.content,
            width: input.availableWidth,
            style: input.style
        )
        return renderCache.get(key)
    }

    /// Returns a cached render output for the given input if present.
    /// Does not update LRU ordering.
    func peekCachedOutput(for input: MessageRenderInput) -> MessageRenderOutput? {
        guard !input.isStreaming else { return nil }
        let key = RenderCache.makeKey(
            content: input.content,
            width: input.availableWidth,
            style: input.style
        )
        return renderCache.peek(key)
    }

    func cachedRowHeight(for input: MessageRenderInput) -> CGFloat? {
        guard !input.isStreaming else { return nil }
        let key = RenderCache.makeKey(
            content: input.content,
            width: input.availableWidth,
            style: input.style
        )
        return rowHeightCache.value(for: key)
    }

    /// Warms render cache entries for the provided non-streaming inputs.
    func prewarm(inputs: [MessageRenderInput]) async {
        for input in inputs where !input.isStreaming {
            if Task.isCancelled { return }

            if cachedOutput(for: input) == nil {
                _ = render(input)
            }

            if Task.isCancelled { return }
            await Task.yield()
        }
    }

    func protectCacheEntries(for inputs: [MessageRenderInput], conversationID: String) {
        for input in inputs where !input.isStreaming {
            let key = RenderCache.makeKey(
                content: input.content,
                width: input.availableWidth,
                style: input.style
            )
            renderCache.markProtected(key: key, conversationID: conversationID)
        }
    }

    func clearProtection(conversationID: String) {
        renderCache.clearProtection(conversationID: conversationID)
    }

    func clearAllProtections() {
        renderCache.clearAllProtections()
    }

    /// Clear all caches.
    func clearCaches() {
        renderCache.clear()
        mathCache.clear()
        rowHeightCache.clear()
    }

    /// Current cache sizes (for diagnostics/testing).
    var messageCacheCount: Int {
        renderCache.count
    }

    var mathCacheCount: Int {
        mathCache.count
    }

    var rowHeightCacheCount: Int {
        rowHeightCache.count
    }

    // MARK: - Private

    private func renderMarkdown(
        content: String,
        input: MessageRenderInput,
        extraDiagnostics: [RenderDiagnostic]
    ) -> MessageRenderOutput {
        // Parse Markdown AST
        let document = Document(parsing: content, options: [.disableSmartOpts])
        RenderDebug.log("[Render] Markdown blocks=\(document.childCount)")

        // Convert AST → attributed string
        let converter = MarkdownToAttributed(
            style: input.style,
            mathRenderer: mathRenderer,
            maxWidth: input.availableWidth,
            isStreaming: input.isStreaming
        )

        let attributedString: NSAttributedString
        do {
            attributedString = try safeRender(converter: converter, document: document)
        } catch {
            return .plainFallback(content, style: input.style)
        }

        let diagnostics = extraDiagnostics + converter.diagnostics

        return MessageRenderOutput(
            attributedString: attributedString,
            plainText: content,
            diagnostics: diagnostics
        )
    }

    /// Wrapper to catch any unexpected errors during rendering.
    private func safeRender(
        converter: MarkdownToAttributed,
        document: Document
    ) throws -> NSAttributedString {
        // In production, this should never throw. But if the AST walk
        // encounters something unexpected, we catch and fall back.
        converter.convert(document)
    }

    private func cacheRowHeight(
        for key: RenderCache.CacheKey,
        attributedString: NSAttributedString,
        width: CGFloat
    ) {
        // NSTextField-backed rendering can clip by a couple of points vs
        // NSAttributedString.boundingRect; add a small safety buffer.
        var safetyPadding: CGFloat = 4
        if attributedString.length > 0,
           attributedString.attribute(
               .hushCodeBlockLanguage,
               at: attributedString.length - 1,
               effectiveRange: nil
           ) != nil
        {
            // Code blocks draw a padded background that can extend below the last
            // line fragment; reserve a bit more room so the bottom corner doesn't clip.
            safetyPadding = max(safetyPadding, HushSpacing.sm + HushSpacing.xs)
        }
        let constrainedWidth = max(1, width)
        let rect = attributedString.boundingRect(
            with: NSSize(width: constrainedWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading, .usesDeviceMetrics],
            context: nil
        )
        let measuredHeight = max(1, ceil(rect.height + safetyPadding))
        rowHeightCache.set(measuredHeight, for: key)
    }
}
