import Foundation
@testable import Hush
import Testing

@MainActor
struct GuardrailsTests {
    // MARK: - Task 8.10: Excessive Math and Long Content

    @Test("Excessive math segments fall back safely with no crash")
    func excessiveMathFallback() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: RenderingFixtures.LaTeX.manySegments,
            availableWidth: 600
        )
        let output = renderer.render(input)

        // Should not crash
        #expect(output.attributedString.length > 0)
        // Should have guardrail diagnostic
        #expect(output.diagnostics.contains { $0.kind == .guardrailTriggered })
    }

    @Test("Very long content does not crash")
    func veryLongContent() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: RenderingFixtures.EdgeCases.veryLong,
            availableWidth: 600
        )
        let output = renderer.render(input)

        // Should render without crashing
        #expect(output.attributedString.length > 0)
    }

    @Test("Content exceeding max length triggers guardrail diagnostic")
    func contentLengthGuardrail() {
        let renderer = MessageContentRenderer()
        // Create content longer than maxRichRenderLength
        let longContent = String(repeating: "A", count: RenderConstants.maxRichRenderLength + 100)
        let input = MessageRenderInput(content: longContent, availableWidth: 600)
        let output = renderer.render(input)

        #expect(output.diagnostics.contains { $0.kind == .guardrailTriggered })
    }

    @Test("Empty content returns empty output without crashing")
    func emptyContentSafe() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(content: "", availableWidth: 600)
        let output = renderer.render(input)

        #expect(output.attributedString.length == 0)
        #expect(output.diagnostics.isEmpty)
    }

    @Test("Malformed markdown with math does not crash")
    func malformedWithMath() {
        let renderer = MessageContentRenderer()
        let content = """
        # Broken
        **unclosed bold with $math$ inside
        ```
        code with $$block math$$
        unclosed fence
        """
        let input = MessageRenderInput(content: content, availableWidth: 600)
        let output = renderer.render(input)

        #expect(output.attributedString.length > 0)
    }
}
