import Foundation
@testable import Hush
import Testing

@MainActor
struct AppContainerSettingsPersistenceTests {
    private func makeRepoAndContainer() throws -> (GRDBAppPreferencesRepository, AppContainer) {
        let dbManager = try DatabaseManager.inMemory()
        let repo = GRDBAppPreferencesRepository(dbManager: dbManager)
        let providerConfigRepo = GRDBProviderConfigurationRepository(dbManager: dbManager)
        let container = AppContainer.forTesting(
            preferencesRepository: repo,
            providerConfigRepository: providerConfigRepo
        )
        return (repo, container)
    }

    @Test("modifying settings sets isDirty")
    func modifyingSettingsSetsDirty() throws {
        let (_, container) = try makeRepoAndContainer()
        #expect(!container.isDirty)

        container.settings.selectedModelID = "changed-model"

        #expect(container.isDirty)
    }

    @Test("flushSettings writes to database and clears isDirty")
    func flushSettingsWritesToDatabase() throws {
        let (repo, container) = try makeRepoAndContainer()

        container.settings.selectedModelID = "flushed-model"
        #expect(container.isDirty)

        container.flushSettings()

        #expect(!container.isDirty)

        let loaded = try repo.fetch()
        #expect(loaded?.selectedModelID == "flushed-model")
    }

    @Test("flushSettings persists provider added via addPlaceholderProvider")
    func flushSettingsPersistsAddedProvider() throws {
        let (repo, container) = try makeRepoAndContainer()

        container.addPlaceholderProvider()
        container.flushSettings()

        let loaded = try repo.fetch()
        #expect(loaded != nil)
        let customProviders = container.settings.providerConfigurations.filter { $0.name == "OpenAI Compatible" }
        #expect(customProviders.count == 1)
        #expect(customProviders.first?.name == "OpenAI Compatible")
    }

    @Test("flushSettings persists provider removal")
    func flushSettingsPersistsRemoval() throws {
        let (_, container) = try makeRepoAndContainer()

        container.addPlaceholderProvider()
        container.flushSettings()

        let addedID = try #require(container.settings.providerConfigurations.first(where: { $0.name == "OpenAI Compatible" })?.id)
        container.removeProviderProfile(id: addedID)
        container.flushSettings()

        #expect(!container.settings.providerConfigurations.contains(where: { $0.id == addedID }))
    }

    @Test("flushSettings is idempotent when not dirty")
    func flushSettingsIdempotentWhenClean() throws {
        let (repo, container) = try makeRepoAndContainer()

        container.settings.selectedModelID = "test-model"
        container.flushSettings()
        #expect(!container.isDirty)

        container.flushSettings()
        #expect(!container.isDirty)

        let loaded = try repo.fetch()
        #expect(loaded?.selectedModelID == "test-model")
    }

    @Test("saveProviderProfile change is persisted after flush")
    func saveProviderProfilePersistedAfterFlush() throws {
        let (_, container) = try makeRepoAndContainer()

        let profile = ProviderConfiguration(
            id: "anthropic",
            name: "Anthropic",
            type: .openAI,
            endpoint: "https://api.anthropic.com",
            apiKeyEnvironmentVariable: "",
            defaultModelID: "claude-3",
            isEnabled: true,
            credentialRef: "anthropic"
        )
        container.saveProviderProfile(profile)
        container.flushSettings()

        let persisted = container.settings.providerConfigurations.first(where: { $0.id == "anthropic" })
        #expect(persisted != nil)
        #expect(persisted?.defaultModelID == "claude-3")
    }

    @Test("flushSettings preserves theme value in persisted preferences")
    func flushSettingsPreservesThemeValue() throws {
        let (repo, container) = try makeRepoAndContainer()
        #expect(container.settings.theme == .dark)

        container.settings.theme = .readPaper
        container.settings.selectedModelID = "theme-persist-model"
        container.flushSettings()

        let loaded = try repo.fetch()
        #expect(loaded?.theme == AppTheme.readPaper.rawValue)
    }

    @Test("theme-related settings flush does not mutate sidebar threads")
    func themeRelatedSettingsFlushDoesNotMutateSidebarThreads() throws {
        let (_, container) = try makeRepoAndContainer()
        let thread = ConversationSidebarThread(
            id: "thread-1",
            title: "Theme safety",
            lastActivityAt: Date(timeIntervalSince1970: 1000)
        )
        container.sidebarThreads = [thread]

        container.settings.theme = .light
        container.settings.selectedModelID = "theme-safety-model"
        container.flushSettings()

        #expect(container.sidebarThreads == [thread])
    }
}
