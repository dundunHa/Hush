import AppKit
import Foundation
@testable import Hush
import Testing

@Suite(.serialized)
@MainActor
struct CellCacheFirstStreamingTests {
    func makeRow(
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
}

extension CellCacheFirstStreamingTests {
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
        let content = "Hello world"
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

    @Test("Empty streaming assistant shows waiting placeholder and yields to first token")
    func emptyStreamingAssistantShowsWaitingPlaceholder() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "77777777-6666-6666-6666-666666666666"))
        let row = makeRow(
            content: "",
            isStreaming: true,
            id: messageID,
            generation: 1
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-streaming-waiting"))

        cell.configure(
            row: row,
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while cell.attributedStringForTesting.string != RenderConstants.assistantWaitingPlaceholder,
              ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(!cell.hasRenderControllerForTesting)
        #expect(cell.renderRequestCountForTesting == 0)
        #expect(cell.attributedStringForTesting.string == RenderConstants.assistantWaitingPlaceholder)
        #expect(cell.waitingBreathingAnimationActiveForTesting)
        #expect(cell.streamingDisplayedLengthForTesting == 0)

        cell.updateStreamingText("hello")

        #expect(cell.attributedStringForTesting.string == "hello")
        #expect(cell.streamingDisplayedLengthForTesting == 5)
    }

    @Test("Whitespace-only streaming assistant keeps showing waiting placeholder until real content arrives")
    func whitespaceOnlyStreamingAssistantShowsWaitingPlaceholder() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "88888888-6666-6666-6666-666666666666"))
        let row = makeRow(
            content: " \n\t ",
            isStreaming: true,
            id: messageID,
            generation: 1
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-streaming-whitespace-waiting"))

        cell.configure(
            row: row,
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while cell.attributedStringForTesting.string != RenderConstants.assistantWaitingPlaceholder,
              ContinuousClock.now < deadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(cell.attributedStringForTesting.string == RenderConstants.assistantWaitingPlaceholder)
        #expect(!cell.hasRenderControllerForTesting)
        #expect(cell.waitingBreathingAnimationActiveForTesting)

        cell.updateStreamingText("hello")

        #expect(cell.attributedStringForTesting.string == "hello")
        #expect(cell.streamingDisplayedLengthForTesting == 5)
    }

    @Test("updateStreamingText updates plain text and displayed length")
    func updateStreamingTextUpdatesDisplayedLength() {
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-streaming-text"))
        cell.updateStreamingText("streaming-123")

        #expect(cell.attributedStringForTesting.string == "streaming-123")
        #expect(cell.streamingDisplayedLengthForTesting == "streaming-123".count)
        #expect(cell.streamingUpdateAssignmentCountForTesting == 1)
    }
}
