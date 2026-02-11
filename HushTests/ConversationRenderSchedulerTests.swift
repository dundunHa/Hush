import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Conversation Render Scheduler")
struct ConversationRenderSchedulerTests {
    private func makeInput(_ content: String) -> MessageRenderInput {
        MessageRenderInput(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false
        )
    }

    private func makeOutput(_ content: String) -> MessageRenderOutput {
        MessageRenderOutput(
            attributedString: NSAttributedString(string: content),
            plainText: content,
            diagnostics: []
        )
    }

    @Test("Latest three assistant messages render before older ones")
    func latestThreeRenderBeforeOlder() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0.2,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        let messageIDs = (0 ..< 5).map { _ in UUID() }
        let highPriorityIDs = Set(messageIDs.prefix(3))
        var executionOrder: [UUID] = []

        let enqueueOrder = [4, 3, 2, 1, 0]
        for rank in enqueueOrder {
            let messageID = messageIDs[rank]
            let priority: ConversationRenderScheduler.RenderWorkPriority = rank < 3 ? .high : .deferred
            let key = ConversationRenderScheduler.RenderWorkKey(
                conversationID: "c1",
                messageID: messageID,
                fingerprint: rank,
                generation: 1
            )
            scheduler.enqueue(
                key: key,
                priority: priority,
                input: makeInput("m-\(rank)"),
                render: { input in
                    makeOutput(input.content)
                },
                apply: { _ in
                    executionOrder.append(messageID)
                }
            )
        }

