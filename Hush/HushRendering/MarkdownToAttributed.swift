import AppKit
import Markdown

// swiftlint:disable type_body_length file_length

/// Converts a Markdown AST into an `NSAttributedString`.
///
/// - Code spans and code blocks are rendered in monospace with no math processing.
/// - Text nodes outside code contexts are segmented for LaTeX math.
/// - Tables are rendered via `TableRenderer` as monospace blocks.
final class MarkdownToAttributed {
    // MARK: - Dependencies

    private let style: RenderStyle
    private let mathRenderer: MathRenderer
    private let maxWidth: CGFloat
    private let isStreaming: Bool

    // MARK: - Diagnostics

    private(set) var diagnostics: [RenderDiagnostic] = []
    private var mathSegmentCount = 0
    private var didTriggerMathSegmentLimit = false

    // MARK: - Init

    init(
        style: RenderStyle,
        mathRenderer: MathRenderer,
        maxWidth: CGFloat,
        isStreaming: Bool = false
    ) {
        self.style = style
        self.mathRenderer = mathRenderer
        self.maxWidth = maxWidth
        self.isStreaming = isStreaming
    }

    // MARK: - Public Interface

    func convert(_ document: Document) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, child) in document.children.enumerated() {
            let block = renderBlock(child)
            result.append(block)

            // Add spacing between blocks (except after last)
            if index < document.childCount - 1 {
                result.append(makeBlockSeparator(after: block))
            }
        }
        return result
    }

    private func makeBlockSeparator(after block: NSAttributedString) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: style.bodyFont,
            .foregroundColor: style.bodyColor
        ]

        guard block.length > 0 else {
            return NSAttributedString(string: "\n", attributes: attrs)
        }

        let lastAttrs = block.attributes(at: block.length - 1, effectiveRange: nil)
        if let paragraphStyle = lastAttrs[.paragraphStyle] {
            attrs[.paragraphStyle] = paragraphStyle
        }
        if let font = lastAttrs[.font] {
            attrs[.font] = font
        }
        if let color = lastAttrs[.foregroundColor] {
            attrs[.foregroundColor] = color
        }

        return NSAttributedString(string: "\n", attributes: attrs)
    }

    // MARK: - Block-Level Rendering

    private func renderBlock(_ markup: any Markup) -> NSAttributedString {
        switch markup {
        case let heading as Heading:
            return renderHeading(heading)

        case let paragraph as Paragraph:
            return renderParagraph(paragraph)

        case let codeBlock as CodeBlock:
            return renderCodeBlock(codeBlock)

        case let blockQuote as BlockQuote:
            return renderBlockQuote(blockQuote)

        case let list as UnorderedList:
            return renderUnorderedList(list)

        case let list as OrderedList:
            return renderOrderedList(list)

        case is ThematicBreak:
            return renderThematicBreak()

        case let table as Markdown.Table:
            return renderTable(table)

        case let html as HTMLBlock:
            return renderHTMLBlock(html)

        default:
            // Unknown block — render children or raw text
            return renderInlineChildren(markup)
        }
    }

    // MARK: - Heading

    private func renderHeading(_ heading: Heading) -> NSAttributedString {
        let font: NSFont
        switch heading.level {
        case 1: font = style.heading1Font
        case 2: font = style.heading2Font
        default: font = style.heading3Font
        }

        let result = NSMutableAttributedString()
        for child in heading.children {
            result.append(renderInline(child, baseFont: font, baseColor: style.headingColor))
        }

        let para = NSMutableParagraphStyle()
        para.paragraphSpacingBefore = style.headingSpacing
        para.paragraphSpacing = style.headingSpacing / 2
        result.addAttribute(
            .paragraphStyle,
            value: para,
            range: NSRange(location: 0, length: result.length)
        )

        return result
    }

    // MARK: - Paragraph

    private func renderParagraph(_ paragraph: Paragraph) -> NSAttributedString {
        let result = renderInlineChildren(paragraph)
        let mutable = NSMutableAttributedString(attributedString: result)

        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = style.paragraphSpacing
        mutable.addAttribute(
            .paragraphStyle,
            value: para,
            range: NSRange(location: 0, length: mutable.length)
        )

        return mutable
    }

    // MARK: - Code Block

    // swiftlint:disable:next function_body_length
    private func renderCodeBlock(_ codeBlock: CodeBlock) -> NSAttributedString {
        let displayLanguage = Self.normalizeCodeBlockLanguage(codeBlock.language)
        let rawLanguage = codeBlock.language?.trimmingCharacters(in: .whitespacesAndNewlines)
        let headerText = (rawLanguage?.isEmpty == false) ? displayLanguage : nil

        var code = codeBlock.code
        if code.hasSuffix("\n") {
            code.removeLast()
        }

        let result = NSMutableAttributedString()

        var headerParagraph: NSMutableParagraphStyle?
        if let headerText, !headerText.isEmpty {
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: style.codeFontSmall,
                .foregroundColor: style.blockquoteColor,
                .kern: 0.3
            ]
            result.append(NSAttributedString(string: headerText, attributes: headerAttrs))
            result.append(NSAttributedString(string: "\n", attributes: headerAttrs))

            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacingBefore = style.codeBlockSpacing
            paragraph.paragraphSpacing = style.paragraphSpacing
            paragraph.lineBreakMode = .byTruncatingTail
            paragraph.headIndent = 12
            paragraph.firstLineHeadIndent = 12
            // Reserve room for the copy button on the right side of the header.
            paragraph.tailIndent = -52
            result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
            headerParagraph = paragraph
        }

        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: style.codeFont,
            .foregroundColor: style.codeColor
        ]
        let codeStart = result.length
        result.append(NSAttributedString(string: code, attributes: codeAttrs))

        guard result.length > 0 else { return result }

        // Mark the container + content for transcript UI (copy button + background drawing).
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.hushCodeBlockLanguage, value: displayLanguage, range: fullRange)
        if result.length > codeStart {
            let codeRange = NSRange(location: codeStart, length: result.length - codeStart)
            result.addAttribute(.hushCodeBlockContent, value: true, range: codeRange)
        }

        // Paragraph styles:
        // - apply outer spacing only to the header (before) and the last code line (after),
        //   so we don't introduce extra spacing between code lines (newlines are paragraphs).
        let codeParagraph = NSMutableParagraphStyle()
        codeParagraph.paragraphSpacingBefore = 0
        codeParagraph.paragraphSpacing = 0
        codeParagraph.lineSpacing = 2
        codeParagraph.lineBreakMode = .byCharWrapping
        codeParagraph.headIndent = 12
        codeParagraph.firstLineHeadIndent = 12
        codeParagraph.tailIndent = -12

        if result.length > codeStart {
            let codeRange = NSRange(location: codeStart, length: result.length - codeStart)
            result.addAttribute(.paragraphStyle, value: codeParagraph, range: codeRange)

            if headerParagraph == nil {
                // Apply top spacing to the first code line only (no header).
                let string = result.string as NSString
                let newlineRange = string.range(of: "\n", options: [], range: codeRange)
                let firstLineRange =
                    newlineRange.location == NSNotFound
                        ? codeRange
                        : NSRange(location: codeStart, length: max(0, newlineRange.location - codeStart))
                if firstLineRange.length > 0 {
                    let headParagraph = NSMutableParagraphStyle()
                    headParagraph.setParagraphStyle(codeParagraph)
                    headParagraph.paragraphSpacingBefore = style.codeBlockSpacing
                    result.addAttribute(.paragraphStyle, value: headParagraph, range: firstLineRange)
                }
            }

            // Add spacing after the final paragraph only.
            if let lastNewline = result.string.lastIndex(of: "\n") {
                let lastNewlineOffset = lastNewline.utf16Offset(in: result.string)
                let lastParagraphStart = max(codeStart, lastNewlineOffset + 1)
                if lastParagraphStart < result.length {
                    let lastParagraphRange = NSRange(location: lastParagraphStart, length: result.length - lastParagraphStart)
                    let tailParagraph = NSMutableParagraphStyle()
                    tailParagraph.setParagraphStyle(codeParagraph)
                    tailParagraph.paragraphSpacing = style.codeBlockSpacing
                    result.addAttribute(.paragraphStyle, value: tailParagraph, range: lastParagraphRange)
                }
            } else {
                let tailParagraph = NSMutableParagraphStyle()
                tailParagraph.setParagraphStyle(codeParagraph)
                tailParagraph.paragraphSpacing = style.codeBlockSpacing
                result.addAttribute(.paragraphStyle, value: tailParagraph, range: codeRange)
            }
        } else {
            // No code content: still add bottom spacing on the header paragraph.
            if let headerParagraph {
                let tailHeader = NSMutableParagraphStyle()
                tailHeader.setParagraphStyle(headerParagraph)
                tailHeader.paragraphSpacing = style.codeBlockSpacing
                result.addAttribute(.paragraphStyle, value: tailHeader, range: NSRange(location: 0, length: codeStart))
            }
        }

        return result
    }

    private static let codeBlockLanguageAliases: [String: String] = [
        "bash": "Bash",
        "sh": "Bash",
        "shell": "Bash",
        "c": "C",
        "cpp": "C++",
        "c++": "C++",
        "cs": "C#",
        "c#": "C#",
        "csharp": "C#",
        "diff": "Diff",
        "patch": "Diff",
        "docker": "Dockerfile",
        "dockerfile": "Dockerfile",
        "go": "Go",
        "golang": "Go",
        "html": "HTML",
        "htm": "HTML",
        "javascript": "JavaScript",
        "js": "JavaScript",
        "node": "JavaScript",
        "json": "JSON",
        "kotlin": "Kotlin",
        "kt": "Kotlin",
        "markdown": "Markdown",
        "md": "Markdown",
        "objc": "Objective-C",
        "objective-c": "Objective-C",
        "objectivec": "Objective-C",
        "python": "Python",
        "py": "Python",
        "ruby": "Ruby",
        "rb": "Ruby",
        "rust": "Rust",
        "rs": "Rust",
        "sql": "SQL",
        "swift": "Swift",
        "toml": "TOML",
        "ts": "TypeScript",
        "typescript": "TypeScript",
        "tsx": "TSX",
        "yaml": "YAML",
        "yml": "YAML"
    ]

    private static func normalizeCodeBlockLanguage(_ raw: String?) -> String {
        guard let raw else { return "Text" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Text" }

        let token = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? trimmed
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Text" }
        let key = normalized.lowercased()
        if let alias = codeBlockLanguageAliases[key] {
            return alias
        }
        if normalized.count <= 12 {
            return normalized
        }
        return String(normalized.prefix(12))
    }

    // MARK: - Block Quote

    private func renderBlockQuote(_ blockQuote: BlockQuote) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let prefix = "│ "

        for child in blockQuote.children {
            let block = renderBlock(child)
            let mutable = NSMutableAttributedString(string: prefix)
            mutable.append(block)
            mutable.addAttribute(
                .foregroundColor,
                value: style.blockquoteColor,
                range: NSRange(location: 0, length: mutable.length)
            )
            result.append(mutable)
        }

        return result
    }

    // MARK: - Lists

    private func renderUnorderedList(_ list: UnorderedList) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for item in list.listItems {
            let bullet = "• "
            let content = renderListItemContent(item)
            let line = NSMutableAttributedString(
                string: bullet,
                attributes: [
                    .font: style.bodyFont,
                    .foregroundColor: style.bodyColor
                ]
            )
            line.append(content)
            result.append(line)
            result.append(NSAttributedString(string: "\n"))
        }
        // Remove trailing newline
        if result.length > 0, result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        let para = NSMutableParagraphStyle()
        para.headIndent = style.listIndent
        para.firstLineHeadIndent = style.listIndent / 2
        para.paragraphSpacing = 2
        applyListParagraphStyleIfNeeded(para, to: result)

        return result
    }

    private func renderOrderedList(_ list: OrderedList) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in list.listItems.enumerated() {
            let number = "\(index + 1). "
            let content = renderListItemContent(item)
            let line = NSMutableAttributedString(
                string: number,
                attributes: [
                    .font: style.bodyFont,
                    .foregroundColor: style.bodyColor
                ]
            )
            line.append(content)
            result.append(line)
            result.append(NSAttributedString(string: "\n"))
        }
        if result.length > 0, result.string.hasSuffix("\n") {
            result.deleteCharacters(in: NSRange(location: result.length - 1, length: 1))
        }

        let para = NSMutableParagraphStyle()
        para.headIndent = style.listIndent
        para.firstLineHeadIndent = style.listIndent / 2
        para.paragraphSpacing = 2
        applyListParagraphStyleIfNeeded(para, to: result)

        return result
    }

    private func applyListParagraphStyleIfNeeded(
        _ paragraphStyle: NSParagraphStyle,
        to text: NSMutableAttributedString
    ) {
        guard text.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            guard value == nil else { return }
            text.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
    }

    private func renderListItemContent(_ item: ListItem) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in item.children {
            if child is Paragraph {
                // Render paragraph inline (no extra spacing inside list)
                result.append(renderInlineChildren(child))
            } else {
                result.append(renderBlock(child))
            }
        }
        return result
    }

    // MARK: - Thematic Break

    private func renderThematicBreak() -> NSAttributedString {
        let line = String(repeating: "─", count: 40)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: style.bodyFont,
            .foregroundColor: style.blockquoteBarColor
        ]
        return NSAttributedString(string: line, attributes: attrs)
    }

    // MARK: - Table

    private func renderTable(_ table: Markdown.Table) -> NSAttributedString {
        // Always render tables as monospace blocks.
        // Table attachments embed nested scroll views and can destabilize transcript scroll,
        // especially during streaming and row-height invalidation. We prefer stable output.
        let fallback = TableRenderer.render(table: table, style: style, maxWidth: maxWidth)
        diagnostics.append(RenderDiagnostic(kind: .tableFallback, message: "Table rendered as monospace"))
        let source = fallback.string
        guard source.contains("$") else {
            return fallback
        }

        RenderDebug.log("[Math] Table fallback contains '$'; attempting math rendering inside table")
        return renderTableFallbackWithMath(source)
    }

    private func renderTableFallbackWithMath(_ source: String) -> NSAttributedString {
        // TableRenderer formats as lines with distinct colors. Rebuild per-line so we
        // can run math segmentation without fragile source-range mapping (e.g. escaped `\\$`).
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let result = NSMutableAttributedString()

        for (index, line) in lines.enumerated() {
            let color: NSColor
            if index == 0 {
                color = style.tableHeaderColor
            } else if index == 1 {
                color = style.tableBorderColor
            } else {
                color = style.bodyColor
            }

            if !line.isEmpty {
                result.append(renderTextWithMath(String(line), font: style.codeFont, color: color))
            }

            // Re-add newline except after the last split component.
            if index < lines.count - 1 {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: style.codeFont,
                    .foregroundColor: color
                ]
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        result.addAttribute(
            .paragraphStyle,
            value: para,
            range: NSRange(location: 0, length: result.length)
        )

        return result
    }

    // MARK: - HTML Block

    private func renderHTMLBlock(_ html: HTMLBlock) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: style.codeFont,
            .foregroundColor: style.codeColor
        ]
        return NSAttributedString(string: html.rawHTML, attributes: attrs)
    }

    // MARK: - Inline Rendering

    private func renderInlineChildren(_ markup: any Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(renderInline(child, baseFont: style.bodyFont, baseColor: style.bodyColor))
        }
        return result
    }

    private func renderInline(
        _ markup: any Markup,
        baseFont: NSFont,
        baseColor: NSColor
    ) -> NSAttributedString {
        if let rendered = renderKnownInline(markup, baseFont: baseFont, baseColor: baseColor) {
            return rendered
        }
        return renderInlineFallback(markup, baseFont: baseFont, baseColor: baseColor)
    }

    private func renderKnownInline(
        _ markup: any Markup,
        baseFont: NSFont,
        baseColor: NSColor
    ) -> NSAttributedString? {
        switch markup {
        case let text as Markdown.Text:
            return renderTextWithMath(text.string, font: baseFont, color: baseColor)
        case let code as InlineCode:
            return renderInlineCode(code)
        case let emphasis as Emphasis:
            return renderEmphasis(emphasis, baseFont: baseFont, baseColor: baseColor)
        case let strong as Strong:
            return renderStrong(strong, baseFont: baseFont, baseColor: baseColor)
        case let link as Markdown.Link:
            return renderLink(link, baseFont: baseFont)
        case is SoftBreak:
            return renderBreakInline(" ", baseFont: baseFont, baseColor: baseColor)
        case is LineBreak:
            return renderBreakInline("\n", baseFont: baseFont, baseColor: baseColor)
        case let image as Markdown.Image:
            return renderImageInline(image, baseFont: baseFont)
        default:
            return nil
        }
    }

    private func renderBreakInline(
        _ value: String,
        baseFont: NSFont,
        baseColor: NSColor
    ) -> NSAttributedString {
        NSAttributedString(
            string: value,
            attributes: [.font: baseFont, .foregroundColor: baseColor]
        )
    }

    private func renderImageInline(
        _ image: Markdown.Image,
        baseFont: NSFont
    ) -> NSAttributedString {
        // Render image alt text as placeholder
        let alt = image.plainText
        let display = alt.isEmpty ? "[image]" : "[\(alt)]"
        return NSAttributedString(
            string: display,
            attributes: [.font: baseFont, .foregroundColor: style.linkColor]
        )
    }

    private func renderInlineFallback(
        _ markup: any Markup,
        baseFont: NSFont,
        baseColor: NSColor
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(renderInline(child, baseFont: baseFont, baseColor: baseColor))
        }
        if result.length > 0 {
            return result
        }

        // Last resort: if markup has a description, use that
        let desc = markup.format()
        return NSAttributedString(
            string: desc,
            attributes: [.font: baseFont, .foregroundColor: baseColor]
        )
    }

    // MARK: - Text with Math

    private func renderTextWithMath(
        _ text: String,
        font: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        let segments = MathSegmenter.segment(text)
        let mathSegments = segments.filter {
            if case .text = $0 { return false }
            return true
        }.count
        if mathSegments > 0 {
            let summary = segments.map { segment -> String in
                switch segment {
                case let .text(value):
                    return "text(\(RenderDebug.preview(value, limit: 80)))"
                case let .inlineMath(value):
                    return "inline(\(RenderDebug.preview(value, limit: 80)))"
                case let .blockMath(value):
                    return "block(\(RenderDebug.preview(value, limit: 80)))"
                }
            }.joined(separator: " | ")
            RenderDebug.log("[MathSeg] source=\(RenderDebug.preview(text, limit: 300))")
            RenderDebug.log("[MathSeg] segments=\(RenderDebug.preview(summary, limit: 800))")
        }
        let result = NSMutableAttributedString()

        for segment in segments {
            switch segment {
            case let .text(str):
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color
                ]
                result.append(NSAttributedString(string: str, attributes: attrs))

            case let .inlineMath(latex):
                result.append(renderMathSegment(latex: latex, displayMode: false, font: font, color: color))

            case let .blockMath(latex):
                result.append(NSAttributedString(string: "\n"))
                result.append(renderMathSegment(latex: latex, displayMode: true, font: font, color: color))
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    private func renderMathSegment(
        latex: String,
        displayMode: Bool,
        font: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        // Check guardrail
        mathSegmentCount += 1
        if mathSegmentCount > RenderConstants.maxMathSegmentsPerMessage {
            if !didTriggerMathSegmentLimit {
                didTriggerMathSegmentLimit = true
                diagnostics.append(RenderDiagnostic(
                    kind: .guardrailTriggered,
                    message: """
                    Math segment limit exceeded (\(RenderConstants.maxMathSegmentsPerMessage));
                    rendering remaining segments as source
                    """
                ))
                RenderDebug.log(
                    "[Math] Guardrail: segment limit exceeded at \(mathSegmentCount) (limit=\(RenderConstants.maxMathSegmentsPerMessage))"
                )
            }
            return mathRenderer.fallbackAttributedString(
                latex: latex, displayMode: displayMode, style: style
            )
        }

        if let attachment = mathRenderer.renderToAttachment(
            latex: latex,
            displayMode: displayMode,
            fontSize: font.pointSize,
            textColor: color,
            maxWidth: maxWidth
        ) {
            return NSAttributedString(attachment: attachment)
        }

        // Fallback
        diagnostics.append(RenderDiagnostic(
            kind: .mathFailed,
            message: "Failed to render: \(latex.prefix(50))"
        ))
        RenderDebug.log(
            "[Math] Fallback mode=\(displayMode ? "block" : "inline") latex=\(RenderDebug.preview(latex, limit: 180))"
        )
        return mathRenderer.fallbackAttributedString(
            latex: latex, displayMode: displayMode, style: style
        )
    }

    // MARK: - Inline Code

    private func renderInlineCode(_ code: InlineCode) -> NSAttributedString {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: style.codeFont,
            .foregroundColor: style.codeColor,
            .backgroundColor: style.codeBackgroundColor
        ]
        return NSAttributedString(string: code.code, attributes: attrs)
    }

    // MARK: - Emphasis / Strong

    private func renderEmphasis(
        _ emphasis: Emphasis,
        baseFont: NSFont,
        baseColor: NSColor
    ) -> NSAttributedString {
        let italicFont: NSFont = {
            let desc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: desc, size: baseFont.pointSize) ?? baseFont
        }()
        let result = NSMutableAttributedString()
        for child in emphasis.children {
            result.append(renderInline(child, baseFont: italicFont, baseColor: baseColor))
        }
        return result
    }

    private func renderStrong(
        _ strong: Strong,
        baseFont: NSFont,
        baseColor: NSColor
    ) -> NSAttributedString {
        let boldFont: NSFont = {
            let desc = baseFont.fontDescriptor.withSymbolicTraits(.bold)
            return NSFont(descriptor: desc, size: baseFont.pointSize) ?? NSFont.boldSystemFont(ofSize: baseFont.pointSize)
        }()
        let result = NSMutableAttributedString()
        for child in strong.children {
            result.append(renderInline(child, baseFont: boldFont, baseColor: baseColor))
        }
        return result
    }

    // MARK: - Link

    private func renderLink(
        _ link: Markdown.Link,
        baseFont: NSFont
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in link.children {
            result.append(renderInline(child, baseFont: baseFont, baseColor: style.linkColor))
        }
        if let destination = link.destination, let url = URL(string: destination) {
            result.addAttribute(
                .link,
                value: url,
                range: NSRange(location: 0, length: result.length)
            )
        }
        result.addAttribute(
            .underlineStyle,
            value: NSUnderlineStyle.single.rawValue,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }
}

// swiftlint:enable type_body_length file_length
