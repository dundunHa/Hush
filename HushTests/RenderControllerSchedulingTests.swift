import Foundation
@testable import Hush
import Testing

@MainActor
struct RenderControllerSchedulingTests {
    private func makeHint(
        messageID: UUID = UUID(),
        rankFromLatest: Int,
        isVisible: Bool,
        generation: UInt64 = 1
    ) -> MessageRenderHint {
        MessageRenderHint(
            conversationID: "c1",
            messageID: messageID,
            rankFromLatest: rankFromLatest,
            isVisible: isVisible,
            switchGeneration: generation
        )
    }

    @Test("Cache miss uses scheduler queue, not synchronous render")
    func cacheMissUsesQueueNotSyncRender() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0.1,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        let controller = RenderController(
            renderer: MessageContentRenderer(),
            scheduler: scheduler,
            coalesceInterval: 0.01
        )

        controller.requestRender(
            content: "queue miss",
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: makeHint(rankFromLatest: 0, isVisible: true)
        )

        #expect(controller.currentOutput == nil)

        let deadline = ContinuousClock.now + .seconds(1)
        while controller.currentOutput == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(controller.currentOutput?.plainText == "queue miss")
    }

    @Test("Cache hit remains immediate")
    func cacheHitStillImmediate() async {
        let renderer = MessageContentRenderer()
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0.1,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        let first = RenderController(
            renderer: renderer,
            scheduler: scheduler,
            coalesceInterval: 0.01
        )
        let second = RenderController(
            renderer: renderer,
            scheduler: scheduler,
            coalesceInterval: 0.01
        )
        let content = "cache me"

        first.requestRender(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: makeHint(rankFromLatest: 0, isVisible: true)
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while first.currentOutput == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(first.currentOutput?.plainText == content)

        second.requestRender(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: makeHint(rankFromLatest: 1, isVisible: true)
        )

        #expect(second.currentOutput?.plainText == content)
    }

    @Test("Deferred cache hit applies immediately to avoid flash to fallback")
    func deferredCacheHitUsesQueue() async {
        let renderer = MessageContentRenderer()
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0.05,
                idleDelay: 0.1,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        let prewarmController = RenderController(
            renderer: renderer,
            scheduler: scheduler,
            coalesceInterval: 0.01
        )
        let deferredController = RenderController(
            renderer: renderer,
            scheduler: scheduler,
            coalesceInterval: 0.01
        )
        let content = "cache queued for deferred"

        prewarmController.requestRender(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: makeHint(rankFromLatest: 0, isVisible: true)
        )

        let warmDeadline = ContinuousClock.now + .seconds(1)
        while prewarmController.currentOutput == nil, ContinuousClock.now < warmDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(prewarmController.currentOutput?.plainText == content)

        deferredController.requestRender(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: makeHint(rankFromLatest: 6, isVisible: false)
        )

        #expect(deferredController.currentOutput?.plainText == content)
    }

    @Test("Duplicate fingerprint request is skipped via dedup")
    func duplicateFingerprintRequestIsSkipped() async {
        let renderer = MessageContentRenderer()
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0.1,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        // Warm the cache via a high-priority controller.
        let warmup = RenderController(
            renderer: renderer,
            scheduler: scheduler,
            coalesceInterval: 0.01
        )
        let content = "dedup-check"

        warmup.requestRender(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: makeHint(rankFromLatest: 0, isVisible: true)
        )

        let warmDeadline = ContinuousClock.now + .seconds(1)
        while warmup.currentOutput == nil, ContinuousClock.now < warmDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(warmup.currentOutput?.plainText == content)

        // Second controller uses deferred priority – cache hit will be queued.
        let controller = RenderController(
            renderer: renderer,
            scheduler: scheduler,
            coalesceInterval: 0.01
        )
        let deferredMessageID = UUID()
        let hint = makeHint(
            messageID: deferredMessageID,
            rankFromLatest: 6,
            isVisible: false
        )

        controller.requestRender(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: hint
        )

        // Wait for the queued cache hit to apply.
        let applyDeadline = ContinuousClock.now + .seconds(1)
        while controller.currentOutput == nil, ContinuousClock.now < applyDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.currentOutput?.plainText == content)

        // Send exact same request again – dedup should skip it.
        // If dedup fails, the non-high cache-hit path would nil currentOutput
        // before re-queuing, which is observable.
        controller.requestRender(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: hint
        )

        #expect(controller.currentOutput?.plainText == content)
    }

    @Test("Queued stale result does not overwrite newer fingerprint")
    func queuedStaleResultDoesNotOverwriteNewerFingerprint() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0.2,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        let messageID = UUID()
        let controller = RenderController(
            renderer: MessageContentRenderer(),
            scheduler: scheduler,
            coalesceInterval: 0.01
        )

        controller.requestRender(
            content: "old content",
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: makeHint(messageID: messageID, rankFromLatest: 20, isVisible: false)
        )

        controller.requestRender(
            content: "new content",
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false,
            hint: makeHint(messageID: messageID, rankFromLatest: 0, isVisible: true)
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while controller.currentOutput?.plainText != "new content", ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(controller.currentOutput?.plainText == "new content")

        try? await Task.sleep(for: .milliseconds(350))
        #expect(controller.currentOutput?.plainText == "new content")
    }
}
