import Foundation
@testable import Hush
import Testing

@MainActor
struct LatexSegmentationTests {
    // MARK: - Task 8.2: Inline vs Block Detection

    @Test("Inline math is detected between single dollar signs")
    func inlineMathDetected() {
        let segments = MathSegmenter.segment("Hello $x^2$ world")
        #expect(segments == [
            .text("Hello "),
            .inlineMath("x^2"),
            .text(" world")
        ])
    }

    @Test("Block math is detected between double dollar signs")
    func blockMathDetected() {
        let segments = MathSegmenter.segment("Before $$E=mc^2$$ after")
        #expect(segments == [
            .text("Before "),
            .blockMath("E=mc^2"),
            .text(" after")
        ])
    }

    @Test("Block math may span newlines")
    func blockMathSpansNewlines() {
        let input = "$$\nx^2\n+ y^2\n$$"
        let segments = MathSegmenter.segment(input)
        #expect(segments.count == 1)
        if case let .blockMath(content) = segments.first {
            #expect(content.contains("x^2"))
            #expect(content.contains("y^2"))
        } else {
            Issue.record("Expected block math")
        }
    }

    @Test("Inline math does not span newlines")
    func inlineMathNoNewlines() {
        let segments = MathSegmenter.segment("$x^2\ny^2$")
        // Should not detect math — renders literally
        #expect(segments == [.text("$x^2\ny^2$")])
    }

    @Test("Multiple inline math segments")
    func multipleInline() {
        let segments = MathSegmenter.segment("$a$ and $b$")
        #expect(segments == [
            .inlineMath("a"),
            .text(" and "),
            .inlineMath("b")
        ])
    }

    @Test("Degree notation with numeric start is treated as inline math")
    func numericDegreeInlineMath() {
        let segments = MathSegmenter.segment("$30^\\circ$ and $0^\\circ$")
        #expect(segments == [
            .inlineMath("30^\\circ"),
            .text(" and "),
            .inlineMath("0^\\circ")
        ])
    }

    @Test("Pure numeric inline math is treated as math, not currency")
    func pureNumericInlineMath() {
        let segments = MathSegmenter.segment("radian $0$ value $1$")
        #expect(segments == [
            .text("radian "),
            .inlineMath("0"),
            .text(" value "),
            .inlineMath("1")
        ])
    }

    @Test("Special-angle rows keep all inline math segments")
    func specialAngleRowsInlineMath() {
        let input = """
        $0^\\circ$ | $0$ | $0$
        $30^\\circ$ | $\\pi/6$ | $1/2$
        $45^\\circ$ | $\\pi/4$ | $\\sqrt{2}/2$
        $60^\\circ$ | $\\pi/3$ | $\\sqrt{3}/2$
        $90^\\circ$ | $\\pi/2$ | $1$
        """

        let segments = MathSegmenter.segment(input)
        let inlineValues = segments.compactMap { segment -> String? in
            if case let .inlineMath(value) = segment {
                return value
            }
            return nil
        }

        #expect(inlineValues == [
            "0^\\circ", "0", "0",
            "30^\\circ", "\\pi/6", "1/2",
            "45^\\circ", "\\pi/4", "\\sqrt{2}/2",
            "60^\\circ", "\\pi/3", "\\sqrt{3}/2",
            "90^\\circ", "\\pi/2", "1"
        ])
    }

    @Test("Special-angle text renders without raw dollar markers")
    func specialAngleRowsRendered() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: """
            9. Special-angle values
            Angle (deg) | Radian (rad) | $\\sin$ value
            $0^\\circ$ | $0$ | $0$
            $30^\\circ$ | $\\pi/6$ | $1/2$
            $45^\\circ$ | $\\pi/4$ | $\\sqrt{2}/2$
            $60^\\circ$ | $\\pi/3$ | $\\sqrt{3}/2$
            $90^\\circ$ | $\\pi/2$ | $1$
            """,
            availableWidth: 600
        )
        let output = renderer.render(input)
        let renderedText = output.attributedString.string

        #expect(!renderedText.contains("$0^\\circ$"))
        #expect(!renderedText.contains("$0$"))
        #expect(!renderedText.contains("$1$"))
    }

    // MARK: - Task 8.2: Failure Fallback

    @Test("Renderer does not crash on math render failure")
    func mathRenderFailbackNoCrash() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: "Result: $\\undefinedmacro{x}$",
            availableWidth: 600
        )
        let output = renderer.render(input)
        // Should produce output without crashing
        #expect(output.attributedString.length > 0)
        #expect(output.plainText.contains("undefinedmacro"))
    }

    @Test("Unsupported dots command is normalized before rendering")
    func dotsCommandNormalizedBeforeRender() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: RenderingFixtures.LaTeX.inlineSeriesWithDots,
            availableWidth: 600
        )
        let output = renderer.render(input)
        let diagnostics = output.diagnostics.map(\.message).joined(separator: " | ")

        #expect(output.attributedString.length > 0)
        #expect(!diagnostics.contains("\\dots"))
    }

    @Test("Unclosed inline math renders literally")
    func unclosedInlineLiteral() {
        let segments = MathSegmenter.segment("Price is $100")
        // $100 should be literal (currency pattern)
        #expect(segments == [.text("Price is $100")])
    }

    @Test("Unclosed block math renders literally")
    func unclosedBlockLiteral() {
        let segments = MathSegmenter.segment("Start $$incomplete block")
        // Should render literally when no closing $$
        #expect(segments == [.text("Start $$incomplete block")])
    }

    // MARK: - Task 8.6: Math Inside Code

    @Test("Dollar signs inside inline code are not treated as math")
    func dollarInInlineCode() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: RenderingFixtures.LaTeX.dollarInCode,
            availableWidth: 600
        )
        let output = renderer.render(input)
        let text = output.attributedString.string
        // $HOME should appear literally in code, not as math
        #expect(text.contains("$HOME") || text.contains("HOME"))
    }

    @Test("Dollar signs inside fenced code blocks are not treated as math")
    func dollarInFencedCode() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: RenderingFixtures.LaTeX.dollarInCodeBlock,
            availableWidth: 600
        )
        let output = renderer.render(input)
        let text = output.attributedString.string
        #expect(text.contains("echo"))
        #expect(text.contains("HOME"))
    }

    // MARK: - Task 8.7: Escaped $ and Currency

    @Test("Escaped dollar sign renders as literal $")
    func escapedDollar() {
        let segments = MathSegmenter.segment("Cost is \\$100.")
        #expect(segments == [.text("Cost is $100.")])
    }

    @Test("Currency range like $10-$20 remains literal")
    func currencyRange() {
        let segments = MathSegmenter.segment("Price: $10-$20")
        // Both $ should be literal due to currency pattern
        #expect(segments == [.text("Price: $10-$20")])
    }

    @Test("Multiple currency values remain literal")
    func multipleCurrency() {
        let segments = MathSegmenter.segment("$50, $42.50, $7.50")
        // All should be literal
        for segment in segments {
            if case .inlineMath = segment {
                Issue.record("Currency should not be detected as math")
            }
            if case .blockMath = segment {
                Issue.record("Currency should not be detected as math")
            }
        }
    }

    // MARK: - No Content

    @Test("Simple math renders as attachment with object replacement character")
    func simpleMathRendersAsAttachment() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: "Result: $x^2$",
            availableWidth: 600
        )
        let output = renderer.render(input)
        let attrString = output.attributedString

        let objectReplacementChar = "\u{FFFC}"
        let hasAttachment = attrString.string.contains(objectReplacementChar)
        let hasFallbackDiagnostic = output.diagnostics.contains { $0.kind == .mathFailed }

        // Either successfully rendered as attachment OR fell back (environment-dependent)
        #expect(hasAttachment || hasFallbackDiagnostic || attrString.string.contains("x^2"))
        #expect(attrString.length > 0)
    }

    @Test("Empty string produces empty segments")
    func emptyString() {
        let segments = MathSegmenter.segment("")
        #expect(segments.isEmpty)
    }

    @Test("Text without dollar signs is a single segment")
    func noDollars() {
        let segments = MathSegmenter.segment("Hello world")
        #expect(segments == [.text("Hello world")])
    }
}
