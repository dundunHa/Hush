import Foundation
import GRDB

// MARK: - Prompt Template Record

public nonisolated struct PromptTemplateRecord: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var content: String
    public var category: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
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

nonisolated extension PromptTemplateRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "promptTemplates"
}

// MARK: - Domain Conversion

public extension PromptTemplateRecord {
    func toPromptTemplate() -> PromptTemplate {
        PromptTemplate(
            id: id,
            name: name,
            content: content,
            category: category,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func from(
        _ template: PromptTemplate,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) -> PromptTemplateRecord {
        PromptTemplateRecord(
            id: template.id,
            name: template.name,
            content: template.content,
            category: template.category,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
