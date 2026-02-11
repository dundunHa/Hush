import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Table Rendering")
struct TableRenderingTests {
    // MARK: - Helpers

    /// Render content and extract the visible plain text.
    private func renderPlain(_ content: String, isStreaming: Bool = false) -> String {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(content: content, availableWidth: 600, isStreaming: isStreaming)
        return renderer.render(input).attributedString.string
    }

    // MARK: - Table Fallback Readability

    @Test("Simple table preserves cell content")
    func simpleCellContent() {
        let text = renderPlain(RenderingFixtures.Tables.simple)
        #expect(text.contains("Alice"))
        #expect(text.contains("Bob"))
        #expect(text.contains("30"))
        #expect(text.contains("25"))
    }

    @Test("Table has visible row/column separation")
    func tableHasSeparation() {
        let text = renderPlain(RenderingFixtures.Tables.simple)
        #expect(text.contains("│") || text.contains("|"))
        #expect(text.contains("─") || text.contains("-"))
    }

    @Test("Table headers are present")
    func tableHeaders() {
        let text = renderPlain(RenderingFixtures.Tables.simple)
        #expect(text.contains("Name"))
        #expect(text.contains("Age"))
    }

    @Test("Wide table content remains accessible")
    func wideTableAccessible() {
        let text = renderPlain(RenderingFixtures.Tables.wide)
        #expect(text.contains("Feature"))
        #expect(text.contains("Description"))
        #expect(text.contains("Status"))
        #expect(text.contains("Auth"))
        #expect(text.contains("Search"))
    }

    @Test("Table with inline formatting preserves content")
    func tableWithFormatting() {
        let text = renderPlain(RenderingFixtures.Tables.withFormatting)
        #expect(text.contains("sort()"))
        #expect(text.contains("search()"))
        #expect(text.contains("O(n log n)"))
    }

    @Test("Table math cells render without raw dollar markers")
    func tableMathRenders() {
        let text = renderPlain(RenderingFixtures.Tables.withMath)
        #expect(!text.contains("$0^\\circ$"))
        #expect(!text.contains("$0$"))
        #expect(!text.contains("$1$"))
    }

    // MARK: - Diagnostics

    @Test("Table rendering emits tableFallback diagnostic when streaming")
    func tableDiagnosticStreaming() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: RenderingFixtures.Tables.simple,
            availableWidth: 600,
            isStreaming: true
        )
        let output = renderer.render(input)
        #expect(output.diagnostics.contains { $0.kind == .tableFallback })
        #expect(!output.diagnostics.contains { $0.kind == .tableAttachment })
    }

    @Test("Non-streaming table also renders as fallback (no attachment)")
    func nonStreamingTableFallback() {
        let renderer = MessageContentRenderer()
        let input = MessageRenderInput(
            content: RenderingFixtures.Tables.simple,
            availableWidth: 600,
            isStreaming: false
        )
        let output = renderer.render(input)
        #expect(output.diagnostics.contains { $0.kind == .tableFallback })
        #expect(!output.diagnostics.contains { $0.kind == .tableAttachment })
    }
}
