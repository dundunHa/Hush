import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
// swiftlint:disable:next type_name
struct MessageTableViewHeightInvalidationScrollTests {
    private func makeMessage(id: UUID, role: ChatRole, content: String) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_700_000_300)
        )
    }

    @Test("Rich height invalidation preserves scroll anchor while scrolled up")
    func richHeightInvalidationPreservesAnchor() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 16),
            mathCache: MathRenderCache(capacity: 16)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
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

        let messageID = UUID()
        let content = """
        # First Answer

        A long message to force scrolling.

        | Feature | Description | Status |
        |---|---|---|
        | Auth | Login support | Done |
        | Search | Full-text | WIP |

        \(Array(repeating: "- item with some text", count: 220).joined(separator: "\n"))
        """

        table.apply(
            messages: [makeMessage(id: messageID, role: .assistant, content: content)],
            activeConversationID: "conv-height-invalidation",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        // Ensure the row is instantiated and currently in plain fallback state.
        host.layoutSubtreeIfNeeded()
        table.prepareCellForTesting(row: 0)
        let cell = try #require(table.visibleCellForTesting(row: 0))
        cell.cancelRenderWork()

        // Scroll into the middle of the (single) huge row, then wait for scroll activity debounce.
        table.setScrollOriginYForTesting(200)
        table.userHasScrolledUp = true
        let before = table.scrollOriginYForTesting
        #expect(before >= 150)

        try? await Task.sleep(for: .milliseconds(200))

        // Populate the rich render cache for this message, then force a cell reload so the
        // cached rich output applies and triggers row-height invalidation.
        _ = renderer.render(MessageRenderInput(
            content: content,
            availableWidth: 800,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        ))

        table.tableView.reloadData(
            forRowIndexes: IndexSet(integer: 0),
            columnIndexes: IndexSet(integer: 0)
        )
        host.layoutSubtreeIfNeeded()

        // Allow the anchor-restore dispatch to run.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))

        let after = table.scrollOriginYForTesting
        #expect(abs(after - before) <= 1.0)
    }

    @Test("Rich height invalidation restores scroll anchor during live scrolling")
    func richHeightInvalidationRestoresAnchorDuringLiveScroll() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 16),
            mathCache: MathRenderCache(capacity: 16)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
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

        let messageID = UUID()
        let content = """
        # First Answer

        \(Array(repeating: "- item with some text", count: 240).joined(separator: "\n"))
        """

        table.apply(
            messages: [makeMessage(id: messageID, role: .assistant, content: content)],
            activeConversationID: "conv-height-invalidation-live-scroll",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        host.layoutSubtreeIfNeeded()
        table.prepareCellForTesting(row: 0)
        let cell = try #require(table.visibleCellForTesting(row: 0))
        cell.cancelRenderWork()

        table.setScrollOriginYForTesting(220)
        table.userHasScrolledUp = true
        table.simulateLiveScrollStartForTesting()
        #expect(table.isLiveScrollingForTesting)

        let before = table.scrollOriginYForTesting
        #expect(before >= 150)

        _ = renderer.render(MessageRenderInput(
            content: content,
            availableWidth: 800,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        ))

        table.tableView.reloadData(
            forRowIndexes: IndexSet(integer: 0),
            columnIndexes: IndexSet(integer: 0)
        )
        host.layoutSubtreeIfNeeded()

        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))

        let after = table.scrollOriginYForTesting
        #expect(abs(after - before) <= 1.0)
        #expect(table.pendingPinnedRowHeightInvalidationsCountForTesting > 0)
    }

    @Test("Pinned rich invalidation defers row-height updates during live scroll and flushes after")
    // swiftlint:disable:next function_body_length
    func pinnedInvalidationDefersDuringLiveScroll() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 16),
            mathCache: MathRenderCache(capacity: 16)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
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

        let messageID = UUID()
        let content = """
        # Answer

        A long message to force scrolling and a meaningful rich layout change.

        | Feature | Description | Status |
        |---|---|---|
        | Auth | Login support | Done |
        | Search | Full-text | WIP |

        \(Array(repeating: "- item with some text", count: 220).joined(separator: "\n"))
        """

        table.apply(
            messages: [makeMessage(id: messageID, role: .assistant, content: content)],
            activeConversationID: "conv-height-invalidation-defer",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        host.layoutSubtreeIfNeeded()
        table.prepareCellForTesting(row: 0)
        let cell = try #require(table.visibleCellForTesting(row: 0))
        cell.cancelRenderWork()

        table.setScrollOriginYForTesting(240)
        table.userHasScrolledUp = true
        let before = table.scrollOriginYForTesting
        #expect(before >= 150)

        // Warm render cache so the next reload is a cache-hit rich apply.
        _ = renderer.render(MessageRenderInput(
            content: content,
            availableWidth: 800,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        ))

        table.simulateLiveScrollStartForTesting()
        #expect(table.isLiveScrollingForTesting)

        table.tableView.reloadData(
            forRowIndexes: IndexSet(integer: 0),
            columnIndexes: IndexSet(integer: 0)
        )
        host.layoutSubtreeIfNeeded()

        let during = table.scrollOriginYForTesting
        #expect(abs(during - before) <= 1.0)
        #expect(table.pendingPinnedRowHeightInvalidationsCountForTesting > 0)

        table.simulateLiveScrollEndForTesting()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(250))

        let after = table.scrollOriginYForTesting
        #expect(abs(after - before) <= 1.0)
        #expect(table.pendingPinnedRowHeightInvalidationsCountForTesting == 0)
    }
}
