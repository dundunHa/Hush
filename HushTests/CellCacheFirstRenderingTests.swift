import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Cell Cache-First Rendering Tests")
struct CellCacheFirstRenderingTests {
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

    @Test("Cache hit sets rich text immediately and does not create RenderController")
    func cacheHitUsesRichImmediately() {
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
        let attributed = NSAttributedString(
            string: "Hello world",
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        renderCache.set(key, output: MessageRenderOutput(
            attributedString: attributed,
            plainText: "Hello world",
            diagnostics: []
        ))

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test"))
        cell.configure(
            row: makeRow(content: content, isStreaming: false),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(!cell.hasRenderControllerForTesting)
        let applied = cell.attributedStringForTesting
        let color = applied.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.systemRed)
    }

    @Test("Cache-hit rich apply invalidates row height when intrinsic height changes")
    func cacheHitRichApplyInvalidatesRowHeightWhenHeightChanges() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let table = MessageTableView()
        let container = AppContainer.forTesting(settings: .testDefault)
        let messageID = try #require(UUID(uuidString: "ABABABAB-7777-7777-7777-777777777777"))
        let seed = ChatMessage(id: messageID, role: .assistant, content: "seed")

        table.apply(
            messages: [seed],
            activeConversationID: "conv-height",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        table.prepareCellForTesting(row: 0)
        table.updateStreamingCell(
            messageID: messageID,
            content: Array(repeating: "line", count: 18).joined(separator: "\n")
        )

        let finalContent = "final **done**"
        let prewarmInput = MessageRenderInput(
            content: finalContent,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        )
        await runtime.prewarm(inputs: [prewarmInput])

        table.apply(
            messages: [ChatMessage(id: messageID, role: .assistant, content: finalContent)],
            activeConversationID: "conv-height",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        table.prepareCellForTesting(row: 0)

        let cell = try #require(table.visibleCellForTesting(row: 0))
        #expect(cell.richOutputHeightInvalidationCountForTesting >= 1)
    }

    @Test("Non-streaming render completion writes row height cache")
    func nonStreamingRenderCachesHeight() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let input = MessageRenderInput(
            content: "height cache **content**",
            availableWidth: 560,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        )

        _ = renderer.render(input)
        let cachedHeight = runtime.cachedRowHeight(for: input)

        #expect(cachedHeight != nil)
        #expect((cachedHeight ?? 0) > 0)
    }

    @Test("Cache-first configure sets cached intrinsic height on cache hit")
    func cacheHitSetsCachedIntrinsicHeight() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let availableWidth: CGFloat = 600
        let contentWidth = max(1, availableWidth - HushSpacing.xl * 2)
        let content = "row height **cache-hit**"
        let input = MessageRenderInput(
            content: content,
            availableWidth: contentWidth,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        )
        _ = renderer.render(input)

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-height-hit"))
        cell.configure(
            row: makeRow(content: content, isStreaming: false),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(cell.cachedIntrinsicHeightForTesting != nil)
    }

    @Test("Cache miss uses plain fallback then updates to rich rendering")
    func cacheMissFallsBackThenUpdates() async {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let content = "Hello **world**"
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test"))
        cell.configure(
            row: makeRow(content: content, isStreaming: false),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(cell.hasRenderControllerForTesting)
        #expect(cell.attributedStringForTesting.string == content)
        #expect(cell.cachedIntrinsicHeightForTesting == nil)

        let deadline = ContinuousClock.now + .seconds(2)
        while cell.attributedStringForTesting.string == content, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(!cell.attributedStringForTesting.string.contains("**"))
    }

    @Test("Render cache eviction removes corresponding row height cache")
    func evictionRemovesRowHeightCacheEntry() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 1),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let style = RenderStyle.fromTheme()
        let inputA = MessageRenderInput(
            content: "A **cached**",
            availableWidth: 500,
            style: style,
            isStreaming: false
        )
        let inputB = MessageRenderInput(
            content: "B **cached**",
            availableWidth: 500,
            style: style,
            isStreaming: false
        )

        _ = renderer.render(inputA)
        #expect(runtime.cachedRowHeight(for: inputA) != nil)

        _ = renderer.render(inputB)
        #expect(runtime.cachedRowHeight(for: inputA) == nil)
        #expect(runtime.cachedRowHeight(for: inputB) != nil)
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

    @Test("Cancel render work releases RenderController")
    func cancelRenderWorkReleasesController() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let content = "Hello **cancel**"
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-cancel"))
        cell.configure(
            row: makeRow(content: content, isStreaming: false),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(cell.hasRenderControllerForTesting)
        cell.cancelRenderWork()
        #expect(!cell.hasRenderControllerForTesting)
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

    @Test("Fingerprint change triggers a new render request (non-streaming)")
    func fingerprintChangeTriggersNewRequest() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "77777777-7777-7777-7777-777777777777"))
        let first = makeRow(
            content: "streaming partial",
            isStreaming: false,
            id: messageID,
            generation: 1
        )
        let changed = makeRow(
            content: "streaming partial + token",
            isStreaming: false,
            id: messageID,
            generation: 1
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-dedup-miss"))

        cell.configure(
            row: first,
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        let firstCount = cell.renderRequestCountForTesting
        #expect(firstCount == 1)

        cell.configure(
            row: changed,
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        #expect(cell.renderRequestCountForTesting == firstCount + 1)
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

    @Test("Non-streaming output apply guard requires content match")
    func nonStreamingOutputApplyGuardRequiresExactContentMatch() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-output-guard-final"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "C2C2C2C2-7777-7777-7777-777777777777"))
        let finalRow = makeRow(content: "final **done**", isStreaming: false, id: messageID)

        cell.configure(
            row: finalRow,
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(cell.shouldApplyOutputForTesting(
            plainText: "final",
            observedRow: finalRow
        ) == false)
        #expect(cell.shouldApplyOutputForTesting(
            plainText: "final **done**",
            observedRow: finalRow
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
    func finalConfigureKeepsPlainTextWhileRichPending() async throws {
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

    @Test("Width change invalidates height cache entry")
    func widthChangeInvalidatesHeightCache() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let style = RenderStyle.fromTheme()
        let content = "width-dependent **content**"

        let inputAt500 = MessageRenderInput(
            content: content,
            availableWidth: 500,
            style: style,
            isStreaming: false
        )
        _ = renderer.render(inputAt500)
        #expect(runtime.cachedRowHeight(for: inputAt500) != nil)

        let inputAt600 = MessageRenderInput(
            content: content,
            availableWidth: 600,
            style: style,
            isStreaming: false
        )
        #expect(runtime.cachedRowHeight(for: inputAt600) == nil)
    }
}
