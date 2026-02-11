import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Markdown Rendering")
struct MarkdownRenderingTests {
    // MARK: - Helpers

    private func renderPlain(_ content: String, width: CGFloat = 600) -> String {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(content: content, availableWidth: width)
        return renderer.render(input).attributedString.string
    }

    private func renderOutput(_ content: String, width: CGFloat = 600) -> MessageRenderOutput {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(content: content, availableWidth: width)
        return renderer.render(input)
    }

    // MARK: - Task 8.1: Common Markdown Formatting

    @Test("Headings render without raw # markers")
    func headingsNoRawMarkers() {
        let text = renderPlain(RenderingFixtures.Markdown.headings)
        #expect(!text.contains("# "))
        #expect(text.contains("Heading 1"))
        #expect(text.contains("Heading 2"))
        #expect(text.contains("Heading 3"))
    }

    @Test("Emphasis renders without raw * markers")
    func emphasisNoRawMarkers() {
        let text = renderPlain(RenderingFixtures.Markdown.emphasis)
        #expect(!text.contains("*italic*"))
        #expect(!text.contains("**bold**"))
        #expect(text.contains("italic"))
        #expect(text.contains("bold"))
    }

    @Test("Paragraphs preserve text content")
    func paragraphsPreserveText() {
        let text = renderPlain(RenderingFixtures.Markdown.paragraphs)
        #expect(text.contains("First paragraph"))
        #expect(text.contains("Second paragraph"))
    }

    @Test("Inline code renders without backtick markers")
    func inlineCodeNoBackticks() {
        let text = renderPlain(RenderingFixtures.Markdown.inlineCode)
        #expect(!text.contains("`"))
        #expect(text.contains("print(\"hello\")"))
    }

    @Test("Links render text without raw markdown syntax")
    func linksNoRawSyntax() {
        let text = renderPlain(RenderingFixtures.Markdown.link)
        #expect(!text.contains("[Apple]"))
        #expect(!text.contains("]("))
        #expect(text.contains("Apple"))
    }

    @Test("Lists render without raw markers")
    func listsRender() {
        let unordered = renderPlain(RenderingFixtures.Markdown.unorderedList)
        #expect(unordered.contains("First item"))
        #expect(unordered.contains("Second item"))
        #expect(!unordered.contains("- First"))

        let ordered = renderPlain(RenderingFixtures.Markdown.orderedList)
        #expect(ordered.contains("First item"))
    }

    @Test("Blockquote renders without > markers")
    func blockquoteNoRawMarkers() {
        let text = renderPlain(RenderingFixtures.Markdown.blockquote)
        #expect(!text.contains("> This"))
        #expect(text.contains("blockquote"))
    }

    @Test("Plain text preserves content unchanged")
    func plainTextPreserved() {
        let text = renderPlain(RenderingFixtures.Markdown.plainText)
        #expect(text.contains("plain text with no markdown"))
    }

    @Test("Mixed content renders all constructs")
    func mixedContent() {
        let text = renderPlain(RenderingFixtures.Markdown.mixed)
        #expect(text.contains("Welcome"))
        #expect(text.contains("bold"))
        #expect(text.contains("inline code"))
        #expect(text.contains("Feature one"))
        #expect(text.contains("important"))
        #expect(text.contains("print"))
    }

    // MARK: - Task 8.11: Code Blocks Preserve Whitespace

    @Test("Fenced code blocks preserve whitespace and line breaks")
    func codeBlockPreservesWhitespace() {
        let text = renderPlain(RenderingFixtures.Markdown.codeBlockWithWhitespace)
        #expect(text.contains("line 1"))
        #expect(text.contains("    indented line"))
        #expect(text.contains("empty line above"))
    }

    @Test("Fenced code block content is preserved")
    func fencedCodePreserved() {
        let text = renderPlain(RenderingFixtures.Markdown.fencedCodeBlock)
        #expect(text.contains("func greet()"))
        #expect(text.contains("Hello, world!"))
    }

    @Test("Fenced code blocks expose language and copyable content ranges")
    func codeBlockLanguageAndContentAttributes() {
        let output = renderOutput(RenderingFixtures.Markdown.fencedCodeBlock)
        let attributed = output.attributedString

        let fullRange = NSRange(location: 0, length: attributed.length)
        var containerRanges: [NSRange] = []

        attributed.enumerateAttribute(.hushCodeBlockLanguage, in: fullRange, options: []) { value, range, _ in
            guard let language = value as? String else { return }
            containerRanges.append(range)
            #expect(language == "Swift")
        }

        #expect(containerRanges.count == 1)
        let container = containerRanges[0]

        var contentRange: NSRange?
        attributed.enumerateAttribute(.hushCodeBlockContent, in: container, options: []) { value, range, stop in
            guard value != nil else { return }
            contentRange = range
            stop.pointee = true
        }

        let code = contentRange.map { attributed.attributedSubstring(from: $0).string } ?? ""
        #expect(code.contains("func greet()"))
        #expect(!code.contains("Swift"))
        #expect(attributed.string.contains("Swift"))
    }

    @Test("Code blocks without explicit language default to Text")
    func codeBlockDefaultsToTextLanguage() {
        let output = renderOutput(RenderingFixtures.Markdown.codeBlockWithWhitespace)
        let attributed = output.attributedString

        let fullRange = NSRange(location: 0, length: attributed.length)
        var languages: [String] = []
        attributed.enumerateAttribute(.hushCodeBlockLanguage, in: fullRange, options: []) { value, _, _ in
            guard let language = value as? String else { return }
            languages.append(language)
        }

        #expect(languages.count == 1)
        #expect(languages[0] == "Text")
        #expect(!attributed.string.contains("TEXT"))
    }

    @Test("Code block spacing before header is preserved inside ordered lists")
    func codeBlockSpacingInsideOrderedList() {
        let markdown = """
        1. List intro paragraph

           ```go
           package main
           ```
        """

        let output = renderOutput(markdown)
        let attributed = output.attributedString
        let fullRange = NSRange(location: 0, length: attributed.length)
        var codeContainer: NSRange?

        attributed.enumerateAttribute(.hushCodeBlockLanguage, in: fullRange, options: []) { value, range, stop in
            guard let language = value as? String else { return }
            #expect(language == "Go")
            codeContainer = range
            stop.pointee = true
        }

        guard let codeContainer else {
            #expect(Bool(false), "Expected one fenced code block in ordered list output")
            return
        }

        let attrs = attributed.attributes(at: codeContainer.location, effectiveRange: nil)
        let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle
        let expectedSpacing = RenderStyle.fromTheme().codeBlockSpacing
        #expect(paragraphStyle != nil)
        #expect(paragraphStyle?.paragraphSpacingBefore == expectedSpacing)
    }

    @Test("Inline code preserves literal characters")
    func inlineCodeLiteral() {
        let text = renderPlain("Use `<div>` and `&amp;` in HTML.")
        #expect(text.contains("<div>"))
        #expect(text.contains("&amp;"))
    }

    // MARK: - Render Failure Safety

    @Test("Empty content does not crash")
    func emptyContent() {
        let output = renderOutput(RenderingFixtures.EdgeCases.empty)
        #expect(output.attributedString.length == 0)
    }

    @Test("Malformed markdown does not crash")
    func malformedMarkdown() {
        let output = renderOutput(RenderingFixtures.EdgeCases.malformedMarkdown)
        #expect(output.attributedString.length > 0)
        // Should contain readable text, not crash
        #expect(output.plainText.contains("Unclosed heading"))
    }
}
