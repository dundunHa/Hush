import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Multi-Scene Render Scheduler")
struct MultiSceneSchedulerTests {
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

    @Test("Hot tier work is demoted: high -> visible")
    func hotHighIsDemotedToVisible() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0,
                queueCapacity: 64
            )
        )
        scheduler.setSceneConfiguration(
            active: ("active", 1),
            hot: [("hot", 1)]
        )

        var executionOrder: [String] = []

        scheduler.enqueue(
            key: .init(conversationID: "hot", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .high,
            input: makeInput("hot-high"),
            render: { input in makeOutput(input.content) },
            apply: { _ in executionOrder.append("hot") }
        )

        scheduler.enqueue(
            key: .init(conversationID: "active", messageID: UUID(), fingerprint: 2, generation: 1),
            priority: .high,
            input: makeInput("active-high"),
            render: { input in makeOutput(input.content) },
            apply: { _ in executionOrder.append("active") }
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while executionOrder.count < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(executionOrder.count == 2)
        #expect(executionOrder.first == "active")
    }

    @Test("Hot tier work is demoted: visible -> deferred")
    func hotVisibleIsDemotedToDeferred() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0,
                queueCapacity: 64
            )
        )
        scheduler.setSceneConfiguration(
            active: ("active", 1),
            hot: [("hot", 1)]
        )

        var executionOrder: [String] = []

        scheduler.enqueue(
            key: .init(conversationID: "hot", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .visible,
            input: makeInput("hot-visible"),
            render: { input in makeOutput(input.content) },
            apply: { _ in executionOrder.append("hot") }
        )

        scheduler.enqueue(
            key: .init(conversationID: "active", messageID: UUID(), fingerprint: 2, generation: 1),
            priority: .visible,
            input: makeInput("active-visible"),
            render: { input in makeOutput(input.content) },
            apply: { _ in executionOrder.append("active") }
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while executionOrder.count < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(executionOrder.count == 2)
        #expect(executionOrder.first == "active")
    }

    @Test("Cold tier work is pruned and never executed")
    func coldTierWorkIsPruned() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0,
                queueCapacity: 64
            )
        )
        scheduler.setSceneConfiguration(
            active: ("active", 1),
            hot: [("hot", 1)]
        )

        var didApplyCold = false
        scheduler.enqueue(
            key: .init(conversationID: "cold", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .high,
            input: makeInput("cold"),
            render: { input in makeOutput(input.content) },
            apply: { _ in didApplyCold = true }
        )

        await Task.yield()
        #expect(!didApplyCold)
    }

    @Test("Hot tier generation mismatch is pruned")
    func hotGenerationMismatchIsPruned() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0,
                queueCapacity: 64
            )
        )
        scheduler.setSceneConfiguration(
            active: ("active", 2),
            hot: [("hot", 2)]
        )

        var didApply = false
        scheduler.enqueue(
            key: .init(conversationID: "hot", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .high,
            input: makeInput("stale"),
            render: { input in makeOutput(input.content) },
            apply: { _ in didApply = true }
        )

        await Task.yield()
        #expect(!didApply)
    }

    @Test("Atomic scene configuration update prunes queued hot work")
    func atomicSceneConfigurationUpdatePrunesQueuedHotWork() async {
        let scheduler = ConversationRenderScheduler(
            configuration: .init(
                budgetInterval: 0,
                idleDelay: 0.2,
                queueCapacity: 64
            )
        )
        scheduler.setSceneConfiguration(
            active: ("active", 1),
            hot: [("hot", 1)]
        )

        var didApply = false
        scheduler.enqueue(
            key: .init(conversationID: "hot", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .idle,
            input: makeInput("hot-idle"),
            render: { input in makeOutput(input.content) },
            apply: { _ in didApply = true }
        )

        scheduler.setSceneConfiguration(
            active: ("active", 1),
            hot: []
        )

        try? await Task.sleep(for: .milliseconds(350))
        #expect(!didApply)
    }

    @Test("setActiveConversation wrapper is equivalent to setSceneConfiguration(active, hot: [])")
    func setActiveConversationWrapperIsEquivalent() async {
        let configuration = ConversationRenderScheduler.Configuration(
            budgetInterval: 0,
            idleDelay: 0,
            queueCapacity: 64
        )

        let schedulerA = ConversationRenderScheduler(configuration: configuration)
        schedulerA.setActiveConversation(conversationID: "c1", generation: 1)

        let schedulerB = ConversationRenderScheduler(configuration: configuration)
        schedulerB.setSceneConfiguration(active: ("c1", 1), hot: [])

        var appliedA: [String] = []
        var appliedB: [String] = []

        schedulerA.enqueue(
            key: .init(conversationID: "c2", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .high,
            input: makeInput("cold-A"),
            render: { input in makeOutput(input.content) },
            apply: { _ in appliedA.append("cold") }
        )
        schedulerB.enqueue(
            key: .init(conversationID: "c2", messageID: UUID(), fingerprint: 1, generation: 1),
            priority: .high,
            input: makeInput("cold-B"),
            render: { input in makeOutput(input.content) },
            apply: { _ in appliedB.append("cold") }
        )

        schedulerA.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 2, generation: 1),
            priority: .high,
            input: makeInput("active-A"),
            render: { input in makeOutput(input.content) },
            apply: { _ in appliedA.append("active") }
        )
        schedulerB.enqueue(
            key: .init(conversationID: "c1", messageID: UUID(), fingerprint: 2, generation: 1),
            priority: .high,
            input: makeInput("active-B"),
            render: { input in makeOutput(input.content) },
            apply: { _ in appliedB.append("active") }
        )

        let deadline = ContinuousClock.now + .seconds(1)
        while appliedA.count < 1 || appliedB.count < 1, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(appliedA == ["active"])
        #expect(appliedB == ["active"])
    }
}
