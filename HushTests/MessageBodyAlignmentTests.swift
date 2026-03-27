import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
struct MessageBodyAlignmentTests {
    private func makeRow(
        content: String,
        isStreaming: Bool,
        role: ChatRole = .assistant,
        debugInfoJSON: String? = nil
    ) -> MessageTableView.RowModel {
        let message = ChatMessage(
            id: UUID(),
            role: role,
            content: content,
            debugInfoJSON: debugInfoJSON
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
        _ cell: NSView,
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
        cell.translatesAutoresizingMaskIntoConstraints = false
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

    @Test("Quick bar user messages stay on the shared readable column with leading text alignment")
    func quickBarUserMessagesUseTrailingEdgeOfCenteredReadableColumn() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = QuickBarMessageCellView(identifier: NSUserInterfaceItemIdentifier("quickbar-user-alignment"))
        let hosted = hostCell(cell)
        defer {
            hosted.window.contentView = nil
            hosted.window.orderOut(nil)
            withExtendedLifetime(hosted.window) {}
        }

        cell.configure(
            row: makeRow(content: "你好", isStreaming: false, role: .user),
            runtime: runtime,
            availableWidth: hosted.container.bounds.width,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        #expect(abs(cell.contentContainerFrameForTesting.width - 640) <= 0.5)
        #expect(abs(cell.contentContainerFrameForTesting.midX - hosted.container.bounds.midX) <= 0.5)
        #expect(cell.bodyTextAlignmentForTesting == .left)
        #expect(cell.metaTextAlignmentForTesting == .left)
        #expect(abs(cell.bodyFrameForTesting.minX - (cell.contentContainerFrameForTesting.minX + HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.bodyFrameForTesting.maxX - (cell.contentContainerFrameForTesting.maxX - HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.visibleTextFrameForTesting.minX - (cell.contentContainerFrameForTesting.minX + HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.metaFrameForTesting.minX - cell.bodyFrameForTesting.minX) <= 0.5)
        #expect(abs(cell.metaFrameForTesting.maxX - cell.bodyFrameForTesting.maxX) <= 0.5)
        #expect(cell.bodyBorderWidthForTesting == 0)
        #expect(cell.bodyBackgroundAlphaForTesting == 0)
        #expect(!cell.waitingBreathingAnimationActiveForTesting)
    }

    @Test("Quick bar assistant messages stay on the shared readable column with leading text alignment")
    func quickBarAssistantMessagesStayLeftAlignedInsideCenteredReadableColumn() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = QuickBarMessageCellView(identifier: NSUserInterfaceItemIdentifier("quickbar-assistant-alignment"))
        let hosted = hostCell(cell)
        defer {
            hosted.window.contentView = nil
            hosted.window.orderOut(nil)
            withExtendedLifetime(hosted.window) {}
        }

        cell.configure(
            row: makeRow(content: "Hello back", isStreaming: false, role: .assistant),
            runtime: runtime,
            availableWidth: hosted.container.bounds.width,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        #expect(abs(cell.contentContainerFrameForTesting.width - 640) <= 0.5)
        #expect(abs(cell.contentContainerFrameForTesting.midX - hosted.container.bounds.midX) <= 0.5)
        #expect(cell.bodyTextAlignmentForTesting == .left)
        #expect(cell.metaTextAlignmentForTesting == .left)
        #expect(abs(cell.bodyFrameForTesting.minX - (cell.contentContainerFrameForTesting.minX + HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.bodyFrameForTesting.maxX - (cell.contentContainerFrameForTesting.maxX - HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.visibleTextFrameForTesting.minX - (cell.contentContainerFrameForTesting.minX + HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.metaFrameForTesting.minX - cell.bodyFrameForTesting.minX) <= 0.5)
        #expect(abs(cell.metaFrameForTesting.maxX - cell.bodyFrameForTesting.maxX) <= 0.5)
        #expect(cell.bodyBorderWidthForTesting == 0)
        #expect(cell.bodyBackgroundAlphaForTesting == 0)
        #expect(!cell.waitingBreathingAnimationActiveForTesting)
    }

    @Test("Quick bar long simple messages share one readable column without decoration")
    func quickBarLongSimpleMessagesShareOneReadableColumnWithoutDecoration() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let userCell = QuickBarMessageCellView(identifier: NSUserInterfaceItemIdentifier("quickbar-user-mirrored-lane"))
        let assistantCell = QuickBarMessageCellView(identifier: NSUserInterfaceItemIdentifier("quickbar-assistant-mirrored-lane"))
        let hostedUser = hostCell(userCell)
        let hostedAssistant = hostCell(assistantCell)
        defer {
            hostedUser.window.contentView = nil
            hostedUser.window.orderOut(nil)
            withExtendedLifetime(hostedUser.window) {}

            hostedAssistant.window.contentView = nil
            hostedAssistant.window.orderOut(nil)
            withExtendedLifetime(hostedAssistant.window) {}
        }

        userCell.configure(
            row: makeRow(
                content: "QuickBar 里用户长消息应该和 assistant 共用一条镜像宽度轨道。",
                isStreaming: false,
                role: .user
            ),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )
        assistantCell.configure(
            row: makeRow(
                content: "这里是 assistant 的简单长文本回复，用来验证 mirrored lane 是否真正共享宽度。",
                isStreaming: false,
                role: .assistant
            ),
            runtime: runtime,
            availableWidth: hostedAssistant.container.bounds.width,
            container: nil
        )

        hostedUser.host.layoutSubtreeIfNeeded()
        hostedAssistant.host.layoutSubtreeIfNeeded()

        let userLeadingGap = userCell.visibleTextFrameForTesting.minX - userCell.contentContainerFrameForTesting.minX
        let assistantLeadingGap = assistantCell.visibleTextFrameForTesting.minX - assistantCell.contentContainerFrameForTesting.minX

        #expect(abs(userLeadingGap - assistantLeadingGap) <= 0.5)
        #expect(abs(userCell.bodyFrameForTesting.minX - assistantCell.bodyFrameForTesting.minX) <= 0.5)
        #expect(abs(userCell.bodyFrameForTesting.maxX - assistantCell.bodyFrameForTesting.maxX) <= 0.5)
        #expect(abs(userCell.bodyFrameForTesting.width - assistantCell.bodyFrameForTesting.width) <= 0.5)
        #expect(abs(userCell.metaFrameForTesting.maxX - userCell.bodyFrameForTesting.maxX) <= 0.5)
        #expect(abs(assistantCell.metaFrameForTesting.minX - assistantCell.bodyFrameForTesting.minX) <= 0.5)
        #expect(userCell.bodyBorderWidthForTesting == 0)
        #expect(assistantCell.bodyBorderWidthForTesting == 0)
        #expect(userCell.bodyBackgroundAlphaForTesting == 0)
        #expect(assistantCell.bodyBackgroundAlphaForTesting == 0)
    }

    @Test("Quick bar short simple messages keep mirrored visible edges on one readable column")
    func quickBarShortSimpleMessagesKeepMirroredVisibleEdgesOnOneReadableColumn() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let userCell = QuickBarMessageCellView(identifier: NSUserInterfaceItemIdentifier("quickbar-user-short-footprint"))
        let assistantCell = QuickBarMessageCellView(identifier: NSUserInterfaceItemIdentifier("quickbar-assistant-short-footprint"))
        let hostedUser = hostCell(userCell)
        let hostedAssistant = hostCell(assistantCell)
        defer {
            hostedUser.window.contentView = nil
            hostedUser.window.orderOut(nil)
            withExtendedLifetime(hostedUser.window) {}

            hostedAssistant.window.contentView = nil
            hostedAssistant.window.orderOut(nil)
            withExtendedLifetime(hostedAssistant.window) {}
        }

        userCell.configure(
            row: makeRow(content: "好。", isStreaming: false, role: .user),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )
        assistantCell.configure(
            row: makeRow(content: "收到。", isStreaming: false, role: .assistant),
            runtime: runtime,
            availableWidth: hostedAssistant.container.bounds.width,
            container: nil
        )

        hostedUser.host.layoutSubtreeIfNeeded()
        hostedAssistant.host.layoutSubtreeIfNeeded()

        let userLeadingGap = userCell.visibleTextFrameForTesting.minX - userCell.contentContainerFrameForTesting.minX
        let assistantLeadingGap = assistantCell.visibleTextFrameForTesting.minX - assistantCell.contentContainerFrameForTesting.minX

        #expect(abs(userLeadingGap - assistantLeadingGap) <= 0.5)
        #expect(abs(userCell.bodyFrameForTesting.minX - assistantCell.bodyFrameForTesting.minX) <= 0.5)
        #expect(abs(userCell.bodyFrameForTesting.maxX - assistantCell.bodyFrameForTesting.maxX) <= 0.5)
        #expect(abs(userCell.bodyFrameForTesting.width - assistantCell.bodyFrameForTesting.width) <= 0.5)
        #expect(abs(userCell.metaFrameForTesting.maxX - userCell.bodyFrameForTesting.maxX) <= 0.5)
        #expect(abs(assistantCell.metaFrameForTesting.minX - assistantCell.bodyFrameForTesting.minX) <= 0.5)
        #expect(userCell.bodyBorderWidthForTesting == 0)
        #expect(assistantCell.bodyBorderWidthForTesting == 0)
        #expect(userCell.bodyBackgroundAlphaForTesting == 0)
        #expect(assistantCell.bodyBackgroundAlphaForTesting == 0)
    }

