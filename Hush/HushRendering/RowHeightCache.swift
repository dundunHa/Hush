import AppKit

final class RowHeightCache {
    private var store: [RenderCache.CacheKey: CGFloat] = [:]

    func value(for key: RenderCache.CacheKey) -> CGFloat? {
        store[key]
    }

    func set(_ height: CGFloat, for key: RenderCache.CacheKey) {
        store[key] = height
    }

    func remove(_ key: RenderCache.CacheKey) {
        store.removeValue(forKey: key)
    }

    func clear() {
        store.removeAll()
    }

    var count: Int {
        store.count
    }
}
