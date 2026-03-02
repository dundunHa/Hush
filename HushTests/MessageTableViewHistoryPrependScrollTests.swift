import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("MessageTableView History Prepend Scroll")
struct MessageTableViewHistoryPrependScrollTests {
    private func makeMessage(id: UUID, content: String) -> ChatMessage {
        ChatMessage(
            id: id,
            role: .user,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
    }

    @Test("Prepending older messages preserves top visible anchor when scrolled up")
    func prependPreservesAnchorWhenScrolledUp() {
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let table = MessageTableView()

        let host = NSView()
        host.addSubview(table)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            table.topAnchor.constraint(equalTo: host.topAnchor),
            table.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.display()
        host.layoutSubtreeIfNeeded()
        defer {
            window.contentView = nil
            window.orderOut(nil)
            withExtendedLifetime(window) {}
        }

        let initialIDs = (0 ..< 20).map { _ in UUID() }
        let initialMessages = initialIDs.map { id in
            makeMessage(
                id: id,
                content: "Initial message \(id.uuidString)\n" + String(repeating: "x", count: 200)
            )
        }

        table.apply(
            messages: initialMessages,
            activeConversationID: "conv-prepend-scroll",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        host.layoutSubtreeIfNeeded()

        let desiredAnchorRowIndex = 6
        #expect(desiredAnchorRowIndex < table.tableView.numberOfRows)
        let desiredAnchorRect = table.tableView.rect(ofRow: desiredAnchorRowIndex)
        table.setScrollOriginYForTesting(desiredAnchorRect.origin.y)
        host.layoutSubtreeIfNeeded()

        let visibleBefore = table.tableView.rows(in: table.tableView.visibleRect)
        #expect(visibleBefore.length > 0)
        #expect(visibleBefore.location != NSNotFound)
        #expect(visibleBefore.location > 0)
        let anchorID = table.rows[visibleBefore.location].message.id

        // Simulate user breakaway from tail-follow while paging older history.
        table.userHasScrolledUp = true

        let olderMessages = (0 ..< 9).map { index in
            makeMessage(
                id: UUID(),
                content: "Older message \(index)\n" + String(repeating: "y", count: 220)
            )
        }

        table.apply(
            messages: olderMessages + initialMessages,
            activeConversationID: "conv-prepend-scroll",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )
        host.layoutSubtreeIfNeeded()

        let visibleAfter = table.tableView.rows(in: table.tableView.visibleRect)
        #expect(visibleAfter.length > 0)
        #expect(visibleAfter.location != NSNotFound)
        let topIDAfter = table.rows[visibleAfter.location].message.id
        #expect(topIDAfter == anchorID)
    }
}