    @Test("Quick bar release transcript hides row actions even when copy and debug are available")
    func quickBarReleaseTranscriptHidesRowActions() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = QuickBarMessageCellView(identifier: NSUserInterfaceItemIdentifier("quickbar-release-actions-hidden"))
        let hosted = hostCell(cell)
        defer {
            hosted.window.contentView = nil
            hosted.window.orderOut(nil)
            withExtendedLifetime(hosted.window) {}
        }

        cell.configure(
            row: makeRow(
                content: "这是一个可复制、也带 trace 的 assistant 回复。",
                isStreaming: false,
                role: .assistant,
                debugInfoJSON: #"{"request":"trace"}"#
            ),
            runtime: runtime,
            availableWidth: hosted.container.bounds.width,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        #expect(!cell.debugButtonVisibleForTesting)
        #expect(!cell.copyButtonVisibleForTesting)
        #expect(!cell.actionBarActiveForTesting)
        #expect(abs(cell.metaFrameForTesting.width - cell.bodyFrameForTesting.width) <= 0.5)
    }

    @Test("Reused quick bar cells reapply shared readable column geometry after rich quick bar content")
    func reusedQuickBarCellsReapplySharedReadableColumnGeometryAfterRichQuickBarContent() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let row = makeRow(content: "say hi", isStreaming: false, role: .user)
        let richAssistantRow = makeRow(
            content: """
            # Rich Reply

            - markdown
            - should stay full width
            """,
            isStreaming: false,
            role: .assistant
        )
        let cell = QuickBarMessageCellView(identifier: NSUserInterfaceItemIdentifier("reused-quickbar-user-alignment"))
        let hosted = hostCell(cell)
        defer {
            hosted.window.contentView = nil
            hosted.window.orderOut(nil)
            withExtendedLifetime(hosted.window) {}
        }

        cell.configure(
            row: richAssistantRow,
            runtime: runtime,
            availableWidth: 640,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()
        #expect(abs(cell.bodyFrameForTesting.minX - (cell.contentContainerFrameForTesting.minX + HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.bodyFrameForTesting.maxX - (cell.contentContainerFrameForTesting.maxX - HushSpacing.xl)) <= 0.5)

        cell.configure(
            row: row,
            runtime: runtime,
            availableWidth: 640,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        #expect(abs(cell.contentContainerFrameForTesting.width - 640) <= 0.5)
        #expect(cell.bodyTextAlignmentForTesting == .left)
        #expect(cell.metaTextAlignmentForTesting == .left)
        #expect(abs(cell.bodyFrameForTesting.minX - (cell.contentContainerFrameForTesting.minX + HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.bodyFrameForTesting.maxX - (cell.contentContainerFrameForTesting.maxX - HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.metaFrameForTesting.minX - cell.bodyFrameForTesting.minX) <= 0.5)
        #expect(abs(cell.metaFrameForTesting.maxX - cell.bodyFrameForTesting.maxX) <= 0.5)
        #expect(cell.bodyBorderWidthForTesting == 0)
        #expect(cell.bodyBackgroundAlphaForTesting == 0)
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
