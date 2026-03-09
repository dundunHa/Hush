import Foundation
@testable import Hush
import Testing

struct RequestSchedulerTests {
    // MARK: - Helpers

    private func makeSnapshot(
        conversationId: String,
        createdAt: Date = .now
    ) -> QueueItemSnapshot {
        QueueItemSnapshot(
            prompt: "test",
            providerID: "mock",
            modelID: "mock-text-1",
            parameters: .standard,
            userMessageID: .init(),
            conversationId: conversationId,
            createdAt: createdAt
        )
    }

    // MARK: - Active Priority

    @Test("active conversation queue is selected first")
    @MainActor func activePriority() {
        var state = SchedulerState()
        state.maxConcurrent = 3

        let activeSnap = makeSnapshot(conversationId: "conv-A")
        let bgSnap = makeSnapshot(conversationId: "conv-B")

        RequestScheduler.enqueue(activeSnap, activeConversationId: "conv-A", state: &state)
        RequestScheduler.enqueue(bgSnap, activeConversationId: "conv-A", state: &state)

        let result = RequestScheduler.selectNext(state: &state, activeConversationId: "conv-A")
        #expect(result != nil)
        #expect(result?.snapshot.conversationId == "conv-A")
        #expect(result?.source == .active)
    }

    // MARK: - Background Round-Robin

    @Test("background queues are selected round-robin")
    @MainActor func backgroundRoundRobin() {
        var state = SchedulerState()
        state.maxConcurrent = 5

        let snapB = makeSnapshot(conversationId: "conv-B")
        let snapC = makeSnapshot(conversationId: "conv-C")
        let snapD = makeSnapshot(conversationId: "conv-D")

        RequestScheduler.enqueue(snapB, activeConversationId: "conv-A", state: &state)
        RequestScheduler.enqueue(snapC, activeConversationId: "conv-A", state: &state)
        RequestScheduler.enqueue(snapD, activeConversationId: "conv-A", state: &state)

        let r1 = RequestScheduler.selectNext(state: &state, activeConversationId: "conv-A")
        let r2 = RequestScheduler.selectNext(state: &state, activeConversationId: "conv-A")
        let r3 = RequestScheduler.selectNext(state: &state, activeConversationId: "conv-A")

        let selectedConvs = [r1, r2, r3].compactMap { $0?.snapshot.conversationId }
        #expect(selectedConvs.count == 3)
        #expect(Set(selectedConvs) == Set(["conv-B", "conv-C", "conv-D"]))
    }

    // MARK: - Aged Quota

    @Test("aged request is promoted after K active grants")
    @MainActor func agedQuotaPromotion() {
        var state = SchedulerState()
        state.maxConcurrent = 10
        state.activeGrantsSinceLastAged = RuntimeConstants.agedQuotaInterval

        let agedDate = Date.now.addingTimeInterval(-Double(RuntimeConstants.agedThresholdSeconds) - 1)
        let agedSnap = makeSnapshot(conversationId: "conv-BG", createdAt: agedDate)
        let activeSnap = makeSnapshot(conversationId: "conv-A")

        RequestScheduler.enqueue(activeSnap, activeConversationId: "conv-A", state: &state)
        RequestScheduler.enqueue(agedSnap, activeConversationId: "conv-A", state: &state)

        let result = RequestScheduler.selectNext(state: &state, activeConversationId: "conv-A")
        #expect(result != nil)
        #expect(result?.source == .aged)
        #expect(result?.snapshot.conversationId == "conv-BG")
        #expect(state.activeGrantsSinceLastAged == 0)
    }

    // MARK: - Per-Conversation Limit

    @Test("per-conversation running limit prevents double start")
    @MainActor func perConversationLimit() {
        var state = SchedulerState()
        state.maxConcurrent = 5
        state.runningSessions[RequestID()] = RunningSession(
            requestID: RequestID(),
            conversationId: "conv-A",
            streamTask: nil
        )

        let snap = makeSnapshot(conversationId: "conv-A")
        RequestScheduler.enqueue(snap, activeConversationId: "conv-A", state: &state)

        let result = RequestScheduler.selectNext(state: &state, activeConversationId: "conv-A")
        #expect(result == nil)
    }

    // MARK: - Global Concurrency Limit

    @Test("global running limit is enforced")
    @MainActor func globalConcurrencyLimit() {
        var state = SchedulerState()
        state.maxConcurrent = 2

        for idx in 0 ..< 2 {
            let rid = RequestID()
            state.runningSessions[rid] = RunningSession(
                requestID: rid,
                conversationId: "conv-\(idx)",
                streamTask: nil
            )
        }

        let snap = makeSnapshot(conversationId: "conv-new")
        RequestScheduler.enqueue(snap, activeConversationId: "conv-new", state: &state)

        let result = RequestScheduler.selectNext(state: &state, activeConversationId: "conv-new")
        #expect(result == nil)
    }

    // MARK: - Queue Full Rejection

    @Test("queue full returns false for canAcceptSubmission")
    @MainActor func queueFullRejection() {
        var state = SchedulerState()
        for idx in 0 ..< RuntimeConstants.pendingQueueCapacity {
            let snap = makeSnapshot(conversationId: "conv-\(idx)")
            RequestScheduler.enqueue(snap, activeConversationId: "conv-0", state: &state)
        }

        #expect(!RequestScheduler.canAcceptSubmission(state: state))
    }

    // MARK: - Rebalance

    @Test("rebalance moves items on active switch")
    @MainActor func rebalanceOnSwitch() {
        var state = SchedulerState()

        let snapA = makeSnapshot(conversationId: "conv-A")
        let snapB = makeSnapshot(conversationId: "conv-B")

        RequestScheduler.enqueue(snapA, activeConversationId: "conv-A", state: &state)
        RequestScheduler.enqueue(snapB, activeConversationId: "conv-A", state: &state)

        #expect(state.activeQueue.count == 1)
        #expect(state.backgroundQueues["conv-B"]?.count == 1)

        RequestScheduler.rebalanceForActiveSwitch(
            newActiveConversationId: "conv-B",
            state: &state
        )

        #expect(state.activeQueue.count == 1)
        #expect(state.activeQueue.first?.conversationId == "conv-B")
        #expect(state.backgroundQueues["conv-A"]?.count == 1)
    }
}
