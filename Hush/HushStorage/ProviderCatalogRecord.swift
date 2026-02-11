import Foundation
import GRDB

// MARK: - Catalog Snapshot Record

/// GRDB-backed record for the `providerCatalogSnapshots` table.
/// Tracks refresh state per provider: last success time and last error.
public nonisolated struct ProviderCatalogSnapshotRecord: Codable, Sendable, Equatable {
    public var providerID: String
    public var fetchedAt: Date?
    public var status: String
    public var lastError: String?

    public init(
        providerID: String,
        fetchedAt: Date? = nil,
        status: String = "empty",
        lastError: String? = nil
    ) {
        self.providerID = providerID
        self.fetchedAt = fetchedAt
        self.status = status
        self.lastError = lastError
    }
}

nonisolated extension ProviderCatalogSnapshotRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "providerCatalogSnapshots"
}

// MARK: - Snapshot Status

public enum CatalogSnapshotStatus: String, Codable, Sendable {
    case empty
    case success
    case error
}

// MARK: - Catalog Model Record

/// GRDB-backed record for the `providerCatalogModels` table.
/// Stores normalized model metadata scoped by provider ID.
public nonisolated struct ProviderCatalogModelRecord: Codable, Sendable, Equatable {
    public var providerID: String
    public var modelID: String
    public var displayName: String
    public var modelType: String
    public var supportedInputs: String // JSON-encoded [Modality]
    public var supportedOutputs: String // JSON-encoded [Modality]
    public var limitsJSON: String?
    public var rawMetadataJSON: String?
    public var updatedAt: Date

    public init(
        providerID: String,
        modelID: String,
        displayName: String,
        modelType: String = "unknown",
        supportedInputs: String = "[\"text\"]",
        supportedOutputs: String = "[\"text\"]",
        limitsJSON: String? = nil,
        rawMetadataJSON: String? = nil,
        updatedAt: Date = .now
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.displayName = displayName
        self.modelType = modelType
        self.supportedInputs = supportedInputs
        self.supportedOutputs = supportedOutputs
        self.limitsJSON = limitsJSON
        self.rawMetadataJSON = rawMetadataJSON
        self.updatedAt = updatedAt
    }
}

nonisolated extension ProviderCatalogModelRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "providerCatalogModels"
}

// MARK: - Domain Conversion

public extension ProviderCatalogModelRecord {
    /// Converts this GRDB record into a domain `ModelDescriptor`.
    func toModelDescriptor() -> ModelDescriptor {
        let decoder = JSONDecoder()

        let parsedInputs: [Modality] = (try? decoder.decode(
            [Modality].self,
            from: Data(supportedInputs.utf8)
        )) ?? [.text]

        let parsedOutputs: [Modality] = (try? decoder.decode(
            [Modality].self,
            from: Data(supportedOutputs.utf8)
        )) ?? [.text]

        let parsedLimits: ModelLimits? = limitsJSON.flatMap { json in
            try? decoder.decode(ModelLimits.self, from: Data(json.utf8))
        }

        let parsedModelType = ModelType(rawValue: modelType) ?? .unknown

        // Map normalized metadata back to legacy capabilities
        var legacyCapabilities: [ModelCapability] = []
        if parsedInputs.contains(.text) || parsedOutputs.contains(.text) {
            legacyCapabilities.append(.text)
        }
        if parsedInputs.contains(.image) || parsedOutputs.contains(.image) {
            legacyCapabilities.append(.image)
        }

        return ModelDescriptor(
            id: modelID,
            displayName: displayName,
            capabilities: legacyCapabilities,
            modelType: parsedModelType,
            supportedInputs: parsedInputs,
            supportedOutputs: parsedOutputs,
            limits: parsedLimits,
            rawMetadataJSON: rawMetadataJSON
        )
    }

    /// Creates a GRDB record from a domain `ModelDescriptor` scoped to a provider.
    static func from(
        descriptor: ModelDescriptor,
        providerID: String,
        updatedAt: Date = .now
    ) -> ProviderCatalogModelRecord {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let inputsJSON = (try? String(data: encoder.encode(descriptor.supportedInputs), encoding: .utf8)) ?? "[\"text\"]"
        let outputsJSON = (try? String(data: encoder.encode(descriptor.supportedOutputs), encoding: .utf8)) ?? "[\"text\"]"
        let limitsJSON = descriptor.limits.flatMap { limits in
            try? String(data: encoder.encode(limits), encoding: .utf8)
        }

        return ProviderCatalogModelRecord(
            providerID: providerID,
            modelID: descriptor.id,
            displayName: descriptor.displayName,
            modelType: descriptor.modelType.rawValue,
            supportedInputs: inputsJSON,
            supportedOutputs: outputsJSON,
            limitsJSON: limitsJSON,
            rawMetadataJSON: descriptor.rawMetadataJSON,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Refresh Status (read-only projection)

/// Lightweight refresh status for UI presentation.
public struct ProviderCatalogRefreshStatus: Sendable, Equatable {
    public let providerID: String
    public let lastSuccessAt: Date?
    public let lastError: String?
    public let modelCount: Int

    public var hasUsableCache: Bool {
        lastSuccessAt != nil && modelCount > 0
    }
}
