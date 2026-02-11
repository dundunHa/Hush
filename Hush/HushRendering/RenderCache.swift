import AppKit

/// Bounded LRU cache for rendered message output.
/// Keyed by `(contentHash, width, styleKey)`.
final class RenderCache {
    // MARK: - Types

    struct CacheKey: Hashable {
        let contentHash: Int
        let width: Int // truncated to integer points
        let styleKey: Int
    }

    private enum ListKind {
        case unprotected
        case protected
    }

    private enum InsertPosition {
        case head
        case tail
    }

    private final class LRUNode<Key: Hashable> {
        let key: Key
        var previous: LRUNode<Key>?
        var next: LRUNode<Key>?
        var listKind: ListKind

        init(key: Key, listKind: ListKind) {
            self.key = key
            self.listKind = listKind
        }
    }

    private struct LRUList<Key: Hashable> {
        var head: LRUNode<Key>?
        var tail: LRUNode<Key>?
    }

    private final class Entry {
        var output: MessageRenderOutput
        let node: LRUNode<CacheKey>

        init(output: MessageRenderOutput, node: LRUNode<CacheKey>) {
            self.output = output
            self.node = node
        }
    }

    // MARK: - State

    private var store: [CacheKey: Entry] = [:]
    private var unprotectedList = LRUList<CacheKey>()
    private var protectedList = LRUList<CacheKey>()
    private var mostRecentlyUsedKey: CacheKey?
    private let capacity: Int
    private let perConversationProtectionLimit: Int = 12
    private var onRemove: ((CacheKey) -> Void)?

    private var conversationToKeys: [String: Set<CacheKey>] = [:]
    private var conversationProtectionOrder: [String: [CacheKey]] = [:]
    private var keyToConversations: [CacheKey: Set<String>] = [:]

    // MARK: - Init

    init(
        capacity: Int = RenderConstants.messageCacheCapacity,
        onRemove: ((CacheKey) -> Void)? = nil
    ) {
        self.capacity = max(1, capacity)
        self.onRemove = onRemove
    }

    // MARK: - Public Interface

    func get(_ key: CacheKey) -> MessageRenderOutput? {
        guard let entry = store[key] else { return nil }
        touchKey(key)
        return entry.output
    }

    func peek(_ key: CacheKey) -> MessageRenderOutput? {
        store[key]?.output
    }

    func set(_ key: CacheKey, output: MessageRenderOutput) {
        if let existing = store[key] {
            existing.output = output
            moveToHead(existing.node)
            mostRecentlyUsedKey = key
        } else {
            let node = LRUNode(key: key, listKind: .unprotected)
            store[key] = Entry(output: output, node: node)
            insertAtHead(node, in: &unprotectedList)
            mostRecentlyUsedKey = key
        }
        evictIfNeeded()
    }

    func markProtected(key: CacheKey, conversationID: String) {
        guard store[key] != nil else { return }
        let wasProtected = isProtected(key)

        if conversationToKeys[conversationID]?.contains(key) == true {
            // Refresh insertion order so the newest protections are retained.
            if var order = conversationProtectionOrder[conversationID],
               let idx = order.firstIndex(of: key)
            {
                order.remove(at: idx)
                order.append(key)
                conversationProtectionOrder[conversationID] = order
            }
            keyToConversations[key, default: []].insert(conversationID)
            if !wasProtected {
                moveNode(for: key, to: .protected)
            }
            return
        }

        if let existingOrder = conversationProtectionOrder[conversationID],
           existingOrder.count >= perConversationProtectionLimit,
           let oldest = existingOrder.first
        {
            unprotect(key: oldest, conversationID: conversationID)
        }

        conversationToKeys[conversationID, default: []].insert(key)
        conversationProtectionOrder[conversationID, default: []].append(key)
        keyToConversations[key, default: []].insert(conversationID)
        if !wasProtected {
            moveNode(for: key, to: .protected)
        }
    }

