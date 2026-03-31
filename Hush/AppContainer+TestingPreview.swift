import Foundation

#if DEBUG
    extension AppContainer {
        func configureQuickBarPreview(
            conversationId: String = "quickbar-preview",
            messages: [ChatMessage] = [],
            draft: String = "",
            isExpanded: Bool,
            isSending: Bool = false,
            showQuickBar: Bool = true,
            providerID: String = "mock",
            modelID: String = "mock-text-1"
        ) {
            quickBarGeneration &+= 1

            let resolvedConversationId: String? = if messages.isEmpty, !isSending {
                nil
            } else {
                conversationId
            }

            quickBarState = QuickBarSessionState(
                conversationId: resolvedConversationId,
                messages: messages,
                draft: draft,
                isExpanded: isExpanded,
                providerID: providerID,
                selectedModelID: modelID,
                generation: quickBarGeneration
            )

            if let resolvedConversationId {
                messagesByConversationId[resolvedConversationId] = messages
            }

            runningConversationIds = if isSending, let resolvedConversationId {
                [resolvedConversationId]
            } else {
                []
            }
            self.showQuickBar = showQuickBar
            statusMessage = "Ready"
        }

        func setRunningConversationIDsForTesting(_ ids: Set<String>) {
            runningConversationIds = ids
        }

        func requestCoordinatorFlushStateCountForTesting() -> Int {
            requestCoordinator.flushStateCountForTesting()
        }
    }
#endif
