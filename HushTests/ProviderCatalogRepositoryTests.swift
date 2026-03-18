import Foundation
import GRDB
@testable import Hush
import Testing

// MARK: - Provider Catalog Repository Tests

struct ProviderCatalogRepositoryTests {
    private func makeRepo() throws -> (GRDBProviderCatalogRepository, DatabaseManager) {
        let db = try DatabaseManager.inMemory()
        let repo = GRDBProviderCatalogRepository(dbManager: db)
        return (repo, db)
    }

    // MARK: - Deterministic Ordering

    @Test("Models are returned in deterministic order by displayName then modelID")
    func deterministicOrdering() throws {
        let (repo, _) = try makeRepo()

        let models = [
            ModelDescriptor(id: "z-model", displayName: "Zulu Model", capabilities: [.text]),
            ModelDescriptor(id: "a-model", displayName: "Alpha Model", capabilities: [.text]),
            ModelDescriptor(id: "m-model", displayName: "Mike Model", capabilities: [.text])
        ]

        try repo.upsertCatalog(providerID: "openai", models: models)
        let fetched = try repo.models(forProviderID: "openai")

        #expect(fetched.count == 3)
        #expect(fetched[0].id == "a-model")
        #expect(fetched[1].id == "m-model")
        #expect(fetched[2].id == "z-model")
    }

    // MARK: - Provider Scoping

    @Test("Models are scoped by provider ID")
    func providerScoping() throws {
        let (repo, _) = try makeRepo()

        let openaiModels = [
            ModelDescriptor(id: "gpt-4", displayName: "GPT-4", capabilities: [.text])
        ]
        let anthropicModels = [
            ModelDescriptor(id: "claude-3", displayName: "Claude 3", capabilities: [.text])
        ]

        try repo.upsertCatalog(providerID: "openai", models: openaiModels)
        try repo.upsertCatalog(providerID: "anthropic", models: anthropicModels)

        let openai = try repo.models(forProviderID: "openai")
        let anthropic = try repo.models(forProviderID: "anthropic")

        #expect(openai.count == 1)
        #expect(openai[0].id == "gpt-4")
        #expect(anthropic.count == 1)
        #expect(anthropic[0].id == "claude-3")
    }

    @Test("Query for nonexistent provider returns empty array")
    func emptyProviderReturnsEmpty() throws {
        let (repo, _) = try makeRepo()

        let models = try repo.models(forProviderID: "nonexistent")
        #expect(models.isEmpty)
    }

    // MARK: - Upsert Behavior

    @Test("Upsert replaces entire catalog for a provider")
    func upsertReplacesEntireCatalog() throws {
        let (repo, _) = try makeRepo()

        let initial = [
            ModelDescriptor(id: "model-a", displayName: "Model A", capabilities: [.text]),
            ModelDescriptor(id: "model-b", displayName: "Model B", capabilities: [.text])
        ]
        try repo.upsertCatalog(providerID: "openai", models: initial)

        let replacement = [
            ModelDescriptor(id: "model-c", displayName: "Model C", capabilities: [.text])
        ]
        try repo.upsertCatalog(providerID: "openai", models: replacement)

        let fetched = try repo.models(forProviderID: "openai")
        #expect(fetched.count == 1)
        #expect(fetched[0].id == "model-c")
    }

    @Test("Upsert for one provider does not affect other providers")
    func upsertDoesNotAffectOtherProviders() throws {
        let (repo, _) = try makeRepo()

        try repo.upsertCatalog(
            providerID: "openai",
            models: [ModelDescriptor(id: "gpt-4", displayName: "GPT-4", capabilities: [.text])]
        )
        try repo.upsertCatalog(
            providerID: "anthropic",
            models: [ModelDescriptor(id: "claude", displayName: "Claude", capabilities: [.text])]
        )

        // Replace only anthropic
        try repo.upsertCatalog(
            providerID: "anthropic",
            models: [ModelDescriptor(id: "claude-new", displayName: "Claude New", capabilities: [.text])]
        )

        let openai = try repo.models(forProviderID: "openai")
        #expect(openai.count == 1)
        #expect(openai[0].id == "gpt-4")
    }

    // MARK: - Restart Persistence

    @Test("Catalog survives database close and reopen")
    func catalogSurvivesRestart() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let path = tmpDir.appendingPathComponent("test.sqlite").path

        // Write catalog
        let db1 = try DatabaseManager(path: path)
        let repo1 = GRDBProviderCatalogRepository(dbManager: db1)
        try repo1.upsertCatalog(
            providerID: "openai",
            models: [ModelDescriptor(id: "gpt-4", displayName: "GPT-4", capabilities: [.text])]
        )

        // Reopen database
        let db2 = try DatabaseManager(path: path)
        let repo2 = GRDBProviderCatalogRepository(dbManager: db2)
        let fetched = try repo2.models(forProviderID: "openai")

