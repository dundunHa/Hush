import Foundation
@testable import Hush
import Testing

@Suite("Streaming Coalescing")
struct StreamingCoalescingTests {
    // MARK: - Task 8.5: Bounded Render Frequency

    @MainActor
    @Test("Non-streaming cache miss is queued and eventually renders")
    func nonStreamingQueued() async {
        let renderer = MessageContentRenderer()
        let controller = RenderController(renderer: renderer)

        controller.requestRender(
            content: "Hello **world**",
            availableWidth: 600,
            style: .appDefault(),
            isStreaming: false
        )

        #expect(controller.currentOutput == nil)

        let deadline = ContinuousClock.now + .seconds(1)
        while controller.currentOutput == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(controller.currentOutput != nil)
        #expect(controller.currentOutput?.plainText == "Hello **world**")
    }

    @MainActor
    @Test("Long non-streaming cache miss renders progressively")
    func longNonStreamingCacheMissIsProgressive() async {
        let renderer = MessageContentRenderer()
        let controller = RenderController(renderer: renderer)
        let content = String(repeating: "long message content ", count: 140) // > 2000 chars

        controller.requestRender(
            content: content,
            availableWidth: 600,
            style: .appDefault(),
            isStreaming: false
        )

        #expect(controller.currentOutput == nil)

        let deadline = ContinuousClock.now + .seconds(2)
        while controller.currentOutput == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(controller.currentOutput != nil)
        #expect(controller.currentOutput?.plainText == content)
    }

    @MainActor
    @Test("Long non-streaming cache hit is immediate")
    func longNonStreamingCacheHitIsImmediate() async {
        let renderer = MessageContentRenderer()
        let first = RenderController(renderer: renderer)
        let second = RenderController(renderer: renderer)
        let content = String(repeating: "cached long content ", count: 140) // > 2000 chars

        first.requestRender(
            content: content,
            availableWidth: 600,
            style: .appDefault(),
            isStreaming: false
        )

        let deadline = ContinuousClock.now + .seconds(2)
        while first.currentOutput == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(first.currentOutput != nil)

        second.requestRender(
            content: content,
            availableWidth: 600,
            style: .appDefault(),
            isStreaming: false
        )

        #expect(second.currentOutput != nil)
        #expect(second.currentOutput?.plainText == content)
    }

    @MainActor
    @Test("Cancel clears pending work")
    func cancelClearsPending() async {
        let renderer = MessageContentRenderer()
        let controller = RenderController(
            renderer: renderer,
            coalesceInterval: 1.0
        )

        controller.requestRender(
            content: "Streaming content",
            availableWidth: 600,
            style: .appDefault(),
            isStreaming: true
        )

        controller.cancel()

        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(controller.currentOutput == nil)
    }

    @MainActor
    @Test("Rapid streaming updates coalesce to final content")
    func rapidUpdatesCoalesceToFinal() async {
        let renderer = MessageContentRenderer()
        let controller = RenderController(
            renderer: renderer,
            coalesceInterval: 0.05
        )

        let finalContent = String(repeating: "word ", count: 20)

        for idx in 0 ..< 20 {
            controller.requestRender(
                content: String(repeating: "word ", count: idx + 1),
                availableWidth: 600,
                style: .appDefault(),
                isStreaming: true
            )
        }

        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(controller.currentOutput != nil)
        #expect(controller.currentOutput?.plainText == finalContent)
    }

    @MainActor
    @Test("Stale render does not overwrite newer content")
    func staleRenderDoesNotOverwrite() async {
        let renderer = MessageContentRenderer()
        let controller = RenderController(
            renderer: renderer,
            coalesceInterval: 0.05
        )

        controller.requestRender(
            content: "First version",
            availableWidth: 600,
            style: .appDefault(),
            isStreaming: true
        )

        controller.requestRender(
            content: "Second version",
            availableWidth: 600,
            style: .appDefault(),
            isStreaming: true
        )

        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(controller.currentOutput != nil)
        #expect(controller.currentOutput?.plainText == "Second version")
    }

    @MainActor
    @Test("Non-streaming retry is not dedup-skipped after stale enqueue drop")
    func nonStreamingRetryAfterStaleDropRendersFinal() async throws {
        let renderer = MessageContentRenderer()
        let scheduler = ConversationRenderScheduler()
        let controller = RenderController(
            renderer: renderer,
            scheduler: scheduler,
            coalesceInterval: 0.01
        )
        let style = RenderStyle.appDefault()

        let conversationID = "conv-retry"
        let messageID = try #require(UUID(uuidString: "A1A1A1A1-B2B2-C3C3-D4D4-E5E5E5E5E5E5"))
        let hint = MessageRenderHint(
            conversationID: conversationID,
            messageID: messageID,
            rankFromLatest: 0,
            isVisible: true,
            switchGeneration: 1
        )

        controller.requestRender(
            content: "partial",
            availableWidth: 600,
            style: style,
            isStreaming: true,
            hint: hint
        )
        try? await Task.sleep(for: .milliseconds(40))
        #expect(controller.currentOutput?.plainText == "partial")

        // First non-streaming request is dropped as stale (conversation is cold).
        scheduler.setSceneConfiguration(active: ("other-conv", 1), hot: [])
        controller.requestRender(
            content: "final-complete-content",
            availableWidth: 600,
            style: style,
            isStreaming: false,
            hint: hint
        )
        try? await Task.sleep(for: .milliseconds(40))
        #expect(controller.currentOutput?.plainText == "partial")
        #expect(controller.lastRequestedIsStreamingForTesting == false)
        #expect(controller.lastQueuedPriorityForTesting == .high)
        #expect(controller.lastRequestedHintForTesting == hint)

        // After conversation becomes active again, retrying the same request
        // should not be dedup-skipped and must render final content.
        scheduler.setSceneConfiguration(active: (conversationID, 1), hot: [])
        controller.requestRender(
            content: "final-complete-content",
            availableWidth: 600,
            style: style,
            isStreaming: false,
            hint: hint
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while controller.currentOutput?.plainText != "final-complete-content",
              ContinuousClock.now < deadline
        {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(controller.currentOutput?.plainText == "final-complete-content")
    }
}
