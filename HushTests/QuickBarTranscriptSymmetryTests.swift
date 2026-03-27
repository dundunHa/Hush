// QuickBarTranscriptSymmetryTests.swift
//
// Outer-edge symmetry measurement infrastructure for Quick Bar transcript.
//
// Why outer-edge instead of cell-internal?
// ────────────────────────────────────────
// Cell-internal comparisons (e.g. bodyFrame vs contentContainer) only capture
// the padding *within* a single cell. They miss the asymmetry introduced by
// the transcript-level padding chain (QuickBarPanelView's horizontal padding
// layers) and the content-container centering logic.
//
// To verify that an assistant message's left visible gap and a user message's
// right visible gap are symmetric from the *user's perspective*, we need to
// measure from the outer edge of the transcript's readable area — the region
// that the MessageTableView actually fills. This file establishes:
//   - `transcriptReadableWidth`: derived from panel + padding constants
//   - `hostCell` / `makeQBRow`: reusable helpers matching the pattern in
//     MessageBodyAlignmentTests
//   - `outerEdgeTolerance`: shared tolerance for future symmetry assertions
//   - A smoke test proving the helpers compile and run correctly

import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Quick Bar transcript outer-edge symmetry helpers")
struct QuickBarTranscriptSymmetryTests {
    // MARK: - Constants

    private let outerEdgeTolerance: CGFloat = 1.0

    private var quickBarTrailingCompactInset: CGFloat {
        HushSpacing.xl + HushSpacing.sm
    }

    private var quickBarOpticalInsetDelta: CGFloat {
        quickBarTrailingCompactInset - HushSpacing.xl
    }

    // MARK: - Computed Layout Metrics

    /// The transcript readable width derived from panel and padding constants.
    ///
    /// QuickBarPanelView applies two horizontal padding layers on each side:
    ///   1. `.padding(.horizontal, HushSpacing.xs)` → 4 pt per side
    ///   2. `.padding(.horizontal, Layout.contentHorizontalInset)` → (sm + 2) = 10 pt per side
    /// Total per side = 14 pt, so readable width = panelWidth - 14*2.
    private var transcriptReadableWidth: CGFloat {
        QuickBarPanelReleaseMetrics.width
            - (HushSpacing.sm + 2) * 2
            - HushSpacing.xs * 2
    }

    // MARK: - Helpers

