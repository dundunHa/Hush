import Foundation

public enum ChatRole: String, Codable, CaseIterable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let role: ChatRole
    public let content: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

