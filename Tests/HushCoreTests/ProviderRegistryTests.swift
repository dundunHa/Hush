import XCTest
@testable import HushCore
@testable import HushProviders

final class ProviderRegistryTests: XCTestCase {

    func testRegisterAndLookupProvider() async throws {
        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let provider = registry.provider(for: "mock")
        let models = try await provider?.availableModels()

        XCTAssertNotNil(provider)
        XCTAssertEqual(models?.first?.id, "mock-text-1")
    }

    func testProviderNotFoundReturnsNil() {
        let registry = ProviderRegistry()
        XCTAssertNil(registry.provider(for: "nonexistent"))
    }

    func testAllProviderIDsReturnsSorted() {
        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "zebra"))
        registry.register(MockProvider(id: "alpha"))
        registry.register(MockProvider(id: "middle"))

        XCTAssertEqual(registry.allProviderIDs(), ["alpha", "middle", "zebra"])
    }

    func testAllProviderIDsEmptyWhenEmpty() {
        let registry = ProviderRegistry()
        XCTAssertEqual(registry.allProviderIDs(), [])
    }

    func testFirstProviderReturnsAlphabeticallyFirst() {
        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "zebra"))
        registry.register(MockProvider(id: "alpha"))

        let first = registry.firstProvider()
        XCTAssertEqual(first?.id, "alpha")
    }

    func testFirstProviderReturnsNilWhenEmpty() {
        let registry = ProviderRegistry()
        XCTAssertNil(registry.firstProvider())
    }

    func testInitWithProvidersArray() {
        let registry = ProviderRegistry(providers: [
            MockProvider(id: "a"),
            MockProvider(id: "b")
        ])

        XCTAssertNotNil(registry.provider(for: "a"))
        XCTAssertNotNil(registry.provider(for: "b"))
        XCTAssertEqual(registry.allProviderIDs(), ["a", "b"])
    }

    func testRegisterOverwritesSameID() {
        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))
        registry.register(MockProvider(id: "mock"))

        // Should still be exactly 1 provider
        XCTAssertEqual(registry.allProviderIDs().count, 1)
    }
}