        #expect(fetched.count == 1)
        #expect(fetched[0].id == "gpt-4")
    }

    // MARK: - Refresh Status

    @Test("Successful refresh records lastSuccessAt and clears error")
    func successfulRefreshRecordsStatus() throws {
        let (repo, _) = try makeRepo()

        try repo.upsertCatalog(
            providerID: "openai",
            models: [ModelDescriptor(id: "gpt-4", displayName: "GPT-4", capabilities: [.text])]
        )

        let status = try repo.refreshStatus(forProviderID: "openai")
        #expect(status.lastSuccessAt != nil)
        #expect(status.lastError == nil)
        #expect(status.modelCount == 1)
        #expect(status.hasUsableCache == true)
    }

    @Test("Failed refresh preserves existing catalog and records error")
    func failedRefreshPreservesExistingCatalog() throws {
        let (repo, _) = try makeRepo()

        // First successful refresh
        try repo.upsertCatalog(
            providerID: "openai",
            models: [ModelDescriptor(id: "gpt-4", displayName: "GPT-4", capabilities: [.text])]
        )

        // Then a failure
        try repo.recordRefreshFailure(providerID: "openai", error: "Network timeout")

        // Models still available
        let models = try repo.models(forProviderID: "openai")
        #expect(models.count == 1)

        // Status reflects error
        let status = try repo.refreshStatus(forProviderID: "openai")
        #expect(status.lastError == "Network timeout")
        #expect(status.modelCount == 1)
    }

    @Test("Refresh status for unknown provider returns empty defaults")
    func refreshStatusUnknownProvider() throws {
        let (repo, _) = try makeRepo()

        let status = try repo.refreshStatus(forProviderID: "nonexistent")
        #expect(status.lastSuccessAt == nil)
        #expect(status.lastError == nil)
        #expect(status.modelCount == 0)
        #expect(status.hasUsableCache == false)
    }

    // MARK: - Remove Catalog

    @Test("Remove catalog deletes all data for provider")
    func removeCatalogDeletesAll() throws {
        let (repo, _) = try makeRepo()

        try repo.upsertCatalog(
            providerID: "openai",
            models: [ModelDescriptor(id: "gpt-4", displayName: "GPT-4", capabilities: [.text])]
        )

        try repo.removeCatalog(forProviderID: "openai")

        let models = try repo.models(forProviderID: "openai")
        #expect(models.isEmpty)

        let status = try repo.refreshStatus(forProviderID: "openai")
        #expect(status.hasUsableCache == false)
    }

    // MARK: - Normalized Metadata Round-Trip

    @Test("Normalized metadata survives persist and read round-trip")
    func normalizedMetadataRoundTrip() throws {
        let (repo, _) = try makeRepo()

        let model = ModelDescriptor(
            id: "gpt-4-turbo",
            displayName: "GPT-4 Turbo",
            capabilities: [.text, .image],
            modelType: .chat,
            supportedInputs: [.text, .image],
            supportedOutputs: [.text],
            limits: ModelLimits(
                contextWindow: 128_000,
                maxOutputTokens: 4096,
                supportsTools: true,
                supportsStreaming: true
            ),
            rawMetadataJSON: "{\"owned_by\":\"openai\"}"
        )

        try repo.upsertCatalog(providerID: "openai", models: [model])
        let fetched = try repo.models(forProviderID: "openai")

        #expect(fetched.count == 1)
        let result = fetched[0]
        #expect(result.id == "gpt-4-turbo")
        #expect(result.displayName == "GPT-4 Turbo")
        #expect(result.modelType == .chat)
        #expect(result.supportedInputs == [.text, .image])
        #expect(result.supportedOutputs == [.text])
        #expect(result.limits?.contextWindow == 128_000)
        #expect(result.limits?.maxOutputTokens == 4096)
        #expect(result.limits?.supportsTools == true)
        #expect(result.limits?.supportsStreaming == true)
        #expect(result.rawMetadataJSON == "{\"owned_by\":\"openai\"}")
    }

    // MARK: - Migration Schema

    @Test("Provider catalog tables have expected columns")
    func catalogTablesSchema() throws {
        let db = try DatabaseManager.inMemory()

        let snapshotColumns = try db.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(providerCatalogSnapshots)")
        }
        let snapshotNames = snapshotColumns.map { $0["name"] as String }
        #expect(snapshotNames.contains("providerID"))
        #expect(snapshotNames.contains("fetchedAt"))
        #expect(snapshotNames.contains("status"))
        #expect(snapshotNames.contains("lastError"))

        let modelColumns = try db.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_info(providerCatalogModels)")
        }
        let modelNames = modelColumns.map { $0["name"] as String }
        #expect(modelNames.contains("providerID"))
        #expect(modelNames.contains("modelID"))
        #expect(modelNames.contains("displayName"))
        #expect(modelNames.contains("modelType"))
        #expect(modelNames.contains("supportedInputs"))
        #expect(modelNames.contains("supportedOutputs"))
        #expect(modelNames.contains("limitsJSON"))
        #expect(modelNames.contains("rawMetadataJSON"))
        #expect(modelNames.contains("updatedAt"))
    }
}