    private func hostCell(
        _ cell: NSView,
        width: CGFloat = 680,
        height: CGFloat = 320
    ) -> (window: NSWindow, host: NSView, container: NSView) {
        let host = NSView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.display()

        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: host.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])

        containerView.addSubview(cell)
        cell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cell.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            cell.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            cell.topAnchor.constraint(equalTo: containerView.topAnchor),
            cell.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        host.layoutSubtreeIfNeeded()

        return (window, host, containerView)
    }

    private func makeContainer() -> AppContainer {
        AppContainer.forTesting(
            messageRenderRuntime: MessageRenderRuntime(),
            enableStartupPrewarm: false
        )
    }

    private func makeTable(width: CGFloat, height: CGFloat = 420) -> MessageTableView {
        let table = MessageTableView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        table.layoutSubtreeIfNeeded()
        return table
    }

    private func makeQBRow(
        content: String,
        role: ChatRole = .assistant,
        isStreaming: Bool = false
    ) -> MessageTableView.RowModel {
        let message = ChatMessage(
            id: UUID(),
            role: role,
            content: content
        )
        return MessageTableView.RowModel(
            message: message,
            isStreaming: isStreaming,
            renderHint: MessageRenderHint(
                conversationID: "conv-symmetry",
                messageID: message.id,
                rankFromLatest: 0,
                isVisible: true,
                switchGeneration: 1
            )
        )
    }

    // MARK: - Smoke Test

    @Test("Smoke: assistant cell visibleTextFrame is obtainable at transcript readable width")
    func smokeAssistantCellVisibleTextFrameObtainable() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let cell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-smoke-assistant")
        )
        let hosted = hostCell(cell, width: transcriptReadableWidth)
        defer {
            hosted.window.contentView = nil
            hosted.window.orderOut(nil)
            withExtendedLifetime(hosted.window) {}
        }

        cell.configure(
            row: makeQBRow(content: "Hello, how can I help?", role: .assistant),
            runtime: runtime,
            availableWidth: hosted.container.bounds.width,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        let visibleFrame = cell.visibleTextFrameForTesting

        #expect(visibleFrame.width > 0, "visibleTextFrame should have positive width")
        #expect(visibleFrame.minX.isFinite, "visibleTextFrame.minX should be finite")
        #expect(visibleFrame.minX >= 0, "visibleTextFrame.minX should be non-negative")

        let assistantLeftGap = visibleFrame.minX
        #expect(assistantLeftGap >= 0, "assistant left gap should be non-negative")
    }

    // MARK: - Compact Plain-Text Outer-Edge Symmetry (RED until fix)

    // These tests verify that for compact plain-text messages, the outer-edge gap
    // of an assistant message (left side) mirrors the outer-edge gap of a user
    // message (right side). They are expected to FAIL (RED) until the body lane
    // constraints are fixed in Task 5/6/7.

    @Test("Short text outer-edge gap symmetry should match between assistant and user (RED until fixed)")
    func compactShortTextOuterEdgeGapsAreSymmetric() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        // Use similar-length strings to avoid length-based geometric noise.
        // "Hello!" = 6 ASCII chars, "你好世界!" = 5 CJK chars (visually similar compact width)
        let assistantCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-short-assistant")
        )
        let userCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-short-user")
        )

        let hostedAssistant = hostCell(assistantCell, width: transcriptReadableWidth)
        defer {
            hostedAssistant.window.contentView = nil
            hostedAssistant.window.orderOut(nil)
            withExtendedLifetime(hostedAssistant.window) {}
        }
        let hostedUser = hostCell(userCell, width: transcriptReadableWidth)
        defer {
            hostedUser.window.contentView = nil
            hostedUser.window.orderOut(nil)
            withExtendedLifetime(hostedUser.window) {}
        }

        assistantCell.configure(
            row: makeQBRow(content: "Hello!", role: .assistant),
            runtime: runtime,
            availableWidth: hostedAssistant.container.bounds.width,
            container: nil
        )
        userCell.configure(
            row: makeQBRow(content: "你好世界!", role: .user),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )

        hostedAssistant.host.layoutSubtreeIfNeeded()
        hostedUser.host.layoutSubtreeIfNeeded()

        let assistantBodyLeftGap = assistantCell.bodyFrameForTesting.minX
        let userBodyRightGap = hostedUser.container.bounds.width - userCell.bodyFrameForTesting.maxX

        let assistantVisibleLeftGap = assistantCell.visibleTextFrameForTesting.minX
        let userVisibleRightGap = hostedUser.container.bounds.width - userCell.visibleTextFrameForTesting.maxX

        #expect(
            abs((userBodyRightGap - assistantBodyLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            Body frame optical compensation mismatch (short text):
            assistantBodyLeftGap=\(assistantBodyLeftGap), userBodyRightGap=\(userBodyRightGap),
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )
        #expect(
            abs((userVisibleRightGap - assistantVisibleLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            Visible text optical compensation mismatch (short text):
            assistantVisibleLeftGap=\(assistantVisibleLeftGap), userVisibleRightGap=\(userVisibleRightGap),
            delta=\(userVisibleRightGap - assistantVisibleLeftGap)
            """
        )
    }

    @Test("Long text outer-edge gap symmetry should match between assistant and user (RED until fixed)")
    func compactLongTextOuterEdgeGapsAreSymmetric() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        // 30 ASCII chars vs 17 CJK chars (~34 display units) — similar rendered width
        let assistantCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-long-assistant")
        )
        let userCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-long-user")
        )

        let hostedAssistant = hostCell(assistantCell, width: transcriptReadableWidth)
        defer {
            hostedAssistant.window.contentView = nil
            hostedAssistant.window.orderOut(nil)
            withExtendedLifetime(hostedAssistant.window) {}
        }
        let hostedUser = hostCell(userCell, width: transcriptReadableWidth)
        defer {
            hostedUser.window.contentView = nil
            hostedUser.window.orderOut(nil)
            withExtendedLifetime(hostedUser.window) {}
        }

        assistantCell.configure(
            row: makeQBRow(content: "The quick brown fox jumps over!", role: .assistant),
            runtime: runtime,
            availableWidth: hostedAssistant.container.bounds.width,
            container: nil
        )
        userCell.configure(
            row: makeQBRow(content: "敏捷的棕色狐狸跳过了懒狗旁边的围栏!", role: .user),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )

        hostedAssistant.host.layoutSubtreeIfNeeded()
        hostedUser.host.layoutSubtreeIfNeeded()

        let assistantBodyLeftGap = assistantCell.bodyFrameForTesting.minX
        let userBodyRightGap = hostedUser.container.bounds.width - userCell.bodyFrameForTesting.maxX

        let assistantVisibleLeftGap = assistantCell.visibleTextFrameForTesting.minX
        let userVisibleRightGap = hostedUser.container.bounds.width - userCell.visibleTextFrameForTesting.maxX

        #expect(
            abs((userBodyRightGap - assistantBodyLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            Body frame optical compensation mismatch (long text):
            assistantBodyLeftGap=\(assistantBodyLeftGap), userBodyRightGap=\(userBodyRightGap),
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )
        #expect(
            abs((userVisibleRightGap - assistantVisibleLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            Visible text optical compensation mismatch (long text):
            assistantVisibleLeftGap=\(assistantVisibleLeftGap), userVisibleRightGap=\(userVisibleRightGap),
            delta=\(userVisibleRightGap - assistantVisibleLeftGap)
            """
        )
    }

    // MARK: - Waiting-State Symmetry

    @Test("Waiting-state assistant body gap should match user trailing gap (may be RED)")
    func waitingStateAssistantAndUserOuterEdgeGapsAreSymmetric() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        // Assistant: streaming + empty content → waiting state → .leadingColumn
        let assistantCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-waiting-assistant")
        )
        let hostedAssistant = hostCell(assistantCell, width: transcriptReadableWidth)
        defer {
            hostedAssistant.window.contentView = nil
            hostedAssistant.window.orderOut(nil)
            withExtendedLifetime(hostedAssistant.window) {}
        }

        assistantCell.configure(
            row: makeQBRow(content: "", role: .assistant, isStreaming: true),
            runtime: runtime,
            availableWidth: hostedAssistant.container.bounds.width,
            container: nil
        )
        hostedAssistant.host.layoutSubtreeIfNeeded()

        // User: trailing column
        let userCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-waiting-user")
        )
        let hostedUser = hostCell(userCell, width: transcriptReadableWidth)
        defer {
            hostedUser.window.contentView = nil
            hostedUser.window.orderOut(nil)
            withExtendedLifetime(hostedUser.window) {}
        }

        userCell.configure(
            row: makeQBRow(content: "好的", role: .user),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )
        hostedUser.host.layoutSubtreeIfNeeded()

        // Body-frame layer gaps
        let assistantBodyLeftGap = assistantCell.bodyFrameForTesting.minX
        let userBodyRightGap = hostedUser.container.bounds.width - userCell.bodyFrameForTesting.maxX
        let bodyDelta = abs(assistantBodyLeftGap - userBodyRightGap)

        print("""
        [waiting-state body] assistantBodyLeftGap=\(assistantBodyLeftGap) \
        userBodyRightGap=\(userBodyRightGap) delta=\(bodyDelta)
        """)

        #expect(
            abs((userBodyRightGap - assistantBodyLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            Waiting-state body gap optical compensation mismatch: \
            assistantBodyLeftGap=\(assistantBodyLeftGap), \
            userBodyRightGap=\(userBodyRightGap), \
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )

        // Visible-text-frame layer gaps
        // Waiting state may have zero-width visible text; still measure for diagnostics.
        let assistantVisibleFrame = assistantCell.visibleTextFrameForTesting
        let userVisibleFrame = userCell.visibleTextFrameForTesting
        let assistantVisibleLeftGap = assistantVisibleFrame.minX
        let userVisibleRightGap = hostedUser.container.bounds.width - userVisibleFrame.maxX
        let visibleDelta = abs(assistantVisibleLeftGap - userVisibleRightGap)

        print("""
        [waiting-state visible] assistantVisibleLeftGap=\(assistantVisibleLeftGap) \
        userVisibleRightGap=\(userVisibleRightGap) delta=\(visibleDelta) \
        assistantVisibleWidth=\(assistantVisibleFrame.width) \
        userVisibleWidth=\(userVisibleFrame.width)
        """)

        // If waiting state has zero-width visible text, skip the visible-text assertion
        // but still log the values for diagnostics.
        if assistantVisibleFrame.width > 0, userVisibleFrame.width > 0 {
            #expect(
                abs((userVisibleRightGap - assistantVisibleLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
                """
                Waiting-state visible text optical compensation mismatch: \
                assistantVisibleLeftGap=\(assistantVisibleLeftGap), \
                userVisibleRightGap=\(userVisibleRightGap), \
                delta=\(userVisibleRightGap - assistantVisibleLeftGap)
                """
            )
        }
    }

    // MARK: - FullWidth / Rich Markdown Symmetry

    @Test("FullWidth rich assistant body gap should match user trailing gap (may be RED)")
    func fullWidthRichAssistantAndUserOuterEdgeGapsAreSymmetric() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        // Assistant: markdown heading → containsStableMarkdownCue → .fullWidth
        let assistantCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-fullwidth-assistant")
        )
        let hostedAssistant = hostCell(assistantCell, width: transcriptReadableWidth)
        defer {
            hostedAssistant.window.contentView = nil
            hostedAssistant.window.orderOut(nil)
            withExtendedLifetime(hostedAssistant.window) {}
        }

        assistantCell.configure(
            row: makeQBRow(
                content: "# Title\n\nSome paragraph text with enough words to fill a line.",
                role: .assistant,
                isStreaming: false
            ),
            runtime: runtime,
            availableWidth: hostedAssistant.container.bounds.width,
            container: nil
        )
        hostedAssistant.host.layoutSubtreeIfNeeded()

        // User: trailing column
        let userCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-fullwidth-user")
        )
        let hostedUser = hostCell(userCell, width: transcriptReadableWidth)
        defer {
            hostedUser.window.contentView = nil
            hostedUser.window.orderOut(nil)
            withExtendedLifetime(hostedUser.window) {}
        }

        userCell.configure(
            row: makeQBRow(content: "收到，谢谢", role: .user),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )
        hostedUser.host.layoutSubtreeIfNeeded()

        // Body-frame layer gaps
        let assistantBodyLeftGap = assistantCell.bodyFrameForTesting.minX
        let userBodyRightGap = hostedUser.container.bounds.width - userCell.bodyFrameForTesting.maxX
        let bodyDelta = abs(assistantBodyLeftGap - userBodyRightGap)

        print("""
        [fullWidth body] assistantBodyLeftGap=\(assistantBodyLeftGap) \
        userBodyRightGap=\(userBodyRightGap) delta=\(bodyDelta)
        """)

        #expect(
            abs((userBodyRightGap - assistantBodyLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            FullWidth body gap optical compensation mismatch: \
            assistantBodyLeftGap=\(assistantBodyLeftGap), \
            userBodyRightGap=\(userBodyRightGap), \
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )

        // Visible-text-frame layer gaps
        let assistantVisibleFrame = assistantCell.visibleTextFrameForTesting
        let userVisibleFrame = userCell.visibleTextFrameForTesting
        let assistantVisibleLeftGap = assistantVisibleFrame.minX
        let userVisibleRightGap = hostedUser.container.bounds.width - userVisibleFrame.maxX
        let visibleDelta = abs(assistantVisibleLeftGap - userVisibleRightGap)

        print("""
        [fullWidth visible] assistantVisibleLeftGap=\(assistantVisibleLeftGap) \
        userVisibleRightGap=\(userVisibleRightGap) delta=\(visibleDelta) \
        assistantVisibleWidth=\(assistantVisibleFrame.width) \
        userVisibleWidth=\(userVisibleFrame.width)
        """)

        if assistantVisibleFrame.width > 0, userVisibleFrame.width > 0 {
            #expect(
                abs((userVisibleRightGap - assistantVisibleLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
                """
                FullWidth visible text optical compensation mismatch: \
                assistantVisibleLeftGap=\(assistantVisibleLeftGap), \
                userVisibleRightGap=\(userVisibleRightGap), \
                delta=\(userVisibleRightGap - assistantVisibleLeftGap)
                """
            )
        }
    }

    // MARK: - Real MessageTableView Path Symmetry

    @Test("Real quick bar table path keeps compact outer-edge gaps symmetric")
    func realQuickBarTablePathKeepsCompactOuterEdgeGapsSymmetric() throws {
        let container = makeContainer()
        let table = makeTable(width: transcriptReadableWidth)
        let assistant = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "Hi! How can I help you today?"
        )
        let user = ChatMessage(
            id: UUID(),
            role: .user,
            content: "say hi"
        )

        table.apply(
            messages: [assistant, user],
            activeConversationID: "conv-quickbar-table-compact",
            isActiveConversationSending: false,
            switchGeneration: 1,
            theme: container.settings.theme,
            surfaceStyle: .quickBar,
            runtime: container.messageRenderRuntime,
            container: container
        )
        table.layoutSubtreeIfNeeded()
        table.prepareCellForTesting(row: 0)
        table.prepareCellForTesting(row: 1)

        let assistantCell = try #require(table.visibleCellForTesting(row: 0))
        let userCell = try #require(table.visibleCellForTesting(row: 1))

        let assistantBodyFrame = assistantCell.convert(assistantCell.bodyFrameForTesting, to: table)
        let userBodyFrame = userCell.convert(userCell.bodyFrameForTesting, to: table)
        let assistantVisibleFrame = assistantCell.convert(assistantCell.visibleTextFrameForTesting, to: table)
        let userVisibleFrame = userCell.convert(userCell.visibleTextFrameForTesting, to: table)

        let assistantBodyLeftGap = assistantBodyFrame.minX
        let userBodyRightGap = table.bounds.width - userBodyFrame.maxX
        let assistantVisibleLeftGap = assistantVisibleFrame.minX
        let userVisibleRightGap = table.bounds.width - userVisibleFrame.maxX

        #expect(
            abs((userBodyRightGap - assistantBodyLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            Real table path body optical compensation mismatch:
            assistantBodyLeftGap=\(assistantBodyLeftGap), userBodyRightGap=\(userBodyRightGap),
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )
        #expect(
            abs((userVisibleRightGap - assistantVisibleLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            Real table path visible-text optical compensation mismatch:
            assistantVisibleLeftGap=\(assistantVisibleLeftGap), userVisibleRightGap=\(userVisibleRightGap),
            delta=\(userVisibleRightGap - assistantVisibleLeftGap)
            """
        )
    }

    @Test("Real quick bar table path keeps waiting-state outer-edge gaps symmetric")
    func realQuickBarTablePathKeepsWaitingStateOuterEdgeGapsSymmetric() throws {
        let container = makeContainer()
        let table = makeTable(width: transcriptReadableWidth)
        let user = ChatMessage(
            id: UUID(),
            role: .user,
            content: "say hi"
        )
        let assistant = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: ""
        )

        table.apply(
            messages: [user, assistant],
            activeConversationID: "conv-quickbar-table-waiting",
            isActiveConversationSending: true,
            switchGeneration: 1,
            theme: container.settings.theme,
            surfaceStyle: .quickBar,
            runtime: container.messageRenderRuntime,
            container: container
        )
        table.layoutSubtreeIfNeeded()
        table.prepareCellForTesting(row: 0)
        table.prepareCellForTesting(row: 1)

        let userCell = try #require(table.visibleCellForTesting(row: 0))
        let assistantCell = try #require(table.visibleCellForTesting(row: 1))

        let assistantBodyFrame = assistantCell.convert(assistantCell.bodyFrameForTesting, to: table)
        let userBodyFrame = userCell.convert(userCell.bodyFrameForTesting, to: table)
        let assistantVisibleFrame = assistantCell.convert(assistantCell.visibleTextFrameForTesting, to: table)
        let userVisibleFrame = userCell.convert(userCell.visibleTextFrameForTesting, to: table)

        let assistantBodyLeftGap = assistantBodyFrame.minX
        let userBodyRightGap = table.bounds.width - userBodyFrame.maxX
        let assistantVisibleLeftGap = assistantVisibleFrame.minX
        let userVisibleRightGap = table.bounds.width - userVisibleFrame.maxX

        #expect(
            abs((userBodyRightGap - assistantBodyLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            Real table path waiting body optical compensation mismatch:
            assistantBodyLeftGap=\(assistantBodyLeftGap), userBodyRightGap=\(userBodyRightGap),
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )
        #expect(
            abs((userVisibleRightGap - assistantVisibleLeftGap) - quickBarOpticalInsetDelta) <= outerEdgeTolerance,
            """
            Real table path waiting visible-text optical compensation mismatch:
            assistantVisibleLeftGap=\(assistantVisibleLeftGap), userVisibleRightGap=\(userVisibleRightGap),
            delta=\(userVisibleRightGap - assistantVisibleLeftGap)
            """
        )
    }
}
