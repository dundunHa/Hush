import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
extension CellCacheFirstStreamingTests {
    @Test("Closed inline math upgrades streaming output to rich render before completion")
    func streamingClosedMathRendersBeforeCompletion() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-streaming-math"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "BABABABA-7777-7777-7777-777777777777"))
        let partial = "公式 $y = \\sin"

        cell.configure(
            row: makeRow(content: partial, isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        #expect(cell.renderRequestCountForTesting == 0)
        #expect(cell.attributedStringForTesting.string == partial)

        let renderedFormula = "公式 $y = \\sin x$ 为核心"
        cell.updateStreamingText(renderedFormula)
        #expect(cell.renderRequestCountForTesting > 0)

        let renderDeadline = ContinuousClock.now + .seconds(2)
        while cell.attributedStringForTesting.string.contains("$"),
              ContinuousClock.now < renderDeadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }

        let richString = cell.attributedStringForTesting.string
        #expect(!richString.contains("$"))
        #expect(richString.contains("公式 "))
        #expect(richString.contains(" 为核心"))

        let appendedText = "公式 $y = \\sin x$ 为核心，继续解释"
        cell.updateStreamingText(appendedText)
        #expect(!cell.attributedStringForTesting.string.contains("$"))

        let appendedDeadline = ContinuousClock.now + .seconds(2)
        while !cell.attributedStringForTesting.string.contains("继续解释"),
              ContinuousClock.now < appendedDeadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }

        let appendedRichString = cell.attributedStringForTesting.string
        #expect(!appendedRichString.contains("$"))
        #expect(appendedRichString.contains("继续解释"))
    }

    @Test("Closed markdown emphasis upgrades streaming output to rich render before completion")
    func streamingClosedMarkdownRendersBeforeCompletion() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-streaming-markdown"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "BDBDBDBD-7777-7777-7777-777777777777"))
        let partial = "Hello **wor"

        cell.configure(
            row: makeRow(content: partial, isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )
        #expect(cell.renderRequestCountForTesting == 0)
        #expect(cell.attributedStringForTesting.string == partial)

        let renderedMarkdown = "Hello **world**"
        cell.updateStreamingText(renderedMarkdown)
        #expect(cell.renderRequestCountForTesting > 0)

        let renderDeadline = ContinuousClock.now + .seconds(2)
        while cell.attributedStringForTesting.string.contains("**"),
              ContinuousClock.now < renderDeadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }

        let richString = cell.attributedStringForTesting.string
        #expect(!richString.contains("**"))
        #expect(richString == "Hello world")
    }

    @Test("Streaming rich render accepts intermediate growth after formula is already visible")
    func streamingRichRenderAcceptsIntermediateGrowth() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-streaming-math-growth"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "BCBCBCBC-7777-7777-7777-777777777777"))
        let renderedFormula = "公式 $y = \\sin x$ 为核心"

        cell.configure(
            row: makeRow(content: renderedFormula, isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        let richDeadline = ContinuousClock.now + .seconds(2)
        while cell.attributedStringForTesting.string.contains("$"),
              ContinuousClock.now < richDeadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }

        let intermediate = renderedFormula + "，继续解释第一段"
        let latest = intermediate + "，以及第二段补充"

        cell.updateStreamingText(intermediate)
        cell.updateStreamingText(latest)

        #expect(cell.shouldApplyOutputForTesting(
            plainText: intermediate,
            observedRow: makeRow(content: latest, isStreaming: true, id: messageID)
        ))
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
        #expect(cell.hasRenderControllerForTesting)

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

    @Test("Final configure preserves streaming rich output while final rich render is pending")
    func finalConfigurePreservesStreamingRichOutputWhileFinalRichPending() async throws {
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
        let initialContent = "Hello **world**"

        cell.configure(
            row: makeRow(content: initialContent, isStreaming: true, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        let richDeadline = ContinuousClock.now + .seconds(2)
        while cell.attributedStringForTesting.string.contains("**"),
              ContinuousClock.now < richDeadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(cell.attributedStringForTesting.string == "Hello world")
        #expect(cell.currentVisiblePlainTextForTesting == initialContent)

        let finalContent = "Hello **world** and **friends**"
        cell.configure(
            row: makeRow(content: finalContent, isStreaming: false, id: messageID),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(!cell.attributedStringForTesting.string.contains("**"))
        #expect(cell.hasRenderControllerForTesting)

        let finalDeadline = ContinuousClock.now + .seconds(2)
        while cell.attributedStringForTesting.string != "Hello world and friends",
              ContinuousClock.now < finalDeadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(cell.attributedStringForTesting.string == "Hello world and friends")
    }
}