    func clearProtection(conversationID: String) {
        guard let keys = conversationToKeys[conversationID] else {
            conversationProtectionOrder.removeValue(forKey: conversationID)
            return
        }
        for key in keys {
            unprotect(key: key, conversationID: conversationID)
        }
        conversationToKeys.removeValue(forKey: conversationID)
        conversationProtectionOrder.removeValue(forKey: conversationID)
    }

    func clearAllProtections() {
        conversationToKeys.removeAll()
        conversationProtectionOrder.removeAll()
        keyToConversations.removeAll()

        while let node = removeHead(from: &protectedList) {
            node.listKind = .unprotected
            insertAtTail(node, in: &unprotectedList)
        }
    }

    var count: Int {
        store.count
    }

    var isEmpty: Bool {
        store.isEmpty
    }

    func clear() {
        let existingKeys = Array(store.keys)
        store.removeAll()
        unprotectedList = LRUList()
        protectedList = LRUList()
        conversationToKeys.removeAll()
        conversationProtectionOrder.removeAll()
        keyToConversations.removeAll()
        mostRecentlyUsedKey = nil

        for key in existingKeys {
            onRemove?(key)
        }
    }

    func setOnRemove(_ handler: ((CacheKey) -> Void)?) {
        onRemove = handler
    }

    // MARK: - Helpers

    static func makeKey(content: String, width: CGFloat, style: RenderStyle) -> CacheKey {
        CacheKey(
            contentHash: content.hashValue,
            width: Int(width),
            styleKey: style.cacheKey
        )
    }

    // MARK: - Private

    private func touchKey(_ key: CacheKey) {
        guard let node = store[key]?.node else { return }
        moveToHead(node)
        mostRecentlyUsedKey = key
    }

    private func evictIfNeeded() {
        while store.count > capacity {
            if let unprotectedVictim = unprotectedList.tail {
                let hasSingleUnprotected = unprotectedList.head === unprotectedVictim
                let shouldSkipSingleNewestUnprotected =
                    hasSingleUnprotected
                        && protectedList.tail != nil
                        && unprotectedVictim.key == mostRecentlyUsedKey
                if !shouldSkipSingleNewestUnprotected,
                   let victim = removeTail(from: &unprotectedList)
                {
                    removeEntry(victim.key, detachedNode: victim)
                    continue
                }
            }
            if let victim = removeTail(from: &protectedList) {
                removeEntry(victim.key, detachedNode: victim)
                continue
            }
            if let victim = removeTail(from: &unprotectedList) {
                removeEntry(victim.key, detachedNode: victim)
                continue
            }
            break
        }
    }

    private func isProtected(_ key: CacheKey) -> Bool {
        keyToConversations[key]?.isEmpty == false
    }

    private func unprotect(key: CacheKey, conversationID: String) {
        conversationToKeys[conversationID]?.remove(key)
        if let set = conversationToKeys[conversationID], set.isEmpty {
            conversationToKeys.removeValue(forKey: conversationID)
        }

        if var order = conversationProtectionOrder[conversationID] {
            order.removeAll { $0 == key }
            if order.isEmpty {
                conversationProtectionOrder.removeValue(forKey: conversationID)
            } else {
                conversationProtectionOrder[conversationID] = order
            }
        }

        if var conversations = keyToConversations[key] {
            conversations.remove(conversationID)
            if conversations.isEmpty {
                keyToConversations.removeValue(forKey: key)
                moveNode(for: key, to: .unprotected, position: .tail)
            } else {
                keyToConversations[key] = conversations
            }
        }
    }

    private func removeEntry(
        _ key: CacheKey,
        detachedNode: LRUNode<CacheKey>? = nil
    ) {
        guard let entry = store.removeValue(forKey: key) else { return }

        if detachedNode == nil {
            removeNode(entry.node)
        }
        removeProtection(for: key)
        if mostRecentlyUsedKey == key {
            mostRecentlyUsedKey = nil
        }
        onRemove?(key)
    }