        let deadline = ContinuousClock.now + .seconds(1)
        while executionOrder.count < 5, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(executionOrder.count == 5)
        #expect(executionOrder.prefix(3).allSatisfy { highPriorityIDs.contains($0) })
    }

    @Test("Offscreen idle work respects idle delay")
    func offscreenItemsRespectIdleDelay() async {
        let idleDelay: TimeInterval = 0.2
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: idleDelay,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        var didApply = false
        var appliedAt: ContinuousClock.Instant?
        let start = ContinuousClock.now
        let key = ConversationRenderScheduler.RenderWorkKey(
            conversationID: "c1",
            messageID: UUID(),
            fingerprint: 1,
            generation: 1
        )

        scheduler.enqueue(
            key: key,
            priority: .idle,
            input: makeInput("idle"),
            render: { input in
                makeOutput(input.content)
            },
            apply: { _ in
                didApply = true
                appliedAt = ContinuousClock.now
            }
        )

        // This work item should not apply synchronously.
        #expect(!didApply)

        let deadline = ContinuousClock.now + .seconds(1)
        while !didApply, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(didApply)
        #expect(appliedAt != nil)

        if let appliedAt {
            let elapsed = start.duration(to: appliedAt)
            let elapsedMs =
                Double(elapsed.components.seconds) * 1000 +
                Double(elapsed.components.attoseconds) / 1e15
            #expect(elapsedMs >= idleDelay * 1000 - 10)
        }
    }

    @Test("Visible promotion preempts deferred work")
    func visiblePromotionPreemptsDeferred() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0.2,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        var executionOrder: [String] = []
        let messageA = UUID()
        let messageB = UUID()

        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: messageA, fingerprint: 1, generation: 1),
            priority: .deferred,
            input: makeInput("A"),
            render: { input in
                makeOutput(input.content)
            },
            apply: { _ in
                executionOrder.append("A")
            }
        )

        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: messageB, fingerprint: 2, generation: 1),
            priority: .deferred,
            input: makeInput("B-deferred"),
            render: { input in
                makeOutput(input.content)
            },
            apply: { _ in
                executionOrder.append("B-deferred")
            }
        )

        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: messageB, fingerprint: 2, generation: 1),
            priority: .visible,
            input: makeInput("B-visible"),
            render: { input in
                makeOutput(input.content)
            },
            apply: { _ in
                executionOrder.append("B-visible")
            }
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while executionOrder.count < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(executionOrder.count == 2)
        #expect(executionOrder.first == "B-visible")
        #expect(executionOrder.contains("A"))
        #expect(!executionOrder.contains("B-deferred"))
    }

    @Test("Capacity overflow drops lowest priority oldest item, never high")
    func capacityOverflowDropsLowestPriorityOldest() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0,
                queueCapacity: 3
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        var applied: [String] = []

        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .high,
            input: makeInput("high-1"),
            render: { input in makeOutput(input.content) },
            apply: { _ in applied.append("high-1") }
        )
        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 2, generation: 1),
            priority: .deferred,
            input: makeInput("deferred-1"),
            render: { input in makeOutput(input.content) },
            apply: { _ in applied.append("deferred-1") }
        )
        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 3, generation: 1),
            priority: .idle,
            input: makeInput("idle-1"),
            render: { input in makeOutput(input.content) },
            apply: { _ in applied.append("idle-1") }
        )

        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 4, generation: 1),
            priority: .visible,
            input: makeInput("visible-1"),
            render: { input in makeOutput(input.content) },
            apply: { _ in applied.append("visible-1") }
        )

        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 5, generation: 1),
            priority: .high,
            input: makeInput("high-2"),
            render: { input in makeOutput(input.content) },
            apply: { _ in applied.append("high-2") }
        )

        let deadline = ContinuousClock.now + .seconds(2)
        while applied.count < 3, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        try? await Task.sleep(for: .milliseconds(50))

        #expect(applied.contains("high-1"))
        #expect(applied.contains("high-2"))
        #expect(!applied.contains("idle-1"))
        #expect(!applied.contains("deferred-1"))
    }

    @Test("Stale generation work items are dropped")
    func staleGenerationItemsAreDropped() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0.2,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)

        var didApply = false
        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .idle,
            input: makeInput("stale"),
            render: { input in
                makeOutput(input.content)
            },
            apply: { _ in
                didApply = true
            }
        )

        scheduler.setActiveConversation(conversationID: "c1", generation: 2)

        try? await Task.sleep(for: .milliseconds(350))
        #expect(!didApply)
    }

    @Test("Live scroll gate pauses queued work and resumes after scroll ends")
    func liveScrollGatePausesAndResumesQueuedWork() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)
        scheduler.setLiveScrolling(true)

        var didApply = false
        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .visible,
            input: makeInput("gated"),
            render: { input in
                makeOutput(input.content)
            },
            apply: { _ in
                didApply = true
            }
        )

        try? await Task.sleep(for: .milliseconds(250))
        #expect(!didApply)

        scheduler.setLiveScrolling(false)
        let deadline = ContinuousClock.now + .seconds(1)
        while !didApply, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(didApply)
    }

    @Test("Stale pruning continues during scroll")
    func stalePruningContinuesDuringScroll() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)
        scheduler.setLiveScrolling(true)

        var didApply = false
        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .high,
            input: makeInput("stale-during-scroll"),
            render: { input in makeOutput(input.content) },
            apply: { _ in didApply = true }
        )

        scheduler.setActiveConversation(conversationID: "c1", generation: 2)
        scheduler.setLiveScrolling(false)

        try? await Task.sleep(for: .milliseconds(300))
        #expect(!didApply)
    }

    @Test("Budget interval still applies after scroll ends")
    func budgetIntervalAppliesAfterScrollEnds() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0.15,
                idleDelay: 0,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)
        scheduler.setLiveScrolling(true)

        var applyTimestamps: [ContinuousClock.Instant] = []
        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .high,
            input: makeInput("budget-1"),
            render: { input in makeOutput(input.content) },
            apply: { _ in applyTimestamps.append(ContinuousClock.now) }
        )
        scheduler.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 2, generation: 1),
            priority: .high,
            input: makeInput("budget-2"),
            render: { input in makeOutput(input.content) },
            apply: { _ in applyTimestamps.append(ContinuousClock.now) }
        )

        scheduler.setLiveScrolling(false)

        let deadline = ContinuousClock.now + .seconds(2)
        while applyTimestamps.count < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(applyTimestamps.count == 2)
        let gap = applyTimestamps[0].duration(to: applyTimestamps[1])
        let gapMs =
            Double(gap.components.seconds) * 1000 +
            Double(gap.components.attoseconds) / 1e15
        #expect(gapMs >= 140)
    }

    @Test("Streaming renders are not affected by scroll gate")
    func streamingRendersNotAffectedByScrollGate() async {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 16),
            mathCache: MathRenderCache(capacity: 16)
        )
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0,
                queueCapacity: 64
            )
        )
        scheduler.setActiveConversation(conversationID: "c1", generation: 1)
        scheduler.setLiveScrolling(true)

        let controller = RenderController(
            renderer: renderer,
            scheduler: scheduler,
            coalesceInterval: 0.01
        )

        controller.requestRender(
            content: "streaming during scroll",
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: true,
            hint: nil
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while controller.currentOutput == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(controller.currentOutput != nil)
        #expect(controller.currentOutput?.plainText == "streaming during scroll")
    }
}
