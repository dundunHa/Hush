import AppKit
@testable import Hush
import Testing

@Suite("Math Render Cache")
struct MathRenderCacheTests {
    private func makeKey(_ latex: String) -> MathRenderCache.CacheKey {
        MathRenderCache.makeKey(
            latex: latex,
            displayMode: false,
            fontSize: 14,
            color: .white,
            maxWidth: 480
        )
    }

    private func makeImage() -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10))
    }

    @Test("Peek does not touch LRU order")
    func peekDoesNotTouchLRUOrder() {
        let cache = MathRenderCache(capacity: 2)
        let keyA = makeKey("A")
        let keyB = makeKey("B")
        let keyC = makeKey("C")

        cache.set(keyA, image: makeImage())
        cache.set(keyB, image: makeImage())
        #expect(cache.peek(keyA) != nil)

        cache.set(keyC, image: makeImage())

        #expect(cache.get(keyA) == nil)
        #expect(cache.get(keyB) != nil)
        #expect(cache.get(keyC) != nil)
    }

    @Test("Get touches entry and keeps it from eviction")
    func getTouchesEntry() {
        let cache = MathRenderCache(capacity: 2)
        let keyA = makeKey("A")
        let keyB = makeKey("B")
        let keyC = makeKey("C")

        cache.set(keyA, image: makeImage())
        cache.set(keyB, image: makeImage())
        _ = cache.get(keyA)

        cache.set(keyC, image: makeImage())

        #expect(cache.get(keyA) != nil)
        #expect(cache.get(keyB) == nil)
        #expect(cache.get(keyC) != nil)
    }
}
