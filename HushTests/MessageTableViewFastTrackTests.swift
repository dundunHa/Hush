import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("MessageTableView Fast-Track")
struct MessageTableViewFastTrackTests {
    private func makeMessage(
        id: UUID,
        role: ChatRole = .assistant,
        content: String
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_700_000_123)
        )
    }

    private func makeRuntime() -> MessageRenderRuntime {
        MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 16),
                mathCache: MathRenderCache(capacity: 16)
            ),
            scheduler: ConversationRenderScheduler()
        )
    }

    @Test("updateStreamingCell locates row by messageID instead of assuming last row")
    func updateStreamingCellLocatesByMessageID() throws {
        let table = MessageTableView()
        let runtime = makeRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let firstID = try #require(UUID(uuidString: "11111111-AAAA-BBBB-CCCC-111111111111"))
        let lastID = try #require(UUID(uuidString: "22222222-AAAA-BBBB-CCCC-222222222222"))
        let first = makeMessage(id: firstID, content: "first")
        let last = makeMessage(id: lastID, content: "last")

        table.apply(
            messages: [first, last],
            activeConversationID: "conv-fast",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        table.prepareCellForTesting(row: 0)
        table.prepareCellForTesting(row: 1)

        table.updateStreamingCell(messageID: firstID, content: "first-updated")

        let firstCell = try? #require(table.visibleCellForTesting(row: 0))
        let lastCell = try? #require(table.visibleCellForTesting(row: 1))
        #expect(firstCell?.attributedStringForTesting.string == "first-updated")
        #expect(lastCell?.attributedStringForTesting.string == "last")
    }

    @Test("updateStreamingCell no-ops when messageID is stale or list is empty")
    func updateStreamingCellNoOpsForStaleOrEmptyMessageID() throws {
        let table = MessageTableView()
        let runtime = makeRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)
        let messageID = try #require(UUID(uuidString: "33333333-AAAA-BBBB-CCCC-333333333333"))
        let message = makeMessage(id: messageID, content: "seed")

        table.apply(
            messages: [message],
            activeConversationID: "conv-fast",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        table.prepareCellForTesting(row: 0)
        let cell = try? #require(table.visibleCellForTesting(row: 0))
        let before = cell?.streamingUpdateAssignmentCountForTesting ?? 0

        try table.updateStreamingCell(
            messageID: #require(UUID(uuidString: "44444444-AAAA-BBBB-CCCC-444444444444")),
            content: "stale"
        )
        #expect(cell?.streamingUpdateAssignmentCountForTesting == before)

        table.apply(
            messages: [],
            activeConversationID: "conv-fast",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        try table.updateStreamingCell(
            messageID: #require(UUID(uuidString: "55555555-AAAA-BBBB-CCCC-555555555555")),
            content: "noop"
        )
    }

    @Test("updateStreamingCell coalesces identical content writes")
    func updateStreamingCellCoalescesIdenticalContent() throws {
        let table = MessageTableView()
        let runtime = makeRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)
        let messageID = try #require(UUID(uuidString: "66666666-AAAA-BBBB-CCCC-666666666666"))
        let message = makeMessage(id: messageID, content: "base")

        table.apply(
            messages: [message],
            activeConversationID: "conv-fast",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        table.prepareCellForTesting(row: 0)
        let cell = try? #require(table.visibleCellForTesting(row: 0))
        let baseline = cell?.streamingUpdateAssignmentCountForTesting ?? 0

        table.updateStreamingCell(messageID: messageID, content: "same-content")
        let firstCount = cell?.streamingUpdateAssignmentCountForTesting ?? 0

        table.updateStreamingCell(messageID: messageID, content: "same-content")
        let secondCount = cell?.streamingUpdateAssignmentCountForTesting ?? 0

        #expect(firstCount == baseline + 1)
        #expect(secondCount == firstCount)
    }

    @Test("updateStreamingCell triggers height invalidation when height changes")
    func updateStreamingCellTriggersHeightInvalidation() throws {
        let table = MessageTableView()
        let runtime = makeRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)
        let messageID = try #require(UUID(uuidString: "77777777-AAAA-BBBB-CCCC-777777777777"))
        let message = makeMessage(id: messageID, content: "short")

        table.apply(
            messages: [message],
            activeConversationID: "conv-fast",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        table.prepareCellForTesting(row: 0)

        let baselineInvalidations = table.heightInvalidationCountForTesting

        table.updateStreamingCell(messageID: messageID, content: "short\nwith\nmultiple\nlines\nfor\nheight")
        let afterFirst = table.heightInvalidationCountForTesting

        table.updateStreamingCell(messageID: messageID, content: "short\nwith\nmultiple\nlines\nfor\nheight")
        let afterSame = table.heightInvalidationCountForTesting

        #expect(afterFirst >= baselineInvalidations)
        #expect(afterSame == afterFirst)
    }

    @Test("updateStreamingCell scrolls to bottom only when not scrolled up")
    func updateStreamingCellScrollBehavior() throws {
        let table = MessageTableView()
        let runtime = makeRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)
        let messageID = try #require(UUID(uuidString: "88888888-AAAA-BBBB-CCCC-888888888888"))
        let message = makeMessage(id: messageID, content: "seed")

        table.apply(
            messages: [message],
            activeConversationID: "conv-fast",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        table.prepareCellForTesting(row: 0)

        let baselineScrollCount = table.scrollToBottomCountForTesting

        table.userHasScrolledUp = false
        table.updateStreamingCell(messageID: messageID, content: "content-a")
        let afterFollowing = table.scrollToBottomCountForTesting
        #expect(afterFollowing == baselineScrollCount + 1)

        table.userHasScrolledUp = true
        table.updateStreamingCell(messageID: messageID, content: "content-b")
        let afterScrolledUp = table.scrollToBottomCountForTesting
        #expect(afterScrolledUp == afterFollowing)
    }
}
