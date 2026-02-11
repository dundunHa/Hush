import Foundation

// MARK: - Scheduler State

@MainActor
struct SchedulerState {
    var runningSessions: [RequestID: RunningSession] = [:]
    var activeQueue: [QueueItemSnapshot] = []
    var backgroundQueues: [String: [QueueItemSnapshot]] = [:]
    var roundRobinCursor: Int = 0
    var activeGrantsSinceLastAged: Int = 0
    var maxConcurrent: Int = RuntimeConstants.defaultMaxConcurrentRequests
}

struct RunningSession: Sendable, Equatable {
    let requestID: RequestID
    let conversationId: String
    let streamTask: Task<Void, Never>?

    static func == (lhs: RunningSession, rhs: RunningSession) -> Bool {
        lhs.requestID == rhs.requestID && lhs.conversationId == rhs.conversationId
    }
}

// MARK: - Deterministic Selection

enum RequestScheduler {
    struct SelectionResult: Equatable {
        let snapshot: QueueItemSnapshot
        let source: SelectionSource
    }

    enum SelectionSource: Equatable {
        case active
        case aged
        case background(conversationId: String)
    }

    static func canAcceptSubmission(state: SchedulerState) -> Bool {
        totalQueuedCount(state: state) < RuntimeConstants.pendingQueueCapacity
    }

    static func totalQueuedCount(state: SchedulerState) -> Int {
        state.activeQueue.count + state.backgroundQueues.values.reduce(0) { $0 + $1.count }
    }

    static func totalRunningCount(state: SchedulerState) -> Int {
        state.runningSessions.count
    }

    static func isConversationRunning(_ conversationId: String, state: SchedulerState) -> Bool {
        state.runningSessions.values.contains { $0.conversationId == conversationId }
    }

    static func conversationsWithRunning(state: SchedulerState) -> Set<String> {
        Set(state.runningSessions.values.map(\.conversationId))
    }

    static func conversationsWithQueued(state: SchedulerState) -> [String: Int] {
        var result: [String: Int] = [:]
        if !state.activeQueue.isEmpty, let convId = state.activeQueue.first?.conversationId {
            result[convId] = state.activeQueue.count
        }
        for (convId, queue) in state.backgroundQueues where !queue.isEmpty {
            result[convId, default: 0] += queue.count
        }
        return result
    }

    /// Deterministic selection: aged → active → background RR.
    /// Returns nil if no eligible request or running limit reached.
    static func selectNext(
        state: inout SchedulerState,
        activeConversationId: String?,
        now: Date = .now
    ) -> SelectionResult? {
        guard totalRunningCount(state: state) < state.maxConcurrent else { return nil }
        let runningConvIds = conversationsWithRunning(state: state)

        // Phase 1: Aged promotion check
        if state.activeGrantsSinceLastAged >= RuntimeConstants.agedQuotaInterval {
            if let result = selectAged(
                state: &state,
                runningConvIds: runningConvIds,
                now: now
            ) {
                state.activeGrantsSinceLastAged = 0
                return result
            }
        }

        // Phase 2: Active queue
        if let activeConvId = activeConversationId,
           !runningConvIds.contains(activeConvId)
        {
            if let idx = state.activeQueue.firstIndex(where: { $0.conversationId == activeConvId }) {
                let snapshot = state.activeQueue.remove(at: idx)
                state.activeGrantsSinceLastAged += 1
                return SelectionResult(snapshot: snapshot, source: .active)
            }
        }

        // Also check active queue head even if it's not for the active conversation
        if let first = state.activeQueue.first,
           !runningConvIds.contains(first.conversationId)
        {
            let snapshot = state.activeQueue.removeFirst()
            state.activeGrantsSinceLastAged += 1
            return SelectionResult(snapshot: snapshot, source: .active)
        }

        // Phase 3: Background round-robin
        return selectBackgroundRoundRobin(state: &state, runningConvIds: runningConvIds)
    }

