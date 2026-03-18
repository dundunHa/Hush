import Foundation
@testable import Hush
import Testing

@MainActor
struct AppContainerProviderSettingsTests {
    @Test("saveOpenAISettings writes credentialRef and no plaintext secret")
    func saveOpenAISettingsWritesCredentialRefOnly() throws {
        let credentialStore = InMemoryCredentialStore()
        let container = AppContainer.forTesting(credentialStore: credentialStore)

        _ = try container.saveOpenAISettings(
            OpenAISettingsInput(
                endpoint: "",
                defaultModelID: "gpt-4o-mini",
                isEnabled: true,
                apiKey: "sk-test-plaintext"
            )
        )

        let config = container.settings.providerConfigurations.first(where: { $0.id == "openai" })
        #expect(config != nil)
        #expect(config?.credentialRef == "openai")
        #expect(config?.endpoint == OpenAIProvider.defaultEndpoint)
        #expect(credentialStore.storedSecret(for: "openai") == "sk-test-plaintext")

        let encodedSettings = try JSONEncoder().encode(container.settings)
        let payload = String(bytes: encodedSettings, encoding: .utf8) ?? ""
        #expect(!payload.contains("sk-test-plaintext"))
    }

    @Test("enabled OpenAI save auto-selects provider and model")
    func enabledOpenAISaveAutoSelects() throws {
        let credentialStore = InMemoryCredentialStore()
        let container = AppContainer.forTesting(credentialStore: credentialStore)

        _ = try container.saveOpenAISettings(
            OpenAISettingsInput(
                endpoint: "https://api.openai.com/v1",
                defaultModelID: "gpt-4.1-mini",
                isEnabled: true,
                apiKey: "sk-select-openai"
            )
        )

        #expect(container.settings.selectedProviderID == "openai")
        #expect(container.settings.selectedModelID == "gpt-4.1-mini")
    }

    @Test("enabled OpenAI save without any credential fails explicitly")
    func enabledOpenAISaveWithoutCredentialFails() {
        let credentialStore = InMemoryCredentialStore()
        let container = AppContainer.forTesting(credentialStore: credentialStore)

        do {
            _ = try container.saveOpenAISettings(
                OpenAISettingsInput(
                    endpoint: "",
                    defaultModelID: "gpt-4o-mini",
                    isEnabled: true,
                    apiKey: ""
                )
            )
            Issue.record("Expected save to fail when enabled without credential")
        } catch let error as OpenAISettingsSaveError {
            #expect(error == .credentialRequired)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("empty API key is allowed when credential already exists")
    func emptyAPIKeyAllowedWithStoredCredential() throws {
        let credentialStore = InMemoryCredentialStore(secrets: ["openai": "sk-existing"])
        let container = AppContainer.forTesting(credentialStore: credentialStore)

        let snapshot = try container.saveOpenAISettings(
            OpenAISettingsInput(
                endpoint: "https://api.openai.com/v1",
                defaultModelID: "gpt-4.1",
                isEnabled: true,
                apiKey: ""
            )
        )

        #expect(snapshot.hasCredential)
        #expect(credentialStore.storedSecret(for: "openai") == "sk-existing")
        #expect(container.settings.selectedProviderID == "openai")
        #expect(container.settings.selectedModelID == "gpt-4.1")
    }

    @Test("empty defaultModelID fails with defaultModelRequired")
    func emptyDefaultModelIDFailsWithValidationError() {
        let credentialStore = InMemoryCredentialStore(secrets: ["openai": "sk-existing"])
        let container = AppContainer.forTesting(credentialStore: credentialStore)

        do {
            _ = try container.saveOpenAISettings(
                OpenAISettingsInput(
                    endpoint: "",
                    defaultModelID: "",
                    isEnabled: true,
                    apiKey: ""
                )
            )
            Issue.record("Expected save to fail when defaultModelID is empty")
        } catch let error as OpenAISettingsSaveError {
            #expect(error == .defaultModelRequired)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("whitespace-only defaultModelID fails with defaultModelRequired")
    func whitespaceOnlyDefaultModelIDFailsWithValidationError() {
        let credentialStore = InMemoryCredentialStore(secrets: ["openai": "sk-existing"])
        let container = AppContainer.forTesting(credentialStore: credentialStore)

        do {
            _ = try container.saveOpenAISettings(
                OpenAISettingsInput(
                    endpoint: "",
                    defaultModelID: "   \t  ",
                    isEnabled: true,
                    apiKey: ""
                )
            )
            Issue.record("Expected save to fail when defaultModelID is whitespace-only")
        } catch let error as OpenAISettingsSaveError {
            #expect(error == .defaultModelRequired)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("disabling selected openai falls back to mock provider")
    func disablingSelectedOpenAIFallsBackToMock() throws {
        let credentialStore = InMemoryCredentialStore(secrets: ["openai": "sk-existing"])
        let openAIConfiguration = ProviderConfiguration(
            id: "openai",
            name: "OpenAI",
            type: .openAI,
            endpoint: OpenAIProvider.defaultEndpoint,
            apiKeyEnvironmentVariable: "",
            defaultModelID: "gpt-4o-mini",
            isEnabled: true,
            credentialRef: "openai"
        )
        let settings = AppSettings(
            providerConfigurations: [.mockDefault(), openAIConfiguration],
            selectedProviderID: "openai",
            selectedModelID: "gpt-4o-mini",
            parameters: .standard,
            quickBar: .standard
        )
        let container = AppContainer.forTesting(
            settings: settings,
            credentialStore: credentialStore
        )

        _ = try container.saveOpenAISettings(
            OpenAISettingsInput(
                endpoint: OpenAIProvider.defaultEndpoint,
                defaultModelID: "gpt-4o-mini",
                isEnabled: false,
                apiKey: ""
            )
        )

        #expect(container.settings.selectedProviderID == "mock")
        #expect(container.settings.selectedModelID == "mock-text-1")
    }
}

private final class InMemoryCredentialStore: KeychainCredentialStore, @unchecked Sendable {
    private var secrets: [String: String]

    init(secrets: [String: String] = [:]) {
        self.secrets = secrets
    }

    func setSecret(_ secret: String, forCredentialRef credentialRef: String) throws {
        secrets[credentialRef] = secret
    }

    func secret(forCredentialRef credentialRef: String) throws -> String {
        guard let secret = secrets[credentialRef] else {
            throw KeychainError.itemNotFound
        }
        return secret
    }

    func hasSecret(forCredentialRef credentialRef: String) -> Bool {
        secrets[credentialRef] != nil
    }

    func storedSecret(for credentialRef: String) -> String? {
        secrets[credentialRef]
    }
}
