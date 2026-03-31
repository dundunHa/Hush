import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
struct MessageBodyAlignmentSupplementalTests {
    private var quickBarReadableWidth: CGFloat {
        QuickBarPanelReleaseMetrics.width
            - (HushSpacing.sm + 2) * 2
            - HushSpacing.xs * 2
    }

    private var quickBarTrailingCompactInset: CGFloat {
        HushSpacing.xl
    }

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

    @Test("Quick bar release transcript hides row actions even when copy and debug are available")
    func quickBarReleaseTranscriptHidesRowActions() {
        let runtime = MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
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
    }

    @Test("Reused quick bar cells reapply trailing column geometry after rich quick bar content")
    func reusedQuickBarCellsReapplyTrailingColumnGeometryAfterRichQuickBarContent() {
        let runtime = MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
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
            availableWidth: quickBarReadableWidth,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()
        #expect(abs(cell.bodyFrameForTesting.minX - (cell.contentContainerFrameForTesting.minX + HushSpacing.xl)) <= 0.5)
        #expect(abs(cell.bodyFrameForTesting.maxX - (cell.contentContainerFrameForTesting.maxX - HushSpacing.xl)) <= 0.5)

        cell.configure(
            row: row,
            runtime: runtime,
            availableWidth: quickBarReadableWidth,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        #expect(abs(cell.contentContainerFrameForTesting.width - quickBarReadableWidth) <= 0.5)
        #expect(cell.bodyTextAlignmentForTesting == .right)
        #expect(abs(cell.bodyFrameForTesting.maxX - (cell.contentContainerFrameForTesting.maxX - quickBarTrailingCompactInset)) <= 0.5)
        #expect(cell.bodyFrameForTesting.minX > cell.contentContainerFrameForTesting.midX)
        #expect(cell.bodyBorderWidthForTesting == 0)
        #expect(cell.bodyBackgroundAlphaForTesting == 0)
    }

    @Test("Assistant waiting state renders as light leading text with breathing animation")
    func assistantWaitingStateRendersAsLeadingTextWithBreathingAnimation() {
        let runtime = MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
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
        #expect(cell.bodyTextAlignmentForTesting == .left)
        #expect(abs(cell.bodyFrameForTesting.minX - (cell.contentContainerFrameForTesting.minX + HushSpacing.xl)) <= 0.5)
        #expect(cell.bodyFrameForTesting.width < cell.contentContainerFrameForTesting.width * 0.6)
        #expect(cell.bodyBorderWidthForTesting == 0)
        #expect(cell.bodyBackgroundAlphaForTesting == 0)
        #expect(cell.waitingBreathingAnimationActiveForTesting)
    }

    @Test("Wide rows center the whole message column with side gutters")
    func wideRowsCenterWholeMessageColumnWithSideGutters() {
        let runtime = MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
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
