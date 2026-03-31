import AppKit
import Foundation
@testable import Hush
import Testing

extension MessageTableViewHeightInvalidationScrollTests {
    @Test("Rich height invalidation keeps transcript pinned to bottom while following tail")
    func richHeightInvalidationKeepsBottomPinWhileFollowingTail() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 16),
            mathCache: MathRenderCache(capacity: 16)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let container = AppContainer.forTesting(settings: .testDefault)
        let harness = makeHostedTable()
        let table = harness.table
        let host = harness.host
        defer {
            harness.window.contentView = nil
            harness.window.orderOut(nil)
            withExtendedLifetime(harness.window) {}
        }

        let messageID = UUID()
        let content = """
        # Final Answer

        A long assistant message that should stay pinned to the latest content.

        | Feature | Description | Status |
        |---|---|---|
        | Auth | Login support | Done |
        | Search | Full-text | WIP |

        \(Array(repeating: "- item with some text", count: 260).joined(separator: "\n"))
        """

        table.apply(
            messages: [makeMessage(id: messageID, role: .assistant, content: content)],
            activeConversationID: "conv-height-invalidation-bottom-pin",
            isActiveConversationSending: false,
            switchGeneration: 1,
            theme: container.settings.theme,
            runtime: runtime,
            container: container
        )

        host.layoutSubtreeIfNeeded()
        table.prepareCellForTesting(row: 0)
        let cell = try #require(table.visibleCellForTesting(row: 0))
        cell.cancelRenderWork()

        table.userHasScrolledUp = false
        table.scrollToBottom()
        let before = table.scrollOriginYForTesting
        #expect(before > 0)

        _ = renderer.render(MessageRenderInput(
            content: content,
            availableWidth: contentWidth(for: table),
            style: RenderStyle.fromTheme(),
            isStreaming: false
        ))

        table.tableView.reloadData(
            forRowIndexes: IndexSet(integer: 0),
            columnIndexes: IndexSet(integer: 0)
        )
        host.layoutSubtreeIfNeeded()

        try await waitUntilPinnedToBottom(table: table, host: host)

        let after = table.scrollOriginYForTesting
        let maxScrollOriginY = table.maxScrollOriginYForTesting
        #expect(abs(after - maxScrollOriginY) <= 1.0)
        #expect(after >= before)
    }
}