    private static func selectAged(
        state: inout SchedulerState,
        runningConvIds: Set<String>,
        now: Date
    ) -> SelectionResult? {
        let threshold = RuntimeConstants.agedThresholdSeconds

        // Check active queue for aged items
        if let idx = state.activeQueue.firstIndex(where: {
            now.timeIntervalSince($0.createdAt) >= threshold
                && !runningConvIds.contains($0.conversationId)
        }) {
            let snapshot = state.activeQueue.remove(at: idx)
            return SelectionResult(snapshot: snapshot, source: .aged)
        }

        // Check background queues for aged items
        let sortedKeys = state.backgroundQueues.keys.sorted()
        for key in sortedKeys {
            guard var queue = state.backgroundQueues[key], !queue.isEmpty else { continue }
            if let idx = queue.firstIndex(where: {
                now.timeIntervalSince($0.createdAt) >= threshold
                    && !runningConvIds.contains($0.conversationId)
            }) {
                let snapshot = queue.remove(at: idx)
                if queue.isEmpty {
                    state.backgroundQueues.removeValue(forKey: key)
                } else {
                    state.backgroundQueues[key] = queue
                }
                return SelectionResult(snapshot: snapshot, source: .aged)
            }
        }

        return nil
    }

    private static func selectBackgroundRoundRobin(
        state: inout SchedulerState,
        runningConvIds: Set<String>
    ) -> SelectionResult? {
        let sortedKeys = state.backgroundQueues.keys.sorted()
        guard !sortedKeys.isEmpty else { return nil }

        let startCursor = state.roundRobinCursor % max(sortedKeys.count, 1)
        for offset in 0 ..< sortedKeys.count {
            let idx = (startCursor + offset) % sortedKeys.count
            let key = sortedKeys[idx]
            guard var queue = state.backgroundQueues[key], !queue.isEmpty else { continue }

            let convId = queue[0].conversationId
            guard !runningConvIds.contains(convId) else { continue }

            let snapshot = queue.removeFirst()
            if queue.isEmpty {
                state.backgroundQueues.removeValue(forKey: key)
            } else {
                state.backgroundQueues[key] = queue
            }
            state.roundRobinCursor = idx + 1
            return SelectionResult(snapshot: snapshot, source: .background(conversationId: convId))
        }

        return nil
    }

    /// Enqueue a snapshot into the appropriate queue based on active conversation.
    static func enqueue(
        _ snapshot: QueueItemSnapshot,
        activeConversationId: String?,
        state: inout SchedulerState
    ) {
        if snapshot.conversationId == activeConversationId {
            state.activeQueue.append(snapshot)
        } else {
            state.backgroundQueues[snapshot.conversationId, default: []].append(snapshot)
        }
    }

    /// Rebalance queues when active conversation changes.
    static func rebalanceForActiveSwitch(
        newActiveConversationId: String?,
        state: inout SchedulerState
    ) {
        guard let newId = newActiveConversationId else { return }

        // Move items from background to active if they belong to new active conv
        if let bgQueue = state.backgroundQueues.removeValue(forKey: newId) {
            state.activeQueue.append(contentsOf: bgQueue)
        }

        // Move items from active queue to background if they don't belong to new active conv
        let stayActive = state.activeQueue.filter { $0.conversationId == newId }
        let moveToBackground = state.activeQueue.filter { $0.conversationId != newId }
        state.activeQueue = stayActive

        for item in moveToBackground {
            state.backgroundQueues[item.conversationId, default: []].append(item)
        }
    }

    /// Remove all queued items for a specific conversation.
    static func removeQueued(
        forConversation conversationId: String,
        state: inout SchedulerState
    ) -> [QueueItemSnapshot] {
        var removed: [QueueItemSnapshot] = []

        let (staying, leaving) = state.activeQueue.reduce(into: ([QueueItemSnapshot](), [QueueItemSnapshot]())) {
            if $1.conversationId == conversationId {
                $0.1.append($1)
            } else {
                $0.0.append($1)
            }
        }
        state.activeQueue = staying
        removed.append(contentsOf: leaving)

        if let bgQueue = state.backgroundQueues.removeValue(forKey: conversationId) {
            removed.append(contentsOf: bgQueue)
        }

        return removed
    }
}
