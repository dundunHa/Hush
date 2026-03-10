import Foundation
@testable import Hush
import Testing

struct ProviderCredentialPersistenceTests {
    @Test("ProviderConfiguration JSON encoding omits apiKey")
    func providerConfigurationJSONOmitsAPIKey() throws {
        let config = ProviderConfiguration(
            id: "openai",
            name: "OpenAI",
            type: .openAI,
            endpoint: OpenAIProvider.defaultEndpoint,
            apiKeyEnvironmentVariable: "",
            defaultModelID: "gpt-4.1",
            isEnabled: true,
            apiKey: "sk-test-plaintext"
        )

        let payload = try JSONEncoder().encode(config)
        let json = try #require(String(bytes: payload, encoding: .utf8))

        #expect(!json.contains("sk-test-plaintext"))
    }

    @Test("ProviderConfigurationRecord roundtrip preserves persisted apiKey")
    func providerConfigurationRecordRoundtripPreservesAPIKey() {
        let original = ProviderConfiguration(
            id: "openai",
            name: "OpenAI",
            type: .openAI,
            endpoint: OpenAIProvider.defaultEndpoint,
            apiKeyEnvironmentVariable: "",
            defaultModelID: "gpt-4.1",
            isEnabled: true,
            apiKey: "sk-persisted"
        )

        let record = ProviderConfigurationRecord.from(original)
        let roundtrip = record.toProviderConfiguration()

        #expect(roundtrip.apiKey == "sk-persisted")
        #expect(roundtrip.normalizedAPIKey == "sk-persisted")
    }
}

struct CredentialResolverTests {
    @Test("Resolver returns trimmed API key when present")
    func resolverReturnsTrimmedAPIKey() throws {
        let resolver = CredentialResolver()
        let secret = try resolver.resolve(providerID: "openai", apiKey: "  sk-resolver-test  ")

        #expect(secret == "sk-resolver-test")
    }

    @Test("Resolver throws CredentialResolutionError when API key is missing")
    func resolverThrowsWhenMissing() {
        let resolver = CredentialResolver()

        #expect(throws: CredentialResolutionError.self) {
            _ = try resolver.resolve(providerID: "openai", apiKey: nil)
        }
    }

    @Test("Resolver treats whitespace-only API key as missing")
    func resolverRejectsWhitespaceOnlyAPIKey() {
        let resolver = CredentialResolver()

        #expect(throws: CredentialResolutionError.self) {
            _ = try resolver.resolve(providerID: "openai", apiKey: "   \t  ")
        }
    }
}
