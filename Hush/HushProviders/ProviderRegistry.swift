import Foundation

public struct ProviderRegistry {
    private var providers: [String: any LLMProvider] = [:]

    public init(providers: [any LLMProvider] = []) {
        for provider in providers {
            self.providers[provider.id] = provider
        }
    }

    public mutating func register(_ provider: any LLMProvider) {
        providers[provider.id] = provider
    }

    public func provider(for id: String) -> (any LLMProvider)? {
        providers[id]
    }

    public func allProviderIDs() -> [String] {
        providers.keys.sorted()
    }

    public func firstProvider() -> (any LLMProvider)? {
        providers.sorted(by: { $0.key < $1.key }).first?.value
    }
}

