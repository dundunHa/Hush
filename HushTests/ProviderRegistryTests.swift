import Foundation
@testable import Hush
import Testing

struct ProviderRegistryTests {
    // MARK: - Helpers

    private func makeProvider(id: String) -> MockProvider {
        MockProvider(id: id)
    }

    // MARK: - init & provider(for:)

    @Test("init with providers registers all by ID")
    func initRegistersAll() {
        let registry = ProviderRegistry(providers: [
            makeProvider(id: "alpha"),
            makeProvider(id: "beta")
        ])

        #expect(registry.provider(for: "alpha") != nil)
        #expect(registry.provider(for: "beta") != nil)
    }

    @Test("provider(for:) returns nil for unknown ID")
    func providerForUnknownIDReturnsNil() {
        let registry = ProviderRegistry(providers: [makeProvider(id: "alpha")])
        #expect(registry.provider(for: "nonexistent") == nil)
    }

    @Test("init with duplicate IDs keeps last provider")
    func initDuplicateIDKeepsLast() {
        let first = MockProvider(id: "dup", streamBehavior: .default)
        let second = MockProvider(id: "dup", streamBehavior: .failing(after: 0))

        let registry = ProviderRegistry(providers: [first, second])
        let resolved = registry.provider(for: "dup") as? MockProvider

        #expect(resolved != nil)
        #expect(resolved?.streamBehavior.failAfterChunks == 0)
    }

    // MARK: - register

    @Test("register overwrites existing provider with same ID")
    func registerOverwrites() {
        var registry = ProviderRegistry(providers: [makeProvider(id: "alpha")])
        let replacement = MockProvider(id: "alpha", streamBehavior: .failing(after: 1))
        registry.register(replacement)

        let resolved = registry.provider(for: "alpha") as? MockProvider
        #expect(resolved?.streamBehavior.failAfterChunks == 1)
    }

    // MARK: - allProviderIDs

    @Test("allProviderIDs returns sorted IDs")
    func allProviderIDsSorted() {
        let registry = ProviderRegistry(providers: [
            makeProvider(id: "charlie"),
            makeProvider(id: "alpha"),
            makeProvider(id: "bravo")
        ])

        #expect(registry.allProviderIDs() == ["alpha", "bravo", "charlie"])
    }

    @Test("allProviderIDs returns empty array for empty registry")
    func allProviderIDsEmpty() {
        let registry = ProviderRegistry()
        #expect(registry.allProviderIDs().isEmpty)
    }

    // MARK: - firstProvider

    @Test("firstProvider returns provider with alphabetically smallest ID")
    func firstProviderAlphabetical() {
        let registry = ProviderRegistry(providers: [
            makeProvider(id: "zulu"),
            makeProvider(id: "alpha"),
            makeProvider(id: "mike")
        ])

        let first = registry.firstProvider()
        #expect(first?.id == "alpha")
    }

    @Test("firstProvider returns nil for empty registry")
    func firstProviderEmpty() {
        let registry = ProviderRegistry()
        #expect(registry.firstProvider() == nil)
    }
}
