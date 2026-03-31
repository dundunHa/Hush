import Foundation

public struct QuickBarSessionState: Equatable, Sendable {
    public var conversationId: String?
    public var isPersistedConversation: Bool
    public var messages: [ChatMessage]
    public var draft: String
    public var isExpanded: Bool
    public var providerID: String
    public var selectedModelID: String
    public var generation: UInt64

    public init(
        conversationId: String? = nil,
        isPersistedConversation: Bool = false,
        messages: [ChatMessage] = [],
        draft: String = "",
        isExpanded: Bool = false,
        providerID: String = "",
        selectedModelID: String = "",
        generation: UInt64 = 0
    ) {
        self.conversationId = conversationId
        self.isPersistedConversation = isPersistedConversation
        self.messages = messages
        self.draft = draft
        self.isExpanded = isExpanded
        self.providerID = providerID
        self.selectedModelID = selectedModelID
        self.generation = generation
    }

    public static let empty = QuickBarSessionState()
}
