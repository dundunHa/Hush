import Foundation
import os

/// Serial scheduler for non-streaming rich render work.
///
/// Work is prioritized by conversation-local recency and visibility so
/// switch-time rendering can prefer latest visible assistant messages.
@MainActor
final class ConversationRenderScheduler {
    enum SceneTier: Equatable {
        case active
        case hot
        case cold
    }

    enum RenderWorkPriority: Int, Comparable {
        case high = 0
        case visible = 1
        case deferred = 2
        case idle = 3

        static func < (lhs: RenderWorkPriority, rhs: RenderWorkPriority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct RenderWorkKey: Hashable {
        let conversationID: String
        let messageID: UUID
        let fingerprint: Int
        let generation: UInt64
    }

    struct Configuration {
        let budgetInterval: TimeInterval
        let idleDelay: TimeInterval
        let queueCapacity: Int

        init(
            budgetInterval: TimeInterval,
            idleDelay: TimeInterval,
            queueCapacity: Int
        ) {
            self.budgetInterval = max(0, budgetInterval)
            self.idleDelay = max(0, idleDelay)
            self.queueCapacity = max(1, queueCapacity)
        }

        static var appDefault: Configuration {
            Configuration(
                budgetInterval: RenderConstants.nonStreamingRenderBudgetInterval,
                idleDelay: RenderConstants.offscreenIdleStartDelay,
                queueCapacity: RenderConstants.nonStreamingQueueCapacity
            )
        }
    }

    private struct RenderWorkItem {
        let key: RenderWorkKey
        let priority: RenderWorkPriority
        let notBefore: Date
        let enqueuedAt: Date
        let input: MessageRenderInput
        let render: (MessageRenderInput) -> MessageRenderOutput
        let apply: (MessageRenderOutput) -> Void
    }

    // MARK: - Debug

    private enum SwitchSchedulerDebug {
        static var isEnabled: Bool {
            #if DEBUG
                guard let raw = ProcessInfo.processInfo.environment["HUSH_SWITCH_DEBUG"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                else {
                    return false
                }
                return raw == "1" || raw == "true" || raw == "yes"
            #else
                return false
            #endif
        }

        static var isContentEnabled: Bool {
            #if DEBUG
                guard let raw = ProcessInfo.processInfo.environment["HUSH_CONTENT_DEBUG"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                else {
                    return false
                }
                return raw == "1" || raw == "true" || raw == "yes"
            #else
                return false
            #endif
        }

        private static let logger = Logger(subsystem: "com.hush.app", category: "SwitchRenderScheduler")
        private static let chunkSize = 256

        static func log(_ message: String, content: String? = nil) {
            guard isEnabled else { return }
            logger.debug("\(message, privacy: .public)")
            guard isContentEnabled, let content else { return }
            var offset = content.startIndex
            var part = 1
            while offset < content.endIndex {
                let end = content.index(offset, offsetBy: chunkSize, limitedBy: content.endIndex) ?? content.endIndex
                let chunk = String(content[offset ..< end])
                logger.debug("[content \(part, privacy: .public)] \(chunk, privacy: .public)")
                offset = end
                part += 1
            }
        }
    }

    // MARK: - State

    private let configuration: Configuration
    private var workItemsByKey: [RenderWorkKey: RenderWorkItem] = [:]
    private var insertionOrder: [RenderWorkKey] = []
    private var workerTask: Task<Void, Never>?

    private struct SceneConfiguration: Equatable {
        let activeConversationID: String
        let activeGeneration: UInt64
        let hotGenerationsByConversationID: [String: UInt64]
    }

    private var sceneConfiguration: SceneConfiguration?
    private var isLiveScrolling = false

    // MARK: - Init

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    convenience init() {
        self.init(configuration: .appDefault)
    }

    deinit {
        workerTask?.cancel()
    }

    // MARK: - Public Interface

    func setActiveConversation(
        conversationID: String?,
        generation: UInt64
    ) {
        guard let conversationID else {
            sceneConfiguration = nil
            workItemsByKey.removeAll()
            insertionOrder.removeAll()
            workerTask?.cancel()
            workerTask = nil
            return
        }

        setSceneConfiguration(active: (conversationID, generation), hot: [])
    }

    func setSceneConfiguration(
        active: (String, UInt64),
        hot: [(String, UInt64)]
    ) {
        let hotMap = Dictionary(uniqueKeysWithValues: hot)
        sceneConfiguration = SceneConfiguration(
            activeConversationID: active.0,
            activeGeneration: active.1,
            hotGenerationsByConversationID: hotMap
        )
        pruneStaleWorkItems(reason: "set-scene-config")
        startWorkerIfNeeded()
    }

    func setLiveScrolling(_ value: Bool) {
        isLiveScrolling = value
        if !value {
            startWorkerIfNeeded()
        }
    }

    func enqueue(
        key: RenderWorkKey,
        priority: RenderWorkPriority,
        input: MessageRenderInput,
        render: @escaping (MessageRenderInput) -> MessageRenderOutput,
        apply: @escaping (MessageRenderOutput) -> Void
    ) {
        if isStale(key) {
            SwitchSchedulerDebug.log(
                "skip-stale-enqueue conversation=\(key.conversationID) message=\(key.messageID.uuidString.prefix(8)) " +
                    "generation=\(key.generation)"
            )
            return
        }

        let effectivePriority = demotePriorityIfNeeded(priority, forConversationID: key.conversationID)
        let now = Date.now
        let notBefore =
            effectivePriority == .idle
                ? now.addingTimeInterval(configuration.idleDelay)
                : now

        if workItemsByKey[key] != nil {
            insertionOrder.removeAll { $0 == key }
        }

        workItemsByKey[key] = RenderWorkItem(
            key: key,
            priority: effectivePriority,
            notBefore: notBefore,
            enqueuedAt: now,
            input: input,
            render: render,
            apply: apply
        )
        insertionOrder.append(key)

        SwitchSchedulerDebug.log(
            "enqueue priority=\(effectivePriority.rawValue) queueDepth=\(workItemsByKey.count) " +
                "conversation=\(key.conversationID) message=\(key.messageID.uuidString.prefix(8)) " +
                "generation=\(key.generation)",
            content: input.content
        )

        enforceQueueCapacity()
        startWorkerIfNeeded()
    }

    // MARK: - Private

    private enum WorkSelection {
        case execute(RenderWorkItem)
        case wait(TimeInterval)
    }

    private func startWorkerIfNeeded() {
        guard workerTask == nil else { return }

        workerTask = Task { [weak self] in
            guard let self else { return }
            await runWorkerLoop()
        }
    }

    private func runWorkerLoop() async {
        defer { workerTask = nil }

        while !Task.isCancelled {
            pruneStaleWorkItems(reason: "loop")

            if isLiveScrolling {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }

            guard let selection = selectNextWork(now: .now) else { return }

            switch selection {
            case let .wait(duration):
                let waitMs = max(0, Int(duration * 1000))
                SwitchSchedulerDebug.log(
                    "wait waitMs=\(waitMs) queueDepth=\(workItemsByKey.count)"
                )
                guard duration > 0 else {
                    await Task.yield()
                    continue
                }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            case let .execute(item):
                let queuedMs = max(0, Int(Date.now.timeIntervalSince(item.enqueuedAt) * 1000))
                SwitchSchedulerDebug.log(
                    "dequeue priority=\(item.priority.rawValue) queueDepth=\(workItemsByKey.count) " +
                        "waitMs=\(queuedMs) conversation=\(item.key.conversationID) " +
                        "message=\(item.key.messageID.uuidString.prefix(8)) generation=\(item.key.generation)",
                    content: item.input.content
                )

                if isStale(item.key) {
                    SwitchSchedulerDebug.log(
                        "skip-stale conversation=\(item.key.conversationID) " +
                            "message=\(item.key.messageID.uuidString.prefix(8)) generation=\(item.key.generation)"
                    )
                    continue
                }

                let output = item.render(item.input)
                guard !Task.isCancelled else { return }

                if isStale(item.key) {
                    SwitchSchedulerDebug.log(
                        "skip-stale-after-render conversation=\(item.key.conversationID) " +
                            "message=\(item.key.messageID.uuidString.prefix(8)) generation=\(item.key.generation)"
                    )
                    continue
                }

                item.apply(output)

                guard configuration.budgetInterval > 0 else { continue }
                try? await Task.sleep(nanoseconds: UInt64(configuration.budgetInterval * 1_000_000_000))
            }
        }
    }

    private func selectNextWork(now: Date) -> WorkSelection? {
        let activeItems = insertionOrder.compactMap { key in
            workItemsByKey[key]
        }

        guard !activeItems.isEmpty else { return nil }

        let ready = activeItems
            .filter { $0.notBefore <= now }
            .sorted(by: Self.compareExecutionOrder)

        if let selected = ready.first {
            removeWorkItem(forKey: selected.key)
            return .execute(selected)
        }

        guard let earliestNotBefore = activeItems.map(\.notBefore).min() else {
            return nil
        }
        return .wait(max(0, earliestNotBefore.timeIntervalSince(now)))
    }

    private static func compareExecutionOrder(
        lhs: RenderWorkItem,
        rhs: RenderWorkItem
    ) -> Bool {
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        return lhs.enqueuedAt < rhs.enqueuedAt
    }

    private func enforceQueueCapacity() {
        while workItemsByKey.count > configuration.queueCapacity {
            guard let dropped = lowestPriorityOldestItem() else { return }
            removeWorkItem(forKey: dropped.key)
            SwitchSchedulerDebug.log(
                "drop reason=capacity priority=\(dropped.priority.rawValue) queueDepth=\(workItemsByKey.count) " +
                    "conversation=\(dropped.key.conversationID) message=\(dropped.key.messageID.uuidString.prefix(8)) " +
                    "generation=\(dropped.key.generation)"
            )
        }
    }

    private func lowestPriorityOldestItem() -> RenderWorkItem? {
        let candidates = insertionOrder.compactMap { key -> (RenderWorkKey, RenderWorkItem)? in
            guard let item = workItemsByKey[key], item.priority != .high else { return nil }
            return (key, item)
        }

        guard !candidates.isEmpty else { return nil }

        let ordered = candidates.sorted { lhs, rhs in
            if lhs.1.priority != rhs.1.priority {
                return lhs.1.priority.rawValue > rhs.1.priority.rawValue
            }
            return lhs.1.enqueuedAt < rhs.1.enqueuedAt
        }
        return ordered.first?.1
    }

    private func pruneStaleWorkItems(reason: String) {
        guard !workItemsByKey.isEmpty else { return }

        let staleKeys = insertionOrder.filter(isStale)
        guard !staleKeys.isEmpty else { return }

        for key in staleKeys {
            removeWorkItem(forKey: key)
            SwitchSchedulerDebug.log(
                "skip-stale reason=\(reason) queueDepth=\(workItemsByKey.count) " +
                    "conversation=\(key.conversationID) message=\(key.messageID.uuidString.prefix(8)) generation=\(key.generation)"
            )
        }
    }

    private func isStale(_ key: RenderWorkKey) -> Bool {
        guard let config = sceneConfiguration else { return false }

        switch sceneTier(for: key.conversationID, config: config) {
        case .cold:
            return true
        case .active:
            return key.generation != config.activeGeneration
        case .hot:
            let expected = config.hotGenerationsByConversationID[key.conversationID] ?? 0
            return key.generation != expected
        }
    }

    private func sceneTier(
        for conversationID: String,
        config: SceneConfiguration
    ) -> SceneTier {
        if conversationID == config.activeConversationID {
            return .active
        }
        if config.hotGenerationsByConversationID[conversationID] != nil {
            return .hot
        }
        return .cold
    }

    private func demotePriorityIfNeeded(
        _ priority: RenderWorkPriority,
        forConversationID conversationID: String
    ) -> RenderWorkPriority {
        guard let config = sceneConfiguration else { return priority }
        guard sceneTier(for: conversationID, config: config) == .hot else { return priority }

        switch priority {
        case .high:
            return .visible
        case .visible:
            return .deferred
        case .deferred, .idle:
            return priority
        }
    }

    private func removeWorkItem(forKey key: RenderWorkKey) {
        workItemsByKey.removeValue(forKey: key)
        insertionOrder.removeAll { $0 == key }
    }
}
