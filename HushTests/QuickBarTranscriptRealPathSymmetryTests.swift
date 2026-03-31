import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
struct QuickBarTranscriptRealPathSymmetryTests {
    private let outerEdgeTolerance: CGFloat = 1.0

    private var transcriptReadableWidth: CGFloat {
        QuickBarPanelReleaseMetrics.width
            - (HushSpacing.sm + 2) * 2
            - HushSpacing.xs * 2
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
            abs(userBodyRightGap - assistantBodyLeftGap) <= outerEdgeTolerance,
            """
            Real table path body symmetry mismatch:
            assistantBodyLeftGap=\(assistantBodyLeftGap), userBodyRightGap=\(userBodyRightGap),
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )
        #expect(
            abs(userVisibleRightGap - assistantVisibleLeftGap) <= outerEdgeTolerance,
            """
            Real table path visible-text symmetry mismatch:
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
            abs(userBodyRightGap - assistantBodyLeftGap) <= outerEdgeTolerance,
            """
            Real table path waiting body symmetry mismatch:
            assistantBodyLeftGap=\(assistantBodyLeftGap), userBodyRightGap=\(userBodyRightGap),
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )
        #expect(
            abs(userVisibleRightGap - assistantVisibleLeftGap) <= outerEdgeTolerance,
            """
            Real table path waiting visible-text symmetry mismatch:
            assistantVisibleLeftGap=\(assistantVisibleLeftGap), userVisibleRightGap=\(userVisibleRightGap),
            delta=\(userVisibleRightGap - assistantVisibleLeftGap)
            """
        )
    }
}
