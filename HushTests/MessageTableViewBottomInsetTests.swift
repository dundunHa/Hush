import AppKit
import Foundation
@testable import Hush
import Testing

@Suite(.serialized)
@MainActor
struct MessageTableViewBottomInsetTests {
    private func makeMessage(content: String) -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .assistant,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_700_000_300)
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

    private func makeContent(lineCount: Int = 260) -> String {
        """
        # Floating Composer

        A long assistant message used to verify dynamic bottom insets.

        \(Array(repeating: "- item with some text", count: lineCount).joined(separator: "\n"))
        """
    }

    @Test("Following tail stays pinned when bottom reserved height grows")
    func followingTailStaysPinnedWhenBottomInsetGrows() {
        let runtime = makeRuntime()
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

        table.apply(
            messages: [makeMessage(content: makeContent())],
            activeConversationID: "conv-bottom-inset-following-tail",
            isActiveConversationSending: false,
            switchGeneration: 1,
            theme: container.settings.theme,
            runtime: runtime,
            container: container
        )

        host.layoutSubtreeIfNeeded()
        table.userHasScrolledUp = false
        table.scrollToBottom()

        let previousMaxY = table.maxScrollOriginYForTesting
        let previousInset = table.bottomReservedHeightForTesting
        #expect(previousMaxY > 0)

        table.setBottomReservedHeight(140)
        host.layoutSubtreeIfNeeded()

        let currentMaxY = table.maxScrollOriginYForTesting
        let currentY = table.scrollOriginYForTesting
        #expect(table.bottomReservedHeightForTesting > previousInset)
        #expect(currentMaxY > previousMaxY)
        #expect(abs(currentY - currentMaxY) <= 1.0)
    }

    @Test("Scrolled-up reader position is preserved when bottom reserved height grows")
    func scrolledUpReaderPositionIsPreservedWhenBottomInsetGrows() {
        let runtime = makeRuntime()
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

        table.apply(
            messages: [makeMessage(content: makeContent())],
            activeConversationID: "conv-bottom-inset-scrolled-up",
            isActiveConversationSending: false,
            switchGeneration: 1,
            theme: container.settings.theme,
            runtime: runtime,
            container: container
        )

        host.layoutSubtreeIfNeeded()
        table.setScrollOriginYForTesting(220)
        table.userHasScrolledUp = true

        let previousY = table.scrollOriginYForTesting
        let previousMaxY = table.maxScrollOriginYForTesting
        #expect(previousY >= 150)

        table.setBottomReservedHeight(140)
        host.layoutSubtreeIfNeeded()

        let currentY = table.scrollOriginYForTesting
        let currentMaxY = table.maxScrollOriginYForTesting
        #expect(currentMaxY > previousMaxY)
        #expect(abs(currentY - previousY) <= 1.0)
    }
}
