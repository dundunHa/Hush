import Foundation
import GRDB
@testable import Hush
import Testing

struct AppPreferencesRepositoryTests {
    private func makeRepo() throws -> GRDBAppPreferencesRepository {
        let dbManager = try DatabaseManager.inMemory()
        return GRDBAppPreferencesRepository(dbManager: dbManager)
    }

    @Test("fetch returns nil when no preferences exist")
    func fetchReturnsNilWhenEmpty() throws {
        let repo = try makeRepo()
        let result = try repo.fetch()
        #expect(result == nil)
    }

    @Test("save then fetch round-trips AppSettings")
    func saveLoadRoundTrip() throws {
        let repo = try makeRepo()

        let original = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "openai",
            selectedModelID: "gpt-4o-mini",
            parameters: .standard,
            quickBar: .standard,
            theme: .readPaper,
            fontSettings: AppFontSettings(
                familyName: "Helvetica Neue",
                size: 16
            )
        )

        try repo.save(original)
        let loaded = try repo.fetch()

        #expect(loaded != nil)
        let prefs = try #require(loaded?.toAppPreferences())
        #expect(prefs.selectedProviderID == "openai")
        #expect(prefs.selectedModelID == "gpt-4o-mini")
        #expect(prefs.parameters == .standard)
        #expect(prefs.quickBar == .standard)
        #expect(prefs.theme == .readPaper)
        #expect(prefs.fontSettings.normalizedFamilyName == "Helvetica Neue")
        #expect(prefs.fontSettings.normalizedSize == 16)
    }

    @Test("save overwrites previous preferences")
    func saveOverwritesPrevious() throws {
        let repo = try makeRepo()

        let first = AppSettings.default
        try repo.save(first)

        var second = first
        second.selectedModelID = "new-model"
        try repo.save(second)

        let loaded = try repo.fetch()
        #expect(loaded?.selectedModelID == "new-model")
    }

    @Test("model parameters round-trip correctly")
    func modelParametersRoundTrip() throws {
        let repo = try makeRepo()

        var settings = AppSettings.default
        settings.parameters = ModelParameters(
            temperature: 0.9,
            topP: 0.8,
            maxTokens: 2048,
            presencePenalty: 0.5,
            frequencyPenalty: 0.3,
            reasoningEffort: .high
        )

        try repo.save(settings)
        let loaded = try repo.fetch()
        let prefs = try #require(loaded?.toAppPreferences())

        #expect(prefs.parameters.temperature == 0.9)
        #expect(prefs.parameters.topP == 0.8)
        #expect(prefs.parameters.maxTokens == 2048)
        #expect(prefs.parameters.presencePenalty == 0.5)
        #expect(prefs.parameters.frequencyPenalty == 0.3)
        #expect(prefs.parameters.reasoningEffort == .high)
    }

    @Test("quickBar configuration round-trips correctly")
    func quickBarRoundTrip() throws {
        let repo = try makeRepo()

        var settings = AppSettings.default
        settings.quickBar = QuickBarConfiguration(
            key: "L",
            modifiers: ["command", "shift"]
        )

        try repo.save(settings)
        let loaded = try repo.fetch()
        let prefs = try #require(loaded?.toAppPreferences())

        #expect(prefs.quickBar.key == "L")
        #expect(prefs.quickBar.modifiers == ["command", "shift"])
    }

    @Test("Non-default maxConcurrentRequests round-trips correctly")
    func maxConcurrentRequestsRoundTrip() throws {
        let repo = try makeRepo()

        var settings = AppSettings.default
        settings.maxConcurrentRequests = 5

        try repo.save(settings)
        let loaded = try repo.fetch()
        let prefs = try #require(loaded?.toAppPreferences())

        #expect(prefs.maxConcurrentRequests == 5)
    }

    @Test("Missing maxConcurrentRequests defaults to RuntimeConstants value")
    func maxConcurrentRequestsMissingDefaultsCorrectly() throws {
        let dbManager = try DatabaseManager.inMemory()
        let repo = GRDBAppPreferencesRepository(dbManager: dbManager)

        let settings = AppSettings.default
        try repo.save(settings)

        try dbManager.write { db in
            try db.execute(
                sql: "UPDATE appPreferences SET maxConcurrentRequests = NULL WHERE id = 'default'"
            )
        }

        let loaded = try repo.fetch()
        let prefs = try #require(loaded?.toAppPreferences())
        #expect(prefs.maxConcurrentRequests == RuntimeConstants.defaultMaxConcurrentRequests)
    }

    @Test("Missing font settings default to shared typography defaults")
    func fontSettingsMissingDefaultsCorrectly() throws {
        let dbManager = try DatabaseManager.inMemory()
        let repo = GRDBAppPreferencesRepository(dbManager: dbManager)

        try repo.save(.default)

        try dbManager.write { db in
            try db.execute(
                sql: """
                UPDATE appPreferences
                SET fontFamilyName = NULL,
                    fontSize = NULL
                WHERE id = 'default'
                """
            )
        }

        let loaded = try repo.fetch()
        let prefs = try #require(loaded?.toAppPreferences())
        #expect(prefs.fontSettings.normalizedFamilyName == nil)
        #expect(prefs.fontSettings.normalizedSize == AppFontSettings.defaultSize)
    }
}
