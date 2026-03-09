import AppKit
import Foundation
@testable import Hush
import Testing

struct RenderCacheProtectionTests {
    // MARK: - Helpers

    private func makeStyle() -> RenderStyle {
        .appDefault()
    }

    private func makeOutput(_ text: String) -> MessageRenderOutput {
        MessageRenderOutput(
            attributedString: NSAttributedString(string: text),
            plainText: text,
            diagnostics: []
        )
    }

    // MARK: - Protection Eviction Semantics

    @Test("Protected entries survive eviction when unprotected entries exist")
    func protectedEntriesSurviveWhenUnprotectedExist() {
        let cache = RenderCache(capacity: 3)
        let style = makeStyle()

        let keyA = RenderCache.makeKey(content: "A", width: 500, style: style)
        let keyB = RenderCache.makeKey(content: "B", width: 500, style: style)
        let keyC = RenderCache.makeKey(content: "C", width: 500, style: style)
        cache.set(keyA, output: makeOutput("A"))
        cache.set(keyB, output: makeOutput("B"))
        cache.set(keyC, output: makeOutput("C"))

        cache.markProtected(key: keyA, conversationID: "conv-1")

        let keyD = RenderCache.makeKey(content: "D", width: 500, style: style)
        cache.set(keyD, output: makeOutput("D"))

        #expect(cache.get(keyA) != nil)
        #expect(cache.get(keyB) == nil)
        #expect(cache.get(keyC) != nil)
        #expect(cache.get(keyD) != nil)
    }

    @Test("All-protected cache falls back to LRU eviction")
    func allProtectedFallsBackToLRU() {
        let cache = RenderCache(capacity: 3)
        let style = makeStyle()

        let keyA = RenderCache.makeKey(content: "A", width: 500, style: style)
        let keyB = RenderCache.makeKey(content: "B", width: 500, style: style)
        let keyC = RenderCache.makeKey(content: "C", width: 500, style: style)
        cache.set(keyA, output: makeOutput("A"))
        cache.set(keyB, output: makeOutput("B"))
        cache.set(keyC, output: makeOutput("C"))

        cache.markProtected(key: keyA, conversationID: "conv-1")
        cache.markProtected(key: keyB, conversationID: "conv-1")
        cache.markProtected(key: keyC, conversationID: "conv-1")

        let keyD = RenderCache.makeKey(content: "D", width: 500, style: style)
        cache.set(keyD, output: makeOutput("D"))

        #expect(cache.get(keyA) == nil) // LRU evicted
        #expect(cache.get(keyB) != nil)
        #expect(cache.get(keyC) != nil)
        #expect(cache.get(keyD) != nil)
    }

    @Test("Protection is additive across conversations and clearProtection removes only that conversation")
    func protectionAdditiveAndClearProtection() {
        let cache = RenderCache(capacity: 3)
        let style = makeStyle()

        let keyA = RenderCache.makeKey(content: "A", width: 500, style: style)
        let keyB = RenderCache.makeKey(content: "B", width: 500, style: style)
        let keyC = RenderCache.makeKey(content: "C", width: 500, style: style)
        cache.set(keyA, output: makeOutput("A"))
        cache.set(keyB, output: makeOutput("B"))
        cache.set(keyC, output: makeOutput("C"))

        cache.markProtected(key: keyA, conversationID: "conv-1")
        cache.markProtected(key: keyA, conversationID: "conv-2")
        cache.markProtected(key: keyB, conversationID: "conv-1")

        cache.clearProtection(conversationID: "conv-1")

        let keyD = RenderCache.makeKey(content: "D", width: 500, style: style)
        cache.set(keyD, output: makeOutput("D"))

        // keyA remains protected by conv-2, keyB is now unprotected and should be evicted first.
        #expect(cache.get(keyA) != nil)
        #expect(cache.get(keyB) == nil)
        #expect(cache.get(keyC) != nil)
        #expect(cache.get(keyD) != nil)
    }

    @Test("Per-conversation protection is bounded to P=12 and overflows remove the oldest protected key")
    func perConversationProtectionBoundedToTwelve() {
        let cache = RenderCache(capacity: 13)
        let style = makeStyle()
        let conversationID = "conv-1"

        let keys: [RenderCache.CacheKey] = (0 ... 12).map { idx in
            RenderCache.makeKey(content: "K\(idx)", width: 500, style: style)
        }

        for (idx, key) in keys.enumerated() {
            cache.set(key, output: makeOutput("K\(idx)"))
            cache.markProtected(key: key, conversationID: conversationID)
        }

        // After protecting 13 keys with P=12, the oldest key (K0) must lose protection.
        // Touch K0 so it becomes non-LRU; then inserting a new key should evict K0 (unprotected),
        // not K1 (protected), proving overflow unprotected the oldest.
        _ = cache.get(keys[0])

        let keyNew = RenderCache.makeKey(content: "K-new", width: 500, style: style)
        cache.set(keyNew, output: makeOutput("K-new"))

        #expect(cache.get(keys[0]) == nil)
        #expect(cache.get(keys[1]) != nil)
        #expect(cache.get(keyNew) != nil)
    }

    @Test("clearAllProtections removes all protection state")
    func clearAllProtectionsRemovesState() {
        let cache = RenderCache(capacity: 3)
        let style = makeStyle()

        let keyA = RenderCache.makeKey(content: "A", width: 500, style: style)
        let keyB = RenderCache.makeKey(content: "B", width: 500, style: style)
        let keyC = RenderCache.makeKey(content: "C", width: 500, style: style)
        cache.set(keyA, output: makeOutput("A"))
        cache.set(keyB, output: makeOutput("B"))
        cache.set(keyC, output: makeOutput("C"))

        cache.markProtected(key: keyA, conversationID: "conv-1")
        cache.clearAllProtections()

        let keyD = RenderCache.makeKey(content: "D", width: 500, style: style)
        cache.set(keyD, output: makeOutput("D"))

        // With protections cleared, eviction should revert to plain LRU.
        #expect(cache.get(keyA) == nil)
        #expect(cache.get(keyB) != nil)
        #expect(cache.get(keyD) != nil)
    }

    @Test("Unprotect migrates key back to unprotected eviction list")
    func unprotectMigratesBackToUnprotectedList() {
        let cache = RenderCache(capacity: 2)
        let style = makeStyle()

        let keyA = RenderCache.makeKey(content: "A", width: 500, style: style)
        let keyB = RenderCache.makeKey(content: "B", width: 500, style: style)
        let keyC = RenderCache.makeKey(content: "C", width: 500, style: style)
        let keyD = RenderCache.makeKey(content: "D", width: 500, style: style)

        cache.set(keyA, output: makeOutput("A"))
        cache.set(keyB, output: makeOutput("B"))
        cache.markProtected(key: keyA, conversationID: "conv-1")

        cache.set(keyC, output: makeOutput("C"))
        #expect(cache.get(keyA) != nil)
        #expect(cache.get(keyB) == nil)

        cache.clearProtection(conversationID: "conv-1")
        _ = cache.get(keyC)
        cache.set(keyD, output: makeOutput("D"))

        #expect(cache.get(keyA) == nil)
        #expect(cache.get(keyC) != nil)
        #expect(cache.get(keyD) != nil)
    }
}
