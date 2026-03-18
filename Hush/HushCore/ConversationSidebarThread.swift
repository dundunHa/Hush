import Foundation

nonisolated struct ConversationSidebarThread: Identifiable, Equatable {
    let id: String
    let title: String
    let lastActivityAt: Date
}

nonisolated enum ConversationSidebarTitleFormatter {
    static let placeholderTitle = "New thread"

    static func makeTitle(conversationTitle: String?, firstUserContent: String?) -> String {
        let trimmedConversationTitle = (conversationTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedConversationTitle.isEmpty {
            return trimmedConversationTitle
        }

        let trimmedUserContent = (firstUserContent ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedUserContent.isEmpty {
            return topicTitle(from: trimmedUserContent)
        }

        return placeholderTitle
    }

    static func topicTitle(from content: String) -> String {
        let firstNonEmptyLine = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Untitled"

        let maxLength = 44
        if firstNonEmptyLine.count <= maxLength {
            return firstNonEmptyLine
        }
        return String(firstNonEmptyLine.prefix(maxLength)) + "…"
    }
}
