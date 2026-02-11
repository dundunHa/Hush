import Foundation

// MARK: - Legacy Capability (kept for backward compatibility)

public enum ModelCapability: String, Codable, CaseIterable, Sendable {
    case text
    case image
}

// MARK: - Normalized Model Metadata

/// Normalized model type that classifies a model's primary function.
/// Providers map their specific model categories to these values.
public enum ModelType: String, Codable, CaseIterable, Sendable {
    case chat
    case embedding
    case image
    case audio
    case reasoning
    case unknown
}

/// A supported input or output modality for a model.
public enum Modality: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case audio
    case video
}

/// Optional limits and feature flags for a model.
/// All fields are optional; unknown values are safe-defaulted to `nil`.
public struct ModelLimits: Codable, Equatable, Sendable {
    public var contextWindow: Int?
    public var maxOutputTokens: Int?
    public var supportsTools: Bool?
    public var supportsStreaming: Bool?

    public init(
        contextWindow: Int? = nil,
        maxOutputTokens: Int? = nil,
        supportsTools: Bool? = nil,
        supportsStreaming: Bool? = nil
    ) {
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.supportsTools = supportsTools
        self.supportsStreaming = supportsStreaming
    }

    public static let unknown = ModelLimits()
}

// MARK: - Model Descriptor

public struct ModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var capabilities: [ModelCapability]

    // Normalized metadata
    public var modelType: ModelType
    public var supportedInputs: [Modality]
    public var supportedOutputs: [Modality]
    public var limits: ModelLimits?

    /// Opaque JSON payload preserving provider-specific fields for
    /// debugging and forward compatibility. Not required for core UI/validation.
    public var rawMetadataJSON: String?

    public init(
        id: String,
        displayName: String,
        capabilities: [ModelCapability],
        modelType: ModelType = .unknown,
        supportedInputs: [Modality] = [.text],
        supportedOutputs: [Modality] = [.text],
        limits: ModelLimits? = nil,
        rawMetadataJSON: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
        self.modelType = modelType
        self.supportedInputs = supportedInputs
        self.supportedOutputs = supportedOutputs
        self.limits = limits
        self.rawMetadataJSON = rawMetadataJSON
    }
}

// MARK: - Backward-Compatible Decoding

extension ModelDescriptor {
    enum CodingKeys: String, CodingKey {
        case id, displayName, capabilities
        case modelType, supportedInputs, supportedOutputs
        case limits, rawMetadataJSON
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        capabilities = try container.decodeIfPresent([ModelCapability].self, forKey: .capabilities) ?? [.text]
        modelType = try container.decodeIfPresent(ModelType.self, forKey: .modelType) ?? .unknown
        supportedInputs = try container.decodeIfPresent([Modality].self, forKey: .supportedInputs) ?? [.text]
        supportedOutputs = try container.decodeIfPresent([Modality].self, forKey: .supportedOutputs) ?? [.text]
        limits = try container.decodeIfPresent(ModelLimits.self, forKey: .limits)
        rawMetadataJSON = try container.decodeIfPresent(String.self, forKey: .rawMetadataJSON)
    }
}
