import AppKit
import Foundation
@testable import Hush
import Testing

extension QuickBarTranscriptSymmetryTests {
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

        let assistantCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-fullwidth-assistant")
        )
        let hostedAssistant = hostCell(assistantCell, width: transcriptReadableWidth)
        defer { releaseHostedCell(hostedAssistant) }

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

        let userCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-fullwidth-user")
        )
        let hostedUser = hostCell(userCell, width: transcriptReadableWidth)
        defer { releaseHostedCell(hostedUser) }

        userCell.configure(
            row: makeQBRow(content: "收到，谢谢", role: .user),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )
        hostedUser.host.layoutSubtreeIfNeeded()

        assertBodyGapSymmetry(
            assistantBodyLeftGap: assistantCell.bodyFrameForTesting.minX,
            userBodyRightGap: hostedUser.container.bounds.width - userCell.bodyFrameForTesting.maxX,
            label: "FullWidth"
        )

        let assistantVisibleFrame = assistantCell.visibleTextFrameForTesting
        let userVisibleFrame = userCell.visibleTextFrameForTesting
        if assistantVisibleFrame.width > 0, userVisibleFrame.width > 0 {
            assertVisibleGapSymmetry(
                assistantVisibleLeftGap: assistantVisibleFrame.minX,
                userVisibleRightGap: hostedUser.container.bounds.width - userVisibleFrame.maxX,
                label: "FullWidth"
            )
        }
    }

    @Test("Real quick bar table path keeps compact outer-edge gaps symmetric")
    func realQuickBarTablePathKeepsCompactOuterEdgeGapsSymmetric() throws {
        let table = makeTable(width: transcriptReadableWidth)
        let assistant = ChatMessage(id: UUID(), role: .assistant, content: "Hi! How can I help you today?")
        let user = ChatMessage(id: UUID(), role: .user, content: "say hi")

        applyQuickBarTable(
            table,
            messages: [assistant, user],
            activeConversationID: "conv-quickbar-table-compact",
            isSending: false
        )
        let assistantCell = try #require(table.visibleCellForTesting(row: 0))
        let userCell = try #require(table.visibleCellForTesting(row: 1))

        assertTableGapSymmetry(
            table: table,
            assistantCell: assistantCell,
            userCell: userCell,
            label: "Real table path"
        )
    }

    @Test("Real quick bar table path keeps waiting-state outer-edge gaps symmetric")
    func realQuickBarTablePathKeepsWaitingStateOuterEdgeGapsSymmetric() throws {
        let table = makeTable(width: transcriptReadableWidth)
        let user = ChatMessage(id: UUID(), role: .user, content: "say hi")
        let assistant = ChatMessage(id: UUID(), role: .assistant, content: "")

        applyQuickBarTable(
            table,
            messages: [user, assistant],
            activeConversationID: "conv-quickbar-table-waiting",
            isSending: true
        )
        let userCell = try #require(table.visibleCellForTesting(row: 0))
        let assistantCell = try #require(table.visibleCellForTesting(row: 1))

        assertTableGapSymmetry(
            table: table,
            assistantCell: assistantCell,
            userCell: userCell,
            label: "Real table path waiting"
        )
    }

    private func releaseHostedCell(_ hosted: (window: NSWindow, host: NSView, container: NSView)) {
        hosted.window.contentView = nil
        hosted.window.orderOut(nil)
        withExtendedLifetime(hosted.window) {}
    }

    private func applyQuickBarTable(
        _ table: MessageTableView,
        messages: [ChatMessage],
        activeConversationID: String,
        isSending: Bool
    ) {
        let container = makeContainer()
        table.apply(
            messages: messages,
            activeConversationID: activeConversationID,
            isActiveConversationSending: isSending,
            switchGeneration: 1,
            theme: container.settings.theme,
            surfaceStyle: .quickBar,
            runtime: container.messageRenderRuntime,
            container: container
        )
        table.layoutSubtreeIfNeeded()
        table.prepareCellForTesting(row: 0)
        table.prepareCellForTesting(row: 1)
    }

    private func assertTableGapSymmetry(
        table: MessageTableView,
        assistantCell: AnyMessageTableTestingRowView,
        userCell: AnyMessageTableTestingRowView,
        label: String
    ) {
        let assistantBodyFrame = assistantCell.convert(assistantCell.bodyFrameForTesting, to: table)
        let userBodyFrame = userCell.convert(userCell.bodyFrameForTesting, to: table)
        let assistantVisibleFrame = assistantCell.convert(assistantCell.visibleTextFrameForTesting, to: table)
        let userVisibleFrame = userCell.convert(userCell.visibleTextFrameForTesting, to: table)

        assertBodyGapSymmetry(
            assistantBodyLeftGap: assistantBodyFrame.minX,
            userBodyRightGap: table.bounds.width - userBodyFrame.maxX,
            label: label
        )
        assertVisibleGapSymmetry(
            assistantVisibleLeftGap: assistantVisibleFrame.minX,
            userVisibleRightGap: table.bounds.width - userVisibleFrame.maxX,
            label: label
        )
    }

    private func assertBodyGapSymmetry(
        assistantBodyLeftGap: CGFloat,
        userBodyRightGap: CGFloat,
        label: String
    ) {
        #expect(
            abs(userBodyRightGap - assistantBodyLeftGap) <= outerEdgeTolerance,
            """
            \(label) body symmetry mismatch:
            assistantBodyLeftGap=\(assistantBodyLeftGap), userBodyRightGap=\(userBodyRightGap),
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )
    }

    private func assertVisibleGapSymmetry(
        assistantVisibleLeftGap: CGFloat,
        userVisibleRightGap: CGFloat,
        label: String
    ) {
        #expect(
            abs(userVisibleRightGap - assistantVisibleLeftGap) <= outerEdgeTolerance,
            """
            \(label) visible-text symmetry mismatch:
            assistantVisibleLeftGap=\(assistantVisibleLeftGap), userVisibleRightGap=\(userVisibleRightGap),
            delta=\(userVisibleRightGap - assistantVisibleLeftGap)
            """
        )
    }
}
