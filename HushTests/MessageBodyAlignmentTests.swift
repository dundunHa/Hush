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

    private func hostCell(
        _ cell: MessageTableCellView,
        width: CGFloat = 840,
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
            containerView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        containerView.addSubview(cell)
        NSLayoutConstraint.activate([
            cell.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            cell.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            cell.topAnchor.constraint(equalTo: containerView.topAnchor),
            cell.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        return (window, host, containerView)
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

    @Test("User messages render as trailing text without bubble chrome")
    func userMessagesRenderAsTrailingTextWithoutBubbleChrome() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("plain-natural-alignment"))
        let hosted = hostCell(cell)
        defer {
            hosted.window.contentView = nil
            hosted.window.orderOut(nil)
            withExtendedLifetime(hosted.window) {}
        }

        cell.configure(
            row: makeRow(content: "say hi", isStreaming: false, role: .user),
            runtime: runtime,
            availableWidth: min(
                hosted.container.bounds.width,
                HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2
            ),
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        #expect(cell.bodyTextAlignmentForTesting == .right)
        #expect(cell.metaTextAlignmentForTesting == .right)
        #expect(abs(cell.bodyFrameForTesting.maxX - (cell.contentContainerFrameForTesting.maxX - HushSpacing.xl)) <= 0.5)
        #expect(cell.bodyFrameForTesting.width < cell.contentContainerFrameForTesting.width - HushSpacing.xl * 3)
        #expect(cell.bodyBorderWidthForTesting == 0)
        #expect(cell.bodyBackgroundAlphaForTesting == 0)
        #expect(!cell.waitingBreathingAnimationActiveForTesting)
    }

    @Test("Assistant waiting state renders as light leading text with breathing animation")
    func assistantWaitingStateRendersAsLeadingTextWithBreathingAnimation() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("assistant-waiting-bubble"))
        let hosted = hostCell(cell)
        defer {
            hosted.window.contentView = nil
            hosted.window.orderOut(nil)
            withExtendedLifetime(hosted.window) {}
        }

        cell.configure(
            row: makeRow(content: "", isStreaming: true, role: .assistant),
            runtime: runtime,
            availableWidth: min(
                hosted.container.bounds.width,
                HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2
            ),
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        #expect(cell.attributedStringForTesting.string == RenderConstants.assistantWaitingPlaceholder)
        #expect(cell.metaTextAlignmentForTesting == .left)
        #expect(cell.bodyTextAlignmentForTesting == .left)
        #expect(abs(cell.bodyFrameForTesting.minX - (cell.contentContainerFrameForTesting.minX + HushSpacing.xl)) <= 0.5)
        #expect(cell.bodyFrameForTesting.width < cell.contentContainerFrameForTesting.width * 0.6)
        #expect(cell.bodyBorderWidthForTesting == 0)
        #expect(cell.bodyBackgroundAlphaForTesting == 0)
        #expect(cell.waitingBreathingAnimationActiveForTesting)
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

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("centered-message-column"))
        let hosted = hostCell(cell, height: 400)
        defer {
            hosted.window.contentView = nil
            hosted.window.orderOut(nil)
            withExtendedLifetime(hosted.window) {}
        }

        let maxColumnWidth = HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2
        cell.configure(
            row: makeRow(content: "Hi there!", isStreaming: false),
            runtime: runtime,
            availableWidth: min(hosted.container.bounds.width, maxColumnWidth),
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        let contentFrame = cell.contentContainerFrameForTesting
        #expect(abs(contentFrame.width - maxColumnWidth) <= 0.5)
        #expect(abs(contentFrame.midX - cell.bounds.midX) <= 0.5)
        #expect(contentFrame.minX >= 19.5)
        #expect(contentFrame.maxX <= cell.bounds.maxX - 19.5)
    }
}
