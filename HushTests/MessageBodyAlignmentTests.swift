import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
struct MessageBodyAlignmentTests {
    private func makeRow(
        content: String,
        isStreaming: Bool,
        role: ChatRole = .assistant
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
                conversationID: "conv-alignment",
                messageID: message.id,
                rankFromLatest: 0,
                isVisible: true,
                switchGeneration: 1
            )
        )
    }

    private func warmRichCache(
        renderer: MessageContentRenderer,
        content: String,
        availableWidth: CGFloat
    ) {
        let contentWidth = max(1, availableWidth - HushSpacing.xl * 2)
        _ = renderer.render(MessageRenderInput(
            content: content,
            availableWidth: contentWidth,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        ))
    }

    @Test("Cache-hit rich markdown keeps paragraph alignment natural")
    func cacheHitRichMarkdownKeepsParagraphAlignmentNatural() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let availableWidth: CGFloat = 600
        let content = """
        # Title

        Paragraph with **markdown** content.
        """

        warmRichCache(
            renderer: renderer,
            content: content,
            availableWidth: availableWidth
        )

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("rich-natural-alignment"))
        cell.configure(
            row: makeRow(content: content, isStreaming: false),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        let attributed = cell.attributedStringForTesting
        let headingStyle = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let paragraphRange = (attributed.string as NSString).range(of: "Paragraph with")

        #expect(paragraphRange.location != NSNotFound)

        let paragraphStyle = attributed.attribute(.paragraphStyle, at: paragraphRange.location, effectiveRange: nil) as? NSParagraphStyle
        #expect(headingStyle?.alignment != .center)
        #expect(paragraphStyle?.alignment != .center)
    }

    @Test("Plain fallback keeps body text view noncentered")
    func plainFallbackKeepsBodyTextViewNoncentered() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("plain-natural-alignment"))

        cell.configure(
            row: makeRow(content: "say hi", isStreaming: false, role: .user),
            runtime: runtime,
            availableWidth: 600,
            container: nil
        )

        #expect(cell.bodyTextAlignmentForTesting != .center)
    }

    @Test("Wide rows center the whole message column with side gutters")
    func wideRowsCenterWholeMessageColumnWithSideGutters() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let host = NSView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.display()
        defer {
            window.contentView = nil
            window.orderOut(nil)
            withExtendedLifetime(window) {}
        }

        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: host.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("centered-message-column"))
        containerView.addSubview(cell)
        NSLayoutConstraint.activate([
            cell.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            cell.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            cell.topAnchor.constraint(equalTo: containerView.topAnchor),
            cell.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let maxColumnWidth = HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2
        cell.configure(
            row: makeRow(content: "Hi there!", isStreaming: false),
            runtime: runtime,
            availableWidth: min(containerView.bounds.width, maxColumnWidth),
            container: nil
        )
        host.layoutSubtreeIfNeeded()

        let contentFrame = cell.contentContainerFrameForTesting
        #expect(abs(contentFrame.width - maxColumnWidth) <= 0.5)
        #expect(abs(contentFrame.midX - cell.bounds.midX) <= 0.5)
        #expect(contentFrame.minX >= 19.5)
        #expect(contentFrame.maxX <= cell.bounds.maxX - 19.5)
    }
}
