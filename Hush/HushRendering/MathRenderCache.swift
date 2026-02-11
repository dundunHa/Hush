import AppKit

/// Bounded LRU cache for rendered math images.
/// Keyed by `(latex, displayMode, fontSize, color, maxWidth)`.
final class MathRenderCache {
    // MARK: - Types

    struct CacheKey: Hashable {
        let latex: String
        let displayMode: Bool
        let fontSize: Int // truncated
        let colorHash: Int
        let maxWidth: Int
    }

    private final class LRUNode {
        let key: CacheKey
        var previous: LRUNode?
        var next: LRUNode?

        init(key: CacheKey) {
            self.key = key
        }
    }

    private struct LRUList {
        var head: LRUNode?
        var tail: LRUNode?
    }

    private final class Entry {
        var image: NSImage
        let node: LRUNode

        init(image: NSImage, node: LRUNode) {
            self.image = image
            self.node = node
        }
    }

    // MARK: - State

    private var store: [CacheKey: Entry] = [:]
    private var lruList = LRUList()
    private let capacity: Int

    // MARK: - Init

    init(capacity: Int = RenderConstants.mathCacheCapacity) {
        self.capacity = max(1, capacity)
    }

    // MARK: - Public Interface

    func get(_ key: CacheKey) -> NSImage? {
        guard let entry = store[key] else { return nil }
        moveToHead(entry.node)
        return entry.image
    }

    func peek(_ key: CacheKey) -> NSImage? {
        store[key]?.image
    }

    func set(_ key: CacheKey, image: NSImage) {
        if let existing = store[key] {
            existing.image = image
            moveToHead(existing.node)
        } else {
            let node = LRUNode(key: key)
            store[key] = Entry(image: image, node: node)
            insertAtHead(node)
        }
        evictIfNeeded()
    }

    var count: Int {
        store.count
    }

    func clear() {
        store.removeAll()
        lruList = LRUList()
    }

    // MARK: - Helpers

    static func makeKey(
        latex: String,
        displayMode: Bool,
        fontSize: CGFloat,
        color: NSColor,
        maxWidth: CGFloat
    ) -> CacheKey {
        CacheKey(
            latex: latex,
            displayMode: displayMode,
            fontSize: Int(fontSize),
            colorHash: color.hashValue,
            maxWidth: Int(maxWidth)
        )
    }

    // MARK: - Private

    private func evictIfNeeded() {
        while store.count > capacity {
            guard let victim = removeTail() else { break }
            store.removeValue(forKey: victim.key)
        }
    }

    private func moveToHead(_ node: LRUNode) {
        guard lruList.head !== node else { return }
        removeNode(node)
        insertAtHead(node)
    }

    private func insertAtHead(_ node: LRUNode) {
        node.previous = nil
        node.next = lruList.head

        if let head = lruList.head {
            head.previous = node
        } else {
            lruList.tail = node
        }

        lruList.head = node
    }

    private func removeTail() -> LRUNode? {
        guard let tail = lruList.tail else { return nil }
        removeNode(tail)
        return tail
    }

    private func removeNode(_ node: LRUNode) {
        let previous = node.previous
        let next = node.next

        if let previous {
            previous.next = next
        } else if lruList.head === node {
            lruList.head = next
        }

        if let next {
            next.previous = previous
        } else if lruList.tail === node {
            lruList.tail = previous
        }

        node.previous = nil
        node.next = nil
    }
}
