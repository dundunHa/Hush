import Foundation

public enum ModelCapability: String, Codable, CaseIterable, Sendable {
    case text
    case image
}

public struct ModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var capabilities: [ModelCapability]

    public init(
        id: String,
        displayName: String,
        capabilities: [ModelCapability]
    ) {
        self.id = id
        self.displayName = displayName
        self.capabilities = capabilities
    }
}