    private func removeProtection(for key: CacheKey) {
        guard let conversations = keyToConversations.removeValue(forKey: key) else { return }
        for conversationID in conversations {
            conversationToKeys[conversationID]?.remove(key)
            if let set = conversationToKeys[conversationID], set.isEmpty {
                conversationToKeys.removeValue(forKey: conversationID)
            }

            if var order = conversationProtectionOrder[conversationID] {
                order.removeAll { $0 == key }
                if order.isEmpty {
                    conversationProtectionOrder.removeValue(forKey: conversationID)
                } else {
                    conversationProtectionOrder[conversationID] = order
                }
            }
        }
    }

    private func moveNode(
        for key: CacheKey,
        to listKind: ListKind,
        position: InsertPosition = .head
    ) {
        guard let node = store[key]?.node else { return }
        guard node.listKind != listKind else {
            switch position {
            case .head:
                moveToHead(node)
            case .tail:
                moveToTail(node)
            }
            return
        }

        removeNode(node)
        node.listKind = listKind
        switch (listKind, position) {
        case (.unprotected, .head):
            insertAtHead(node, in: &unprotectedList)
        case (.unprotected, .tail):
            insertAtTail(node, in: &unprotectedList)
        case (.protected, .head):
            insertAtHead(node, in: &protectedList)
        case (.protected, .tail):
            insertAtTail(node, in: &protectedList)
        }
    }

    private func moveToHead(_ node: LRUNode<CacheKey>) {
        switch node.listKind {
        case .unprotected:
            moveToHead(node, in: &unprotectedList)
        case .protected:
            moveToHead(node, in: &protectedList)
        }
    }

    private func moveToHead(
        _ node: LRUNode<CacheKey>,
        in list: inout LRUList<CacheKey>
    ) {
        guard list.head !== node else { return }
        removeNode(node, from: &list)
        insertAtHead(node, in: &list)
    }

    private func moveToTail(_ node: LRUNode<CacheKey>) {
        switch node.listKind {
        case .unprotected:
            moveToTail(node, in: &unprotectedList)
        case .protected:
            moveToTail(node, in: &protectedList)
        }
    }

    private func moveToTail(
        _ node: LRUNode<CacheKey>,
        in list: inout LRUList<CacheKey>
    ) {
        guard list.tail !== node else { return }
        removeNode(node, from: &list)
        insertAtTail(node, in: &list)
    }

    private func insertAtHead(
        _ node: LRUNode<CacheKey>,
        in list: inout LRUList<CacheKey>
    ) {
        node.previous = nil
        node.next = list.head

        if let head = list.head {
            head.previous = node
        } else {
            list.tail = node
        }

        list.head = node
    }

    private func insertAtTail(
        _ node: LRUNode<CacheKey>,
        in list: inout LRUList<CacheKey>
    ) {
        node.next = nil
        node.previous = list.tail

        if let tail = list.tail {
            tail.next = node
        } else {
            list.head = node
        }

        list.tail = node
    }

    private func removeTail(from list: inout LRUList<CacheKey>) -> LRUNode<CacheKey>? {
        guard let tail = list.tail else { return nil }
        removeNode(tail, from: &list)
        return tail
    }

    private func removeHead(from list: inout LRUList<CacheKey>) -> LRUNode<CacheKey>? {
        guard let head = list.head else { return nil }
        removeNode(head, from: &list)
        return head
    }

    private func removeNode(_ node: LRUNode<CacheKey>) {
        switch node.listKind {
        case .unprotected:
            removeNode(node, from: &unprotectedList)
        case .protected:
            removeNode(node, from: &protectedList)
        }
    }

    private func removeNode(
        _ node: LRUNode<CacheKey>,
        from list: inout LRUList<CacheKey>
    ) {
        let previous = node.previous
        let next = node.next

        if let previous {
            previous.next = next
        } else if list.head === node {
            list.head = next
        }

        if let next {
            next.previous = previous
        } else if list.tail === node {
            list.tail = previous
        }

        node.previous = nil
        node.next = nil
    }
}

#if DEBUG
    extension RenderCache {
        func protectedKeyCountForTesting(conversationID: String) -> Int {
            conversationToKeys[conversationID]?.count ?? 0
        }
    }
#endif
