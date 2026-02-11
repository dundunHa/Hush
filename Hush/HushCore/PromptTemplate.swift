import Foundation

public struct PromptTemplate: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var content: String
    public var category: String
    public var createdAt: Date
    public var updatedAt: Date

    // MARK: - Init

    public init(
        id: String = UUID().uuidString,
        name: String,
        content: String = "",
        category: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.category = category
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
