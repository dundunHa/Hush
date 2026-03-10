import Foundation
@testable import Hush
import Testing

@MainActor
struct AppContainerProviderSettingsTests {
    @Test("saveOpenAISettings stores apiKey in provider config and omits it from JSON settings")
    func saveOpenAISettingsStoresPersistedAPIKey() throws {
        let container = AppContainer.forTesting()

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
        #expect(config?.endpoint == OpenAIProvider.defaultEndpoint)
        #expect(config?.apiKey == "sk-test-plaintext")

        let encodedSettings = try JSONEncoder().encode(container.settings)
        let payload = String(bytes: encodedSettings, encoding: .utf8) ?? ""
        #expect(!payload.contains("sk-test-plaintext"))
    }

    @Test("enabled OpenAI save preserves current provider selection")
    func enabledOpenAISavePreservesCurrentSelection() throws {
        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard
        )
        let container = AppContainer.forTesting(settings: settings)

        _ = try container.saveOpenAISettings(
            OpenAISettingsInput(
                endpoint: "https://api.openai.com/v1",
                defaultModelID: "gpt-4.1-mini",
                isEnabled: true,
                apiKey: "sk-select-openai"
            )
        )

        #expect(container.settings.selectedProviderID == "mock")
        #expect(container.settings.selectedModelID == "mock-text-1")
    }

    @Test("enabled OpenAI save without any credential fails explicitly")
    func enabledOpenAISaveWithoutCredentialFails() {
        let container = AppContainer.forTesting()

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

    @Test("empty API key is allowed when credential already exists without auto-selecting OpenAI")
    func emptyAPIKeyAllowedWithStoredCredential() throws {
        let settings = AppSettings(
            providerConfigurations: [
                ProviderConfiguration(
                    id: "openai",
                    name: "OpenAI",
                    type: .openAI,
                    endpoint: OpenAIProvider.defaultEndpoint,
                    apiKeyEnvironmentVariable: "",
                    defaultModelID: "gpt-4.1",
                    isEnabled: true,
                    apiKey: "sk-existing"
                )
            ],
            selectedProviderID: "",
            selectedModelID: "",
            parameters: .standard,
            quickBar: .standard
        )
        let container = AppContainer.forTesting(settings: settings)

        let snapshot = try container.saveOpenAISettings(
            OpenAISettingsInput(
                endpoint: "https://api.openai.com/v1",
                defaultModelID: "gpt-4.1",
                isEnabled: true,
                apiKey: ""
            )
        )

        #expect(snapshot.hasCredential)
        #expect(container.settings.providerConfigurations.first(where: { $0.id == "openai" })?.apiKey == "sk-existing")
        #expect(container.settings.selectedProviderID.isEmpty)
        #expect(container.settings.selectedModelID.isEmpty)
    }

    @Test("empty defaultModelID fails with defaultModelRequired")
    func emptyDefaultModelIDFailsWithValidationError() {
        let settings = AppSettings(
            providerConfigurations: [
                ProviderConfiguration(
                    id: "openai",
                    name: "OpenAI",
                    type: .openAI,
                    endpoint: OpenAIProvider.defaultEndpoint,
                    apiKeyEnvironmentVariable: "",
                    defaultModelID: "gpt-4.1",
                    isEnabled: true,
                    apiKey: "sk-existing"
                )
            ],
            selectedProviderID: "",
            selectedModelID: "",
            parameters: .standard,
            quickBar: .standard
        )
        let container = AppContainer.forTesting(settings: settings)

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
        let settings = AppSettings(
            providerConfigurations: [
                ProviderConfiguration(
                    id: "openai",
                    name: "OpenAI",
                    type: .openAI,
                    endpoint: OpenAIProvider.defaultEndpoint,
                    apiKeyEnvironmentVariable: "",
                    defaultModelID: "gpt-4.1",
                    isEnabled: true,
                    apiKey: "sk-existing"
                )
            ],
            selectedProviderID: "",
            selectedModelID: "",
            parameters: .standard,
            quickBar: .standard
        )
        let container = AppContainer.forTesting(settings: settings)

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

    @Test("disabled OpenAI can save without a default model")
    func disabledOpenAICanSaveWithoutDefaultModel() throws {
        let container = AppContainer.forTesting()

        let snapshot = try container.saveOpenAISettings(
            OpenAISettingsInput(
                endpoint: "",
                defaultModelID: "",
                isEnabled: false,
                apiKey: ""
            )
        )

        #expect(snapshot.defaultModelID.isEmpty)
        #expect(container.settings.selectedProviderID.isEmpty)
    }

    @Test("disabling selected openai falls back to mock provider")
    func disablingSelectedOpenAIFallsBackToMock() throws {
        let openAIConfiguration = ProviderConfiguration(
            id: "openai",
            name: "OpenAI",
            type: .openAI,
            endpoint: OpenAIProvider.defaultEndpoint,
            apiKeyEnvironmentVariable: "",
            defaultModelID: "gpt-4o-mini",
            isEnabled: true,
            apiKey: "sk-existing"
        )
        let settings = AppSettings(
            providerConfigurations: [.mockDefault(), openAIConfiguration],
            selectedProviderID: "openai",
            selectedModelID: "gpt-4o-mini",
            parameters: .standard,
            quickBar: .standard
        )
        let container = AppContainer.forTesting(settings: settings)

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

    @Test("saving selected OpenAI updates selected model to its saved default")
    func savingSelectedOpenAIUpdatesSelectedModel() throws {
        let openAIConfiguration = ProviderConfiguration(
            id: "openai",
            name: "OpenAI",
            type: .openAI,
            endpoint: OpenAIProvider.defaultEndpoint,
            apiKeyEnvironmentVariable: "",
            defaultModelID: "gpt-4o-mini",
            isEnabled: true,
            apiKey: "sk-existing"
        )
        let settings = AppSettings(
            providerConfigurations: [.mockDefault(), openAIConfiguration],
            selectedProviderID: "openai",
            selectedModelID: "gpt-4o-mini",
            parameters: .standard,
            quickBar: .standard
        )
        let container = AppContainer.forTesting(settings: settings)

        _ = try container.saveOpenAISettings(
            OpenAISettingsInput(
                endpoint: OpenAIProvider.defaultEndpoint,
                defaultModelID: "gpt-4.1",
                isEnabled: true,
                apiKey: ""
            )
        )

        #expect(container.settings.selectedProviderID == "openai")
        #expect(container.settings.selectedModelID == "gpt-4.1")
    }
}
