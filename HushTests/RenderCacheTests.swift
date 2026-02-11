import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Render Cache")
struct RenderCacheTests {
    // MARK: - Helpers

    private func makeRenderer() -> MessageContentRenderer {
        MessageContentRenderer()
    }

    private func makeStyle() -> RenderStyle {
        .appDefault()
    }

    // MARK: - Task 8.4: Width/Style Affect Cache Keys

    @Test("Different widths produce different cache keys")
    func widthAffectsCacheKey() {
        let style = makeStyle()
        let key1 = RenderCache.makeKey(content: "hello", width: 400, style: style)
        let key2 = RenderCache.makeKey(content: "hello", width: 600, style: style)
        #expect(key1 != key2)
    }

    @Test("Same content and width hit cache")
    func cacheHit() {
        let cache = RenderCache(capacity: 10)
        let style = makeStyle()
        let key = RenderCache.makeKey(content: "test", width: 500, style: style)

        let output = MessageRenderOutput(
            attributedString: NSAttributedString(string: "test"),
            plainText: "test",
            diagnostics: []
        )
        cache.set(key, output: output)

        let cached = cache.get(key)
        #expect(cached != nil)
        #expect(cached?.plainText == "test")
    }

    @Test("Different content misses cache")
    func cacheMiss() {
        let cache = RenderCache(capacity: 10)
        let style = makeStyle()
        let key1 = RenderCache.makeKey(content: "hello", width: 500, style: style)
        let key2 = RenderCache.makeKey(content: "world", width: 500, style: style)

        let output = MessageRenderOutput(
            attributedString: NSAttributedString(string: "hello"),
            plainText: "hello",
            diagnostics: []
        )
        cache.set(key1, output: output)

        #expect(cache.get(key2) == nil)
    }

    @Test("Peek returns cached value without changing LRU order")
    func peekDoesNotTouchLRUOrder() {
        let cache = RenderCache(capacity: 2)
        let style = makeStyle()
        let keyA = RenderCache.makeKey(content: "A", width: 500, style: style)
        let keyB = RenderCache.makeKey(content: "B", width: 500, style: style)
        let keyC = RenderCache.makeKey(content: "C", width: 500, style: style)

        cache.set(keyA, output: MessageRenderOutput(
            attributedString: NSAttributedString(string: "A"),
            plainText: "A",
            diagnostics: []
        ))
        cache.set(keyB, output: MessageRenderOutput(
            attributedString: NSAttributedString(string: "B"),
            plainText: "B",
            diagnostics: []
        ))

        #expect(cache.peek(keyA)?.plainText == "A")

        cache.set(keyC, output: MessageRenderOutput(
            attributedString: NSAttributedString(string: "C"),
            plainText: "C",
            diagnostics: []
        ))

        #expect(cache.get(keyA) == nil)
        #expect(cache.get(keyB) != nil)
        #expect(cache.get(keyC) != nil)
    }

    // MARK: - Task 8.8: Width Change Reflow

    @Test("Width change does not reuse stale cached layout")
    func widthChangeNoStaleCache() {
        let renderer = makeRenderer()
        let content = "Some markdown **content** here"

        let output1 = renderer.render(MessageRenderInput(
            content: content, availableWidth: 400
        ))
        let output2 = renderer.render(MessageRenderInput(
            content: content, availableWidth: 800
        ))

        // Both should render successfully
        #expect(output1.attributedString.length > 0)
        #expect(output2.attributedString.length > 0)
        // Cache should have 2 entries (different widths)
        #expect(renderer.messageCacheCount == 2)
    }

    // MARK: - Task 8.9: Cache Bounds and Eviction

    @Test("Message cache is bounded and evicts deterministically")
    func messageCacheBounded() {
        let cache = RenderCache(capacity: 3)
        let style = makeStyle()

        for idx in 0 ..< 5 {
            let key = RenderCache.makeKey(
                content: "content\(idx)", width: 500, style: style
            )
            let output = MessageRenderOutput(
                attributedString: NSAttributedString(string: "content\(idx)"),
                plainText: "content\(idx)",
                diagnostics: []
            )
            cache.set(key, output: output)
        }

        // Should be capped at capacity
        #expect(cache.count == 3)

        // Oldest entries (0, 1) should have been evicted
        let key0 = RenderCache.makeKey(
            content: "content0", width: 500, style: style
        )
        #expect(cache.get(key0) == nil)

        // Newest entries (2, 3, 4) should still be present
        let key4 = RenderCache.makeKey(
            content: "content4", width: 500, style: style
        )
        #expect(cache.get(key4) != nil)
    }

    @Test("Math cache is bounded and evicts deterministically")
    func mathCacheBounded() {
        let cache = MathRenderCache(capacity: 3)

        for idx in 0 ..< 5 {
            let key = MathRenderCache.makeKey(
                latex: "x_{\(idx)}",
                displayMode: false,
                fontSize: 14,
                color: .white,
                maxWidth: 500
            )
            let image = NSImage(size: NSSize(width: 10, height: 10))
            cache.set(key, image: image)
        }

        #expect(cache.count == 3)
    }

    @Test("RenderCache capacity is clamped to at least one")
    func capacityIsClampedToAtLeastOne() {
        let cache = RenderCache(capacity: 0)
        let style = makeStyle()

        let key1 = RenderCache.makeKey(content: "one", width: 500, style: style)
        let key2 = RenderCache.makeKey(content: "two", width: 500, style: style)
        cache.set(key1, output: MessageRenderOutput(
            attributedString: NSAttributedString(string: "one"),
            plainText: "one",
            diagnostics: []
        ))
        cache.set(key2, output: MessageRenderOutput(
            attributedString: NSAttributedString(string: "two"),
            plainText: "two",
            diagnostics: []
        ))

        #expect(cache.count == 1)
        #expect(cache.get(key1) == nil)
        #expect(cache.get(key2) != nil)
    }

    @Test("Cache clear removes all entries")
    func cacheClear() {
        let cache = RenderCache(capacity: 10)
        let style = makeStyle()

        for idx in 0 ..< 5 {
            let key = RenderCache.makeKey(
                content: "content\(idx)", width: 500, style: style
            )
            let output = MessageRenderOutput(
                attributedString: NSAttributedString(string: "c"),
                plainText: "c",
                diagnostics: []
            )
            cache.set(key, output: output)
        }
        #expect(cache.count == 5)

        cache.clear()
        #expect(cache.isEmpty)
    }

    @MainActor
    @Test("Shared renderer cache is reused across controllers")
    func sharedRendererReusesAcrossControllers() async {
        let renderer = MessageContentRenderer()
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let first = runtime.makeRenderController()
        let second = runtime.makeRenderController()
        let content = String(repeating: "reuse cache content ", count: 140) // > 2000 chars

        first.requestRender(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false
        )

        let deadline = ContinuousClock.now + .seconds(2)
        while first.currentOutput == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(first.currentOutput != nil)
        #expect(renderer.messageCacheCount > 0)

        second.requestRender(
            content: content,
            availableWidth: 640,
            style: .appDefault(),
            isStreaming: false
        )

        #expect(second.currentOutput != nil)
    }
}
