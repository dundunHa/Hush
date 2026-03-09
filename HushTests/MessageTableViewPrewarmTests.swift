import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
struct MessageTableViewPrewarmTests {
    private func makeMessage(
        id: UUID,
        role: ChatRole,
        content: String
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }

    @Test("Lookahead prewarm only selects eligible non-streaming assistant rows")
    func selectsEligibleRowsOnly() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 16),
            mathCache: MathRenderCache(capacity: 16)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let table = MessageTableView()
        let container = AppContainer.forTesting(settings: .testDefault)

        let assistantPast = try makeMessage(
            id: #require(UUID(uuidString: "88888888-8888-8888-8888-888888888888")),
            role: .assistant,
            content: "past assistant"
        )
        let user = try makeMessage(
            id: #require(UUID(uuidString: "99999999-9999-9999-9999-999999999999")),
            role: .user,
            content: "user content"
        )
        let assistantEligible = try makeMessage(
            id: #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")),
            role: .assistant,
            content: "eligible assistant"
        )
        let assistantStreaming = try makeMessage(
            id: #require(UUID(uuidString: "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF")),
            role: .assistant,
            content: "streaming assistant tail"
        )

        table.apply(
            messages: [assistantPast, user, assistantEligible, assistantStreaming],
            activeConversationID: "conv-prewarm",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        let ids = table.lookaheadCandidateMessageIDsForTesting(
            visibleRows: NSRange(location: 0, length: 2),
            availableWidth: 600
        )
        #expect(ids == [assistantEligible.id])
    }

    @Test("Lookahead prewarm skips rows that are already cached")
    func skipsCachedRows() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 16),
            mathCache: MathRenderCache(capacity: 16)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let table = MessageTableView()
        let container = AppContainer.forTesting(settings: .testDefault)

        let user = try makeMessage(
            id: #require(UUID(uuidString: "12121212-1212-1212-1212-121212121212")),
            role: .user,
            content: "user content"
        )
        let assistantCached = try makeMessage(
            id: #require(UUID(uuidString: "34343434-3434-3434-3434-343434343434")),
            role: .assistant,
            content: "assistant cached"
        )

        let availableWidth: CGFloat = 600
        let contentWidth = max(1, availableWidth - HushSpacing.xl * 2)
        _ = renderer.render(MessageRenderInput(
            content: assistantCached.content,
            availableWidth: contentWidth,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        ))

        table.apply(
            messages: [user, assistantCached],
            activeConversationID: "conv-prewarm",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        let ids = table.lookaheadCandidateMessageIDsForTesting(
            visibleRows: NSRange(location: 0, length: 1),
            availableWidth: availableWidth
        )
        #expect(ids.isEmpty)
    }

    @Test("Live scroll suppresses lookahead scheduling during pinned updates")
    func liveScrollSuppressesLookaheadScheduling() {
        let table = MessageTableView()

        table.triggerPinnedStateUpdateForTesting()
        let baseline = table.lookaheadScheduleInvocationCountForTesting

        table.simulateLiveScrollStartForTesting()
        #expect(table.isLiveScrollingForTesting)

        table.triggerPinnedStateUpdateForTesting()
        #expect(table.lookaheadScheduleInvocationCountForTesting == baseline)
    }

    @Test("Scroll end triggers one debounced lookahead scheduling pass")
    func scrollEndTriggersDebouncedLookaheadScheduling() async {
        let table = MessageTableView()
        table.simulateLiveScrollStartForTesting()

        let baseline = table.lookaheadScheduleInvocationCountForTesting
        table.simulateLiveScrollEndForTesting()
        #expect(!table.isLiveScrollingForTesting)

        try? await Task.sleep(for: .milliseconds(260))
        #expect(table.lookaheadScheduleInvocationCountForTesting == baseline + 1)
    }

    @Test("Keyboard arrow scrolling does not trigger live scroll")
    func keyboardArrowScrollDoesNotTriggerLiveScroll() {
        let table = MessageTableView()

        table.triggerPinnedStateUpdateForTesting()

        #expect(!table.isLiveScrollingForTesting)
        #expect(table.lookaheadScheduleInvocationCountForTesting >= 1)
    }

    @Test("Fallback timeout resets isLiveScrolling after 3 seconds")
    func fallbackTimeoutResetsLiveScrolling() async {
        let table = MessageTableView()
        table.simulateLiveScrollStartForTesting()
        #expect(table.isLiveScrollingForTesting)

        try? await Task.sleep(for: .milliseconds(3300))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        #expect(!table.isLiveScrollingForTesting)
    }

    @Test("Rapid scroll restart cancels pending debounce prewarm")
    func rapidScrollRestartCancelsPendingDebouncePrewarm() async {
        let table = MessageTableView()

        table.simulateLiveScrollStartForTesting()
        table.simulateLiveScrollEndForTesting()

        let baselineAfterEnd = table.lookaheadScheduleInvocationCountForTesting

        try? await Task.sleep(for: .milliseconds(50))
        table.simulateLiveScrollStartForTesting()

        try? await Task.sleep(for: .milliseconds(300))

        #expect(table.lookaheadScheduleInvocationCountForTesting == baselineAfterEnd)
    }
}
