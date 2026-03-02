import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Cell Cache-First Streaming Tests")
struct CellCacheFirstStreamingTests {
    private func makeRow(
        content: String,
        isStreaming: Bool,
        id: UUID = UUID(),
        generation: UInt64 = 1
    ) -> MessageTableView.RowModel {
        let message = ChatMessage(id: id, role: .assistant, content: content)
        return MessageTableView.RowModel(
            message: message,
            isStreaming: isStreaming,
            renderHint: MessageRenderHint(
                conversationID: "conv-1",
                messageID: message.id,
                rankFromLatest: 0,
                isVisible: true,
                switchGeneration: generation
            )
        )
    }

    @Test("Streaming messages skip cache-first path")
    func streamingSkipsCacheFirst() {
        let renderCache = RenderCache(capacity: 10)
        let renderer = MessageContentRenderer(
            renderCache: renderCache,
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let contentWidth = max(1, availableWidth - HushSpacing.xl * 2)
        let content = "Hello **world**"
        let style = RenderStyle.fromTheme()

        let key = RenderCache.makeKey(content: content, width: contentWidth, style: style)
        renderCache.set(key, output: MessageRenderOutput(
            attributedString: NSAttributedString(
                string: "Hello world",
                attributes: [.foregroundColor: NSColor.systemGreen]
            ),
            plainText: "Hello world",
            diagnostics: []
        ))

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test"))
        cell.configure(
            row: makeRow(content: content, isStreaming: true),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(!cell.hasRenderControllerForTesting)
        #expect(cell.attributedStringForTesting.string == content)
    }

    @Test("Streaming configure never issues rich render requests")
    func streamingConfigureDoesNotRequestRichRender() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "66666666-6666-6666-6666-666666666666"))
        let row = makeRow(
            content: "streaming partial",
            isStreaming: true,
            id: messageID,
            generation: 1
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-dedup-hit"))

        cell.configure(
            row: row,
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        #expect(cell.renderRequestCountForTesting == 0)
        #expect(!cell.hasRenderControllerForTesting)

        cell.configure(
            row: row,
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        #expect(cell.renderRequestCountForTesting == 0)
        #expect(!cell.hasRenderControllerForTesting)
    }

    @Test("updateStreamingText updates plain text and displayed length")
    func updateStreamingTextUpdatesDisplayedLength() {
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-streaming-text"))
        cell.updateStreamingText("streaming-123")

        #expect(cell.attributedStringForTesting.string == "streaming-123")
        #expect(cell.streamingDisplayedLengthForTesting == "streaming-123".count)
        #expect(cell.streamingUpdateAssignmentCountForTesting == 1)
    }

    @Test("Streaming configure does not regress over newer fast-track text")
    func streamingConfigureSkipsStalePlainOverwrite() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-anti-regression"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "CCCCCCCC-7777-7777-7777-777777777777"))

        let initialStreamingContent = "abc **def**"
        cell.configure(
            row: makeRow(content: initialStreamingContent, isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        #expect(cell.attributedStringForTesting.string == initialStreamingContent)
        #expect(!cell.hasRenderControllerForTesting)

        cell.updateStreamingText("abc def + tail")

        cell.configure(
            row: makeRow(content: "abc", isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        try? await Task.sleep(for: .milliseconds(80))

        #expect(cell.attributedStringForTesting.string == "abc def + tail")
    }

    @Test("Streaming output apply guard rejects stale shorter plain text")
    func streamingOutputApplyGuardRejectsStaleShorterOutput() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-output-guard-streaming"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "C1C1C1C1-7777-7777-7777-777777777777"))
        let observedRow = makeRow(content: "stale", isStreaming: true, id: messageID)

        cell.configure(
            row: makeRow(content: "seed", isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        cell.updateStreamingText("seed + tail")

        #expect(cell.shouldApplyOutputForTesting(
            plainText: "seed",
            observedRow: observedRow
        ) == false)
        #expect(cell.shouldApplyOutputForTesting(
            plainText: "seed + tail",
            observedRow: observedRow
        ))
    }

    @Test("Non-streaming configure always overwrites and resets anti-regression state")
    func nonStreamingConfigureAlwaysOverwritesAndResetsState() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-final-overwrite"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "DDDDDDDD-7777-7777-7777-777777777777"))

        cell.configure(
            row: makeRow(content: "abcdef", isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        cell.updateStreamingText("abcdefghij")

        cell.configure(
            row: makeRow(content: "final", isStreaming: false, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(cell.attributedStringForTesting.string == "final")
        #expect(cell.streamingDisplayedLengthForTesting == 0)
    }

    @Test("Fast-track then stale slow-track then final rich render keeps visual correctness")
    func fastTrackStaleSlowTrackThenFinalRichRender() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-fast-slow-integration"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "EEEEEEEE-7777-7777-7777-777777777777"))

        cell.configure(
            row: makeRow(content: "start", isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        cell.updateStreamingText("streaming-longer-text")

        cell.configure(
            row: makeRow(content: "short", isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        #expect(cell.attributedStringForTesting.string == "streaming-longer-text")

        cell.configure(
            row: makeRow(content: "final **done**", isStreaming: false, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        let deadline = ContinuousClock.now + .seconds(2)
        while cell.attributedStringForTesting.string.contains("**"), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!cell.attributedStringForTesting.string.contains("**"))
    }

    @Test("Final configure keeps plain text when rich render is pending")
    func finalConfigureKeepsPlainTextWhileRichPending() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-final-guard"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "F0F0F0F0-7777-7777-7777-777777777777"))

        cell.configure(
            row: makeRow(content: "stream old + tail", isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        #expect(cell.attributedStringForTesting.string == "stream old + tail")
        #expect(!cell.hasRenderControllerForTesting)

        let finalContent = "stream old + tail **final**"
        cell.configure(
            row: makeRow(content: finalContent, isStreaming: false, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        // Non-streaming cache miss shows the plain fallback immediately.
        #expect(cell.attributedStringForTesting.string == finalContent)
        #expect(cell.hasRenderControllerForTesting)
    }
}
