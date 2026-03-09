import Foundation

@MainActor
final class HotScenePool {
    struct SwitchResult {
        let scene: ConversationViewController
        let didCreate: Bool
        let evicted: (conversationID: String, scene: ConversationViewController)?
    }

    private let capacity: Int
    private var scenesByConversationID: [String: ConversationViewController] = [:]
    private var accessOrder: [String] = []
    private var messageCounts: [String: Int] = [:]
    private var generationsByConversationID: [String: UInt64] = [:]

    private(set) var activeConversationID: String?

    init(capacity: Int = RenderConstants.hotScenePoolCapacity) {
        self.capacity = min(max(1, capacity), 6)
    }

    var hotConversationIDs: [String] {
        accessOrder.filter { $0 != activeConversationID }
    }

    func hotConversationGenerations() -> [(String, UInt64)] {
        hotConversationIDs.compactMap { id in
            generationsByConversationID[id].map { (id, $0) }
        }
    }

    func sceneFor(conversationID: String) -> ConversationViewController? {
        scenesByConversationID[conversationID]
    }

    func generationForConversation(conversationID: String) -> UInt64? {
        generationsByConversationID[conversationID]
    }

    func markNeedsReload(conversationID: String) {
        guard conversationID != activeConversationID else { return }
        guard let scene = scenesByConversationID[conversationID] else { return }
        scene.needsReload = true
    }

    func switchTo(
        conversationID: String,
        messageCount: Int,
        generation: UInt64,
        makeScene: () -> ConversationViewController
    ) -> SwitchResult {
        if let existing = scenesByConversationID[conversationID] {
            PerfTrace.count(
                PerfTrace.Event.switchScenePoolPath,
                fields: [
                    "path": "hot-hit",
                    "conversation": conversationID,
                    "generation": "\(generation)"
                ]
            )
            activeConversationID = conversationID
            messageCounts[conversationID] = messageCount
            generationsByConversationID[conversationID] = generation
            touch(conversationID)
            return SwitchResult(scene: existing, didCreate: false, evicted: nil)
        }

        var evicted: (conversationID: String, scene: ConversationViewController)?
        if scenesByConversationID.count >= capacity, let victim = evictColdest() {
            evicted = victim
        }

        PerfTrace.count(
            PerfTrace.Event.switchScenePoolPath,
            fields: [
                "path": "cold-miss",
                "conversation": conversationID,
                "generation": "\(generation)",
                "evicted": evicted == nil ? "false" : "true"
            ]
        )

        let scene = makeScene()
        scenesByConversationID[conversationID] = scene
        messageCounts[conversationID] = messageCount
        generationsByConversationID[conversationID] = generation
        activeConversationID = conversationID
        touch(conversationID)

        return SwitchResult(scene: scene, didCreate: true, evicted: evicted)
    }

    func remove(conversationID: String) {
        scenesByConversationID.removeValue(forKey: conversationID)
        messageCounts.removeValue(forKey: conversationID)
        generationsByConversationID.removeValue(forKey: conversationID)
        accessOrder.removeAll { $0 == conversationID }
        if activeConversationID == conversationID {
            activeConversationID = nil
        }
    }

    // MARK: - Eviction

    func evictColdest() -> (conversationID: String, scene: ConversationViewController)? {
        guard !accessOrder.isEmpty else { return nil }

        let empties = accessOrder.filter { (messageCounts[$0] ?? 0) == 0 }
        let victimID = (empties.first ?? accessOrder.first)
        guard let victimID, let victimScene = scenesByConversationID[victimID] else { return nil }

        remove(conversationID: victimID)
        return (victimID, victimScene)
    }

    // MARK: - LRU

    private func touch(_ conversationID: String) {
        accessOrder.removeAll { $0 == conversationID }
        accessOrder.append(conversationID)
    }
}
