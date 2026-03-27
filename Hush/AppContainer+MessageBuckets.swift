import Foundation

// MARK: - Message Bucket Interface

extension AppContainer {
    func registerHotScenePool(_ pool: HotScenePool?) {
        hotScenePool = pool
    }

    func messagesForConversation(_ conversationId: String) -> [ChatMessage] {
        if conversationId == activeConversationId {
            return messages
        }
        return messagesByConversationId[conversationId] ?? []
    }

    func appendMessage(_ message: ChatMessage, toConversation conversationId: String) {
        if conversationId == activeConversationId {
            messages.append(message)
        }
        messagesByConversationId[conversationId, default: []].append(message)
        syncQuickBarMessagesIfNeeded(conversationId: conversationId)
        hotScenePool?.markNeedsReload(conversationID: conversationId)
    }

    func updateMessage(at index: Int, inConversation conversationId: String, content: String) {
        if conversationId == activeConversationId, index < messages.count {
            let existing = messages[index]
            messages[index] = existing.updatingContent(content)
        }
        if var bucket = messagesByConversationId[conversationId], index < bucket.count {
            let existing = bucket[index]
            bucket[index] = existing.updatingContent(content)
            messagesByConversationId[conversationId] = bucket
        }
        syncQuickBarMessagesIfNeeded(conversationId: conversationId)
        hotScenePool?.markNeedsReload(conversationID: conversationId)
    }

    func updateMessagesDebugInfo(
        _ messageIDs: [UUID],
        inConversation conversationId: String,
        debugInfoJSON: String?
    ) {
        guard !messageIDs.isEmpty else { return }
        let messageIDSet = Set(messageIDs)

        if conversationId == activeConversationId {
            messages = messages.map { message in
                guard messageIDSet.contains(message.id) else { return message }
                return message.updatingDebugInfo(debugInfoJSON)
            }
        }

        if let bucket = messagesByConversationId[conversationId] {
            messagesByConversationId[conversationId] = bucket.map { message in
                guard messageIDSet.contains(message.id) else { return message }
                return message.updatingDebugInfo(debugInfoJSON)
            }
        }

        syncQuickBarMessagesIfNeeded(conversationId: conversationId)
        hotScenePool?.markNeedsReload(conversationID: conversationId)
    }

    func resolveURL(for attachment: MessageAttachment) -> URL? {
        messageAssetStore?.url(forRelativePath: attachment.localRelativePath)
    }

    func pushStreamingContent(conversationId: String, messageID: UUID, content: String) {
        guard conversationId == activeConversationId else { return }
        guard let scene = hotScenePool?.sceneFor(conversationID: conversationId) else { return }
        scene.pushStreamingContent(messageID: messageID, content: content)
    }

    func markUnreadCompletion(forConversation conversationId: String) {
        guard conversationId != activeConversationId else { return }
        unreadCompletions.insert(conversationId)
    }

    func clearUnreadCompletion(forConversation conversationId: String) {
        unreadCompletions.remove(conversationId)
    }

    func clearActiveConversationUnreadIfAtTail() {
        guard let conversationId = activeConversationId else { return }
        clearUnreadCompletion(forConversation: conversationId)
    }

    func syncPublishedSchedulerState() {
        guard let coordinator = requestCoordinator else { return }
        runningConversationIds = coordinator.conversationsWithRunning()
        queuedConversationCounts = coordinator.conversationsWithQueued()
    }

    func mutateQuickBarState(_ mutate: (inout QuickBarSessionState) -> Void) {
        var nextState = quickBarState
        mutate(&nextState)
        quickBarState = nextState
    }

    func syncQuickBarMessagesIfNeeded(conversationId: String) {
        guard quickBarState.conversationId == conversationId else { return }
        let messages = messagesByConversationId[conversationId] ?? []
        mutateQuickBarState { state in
            state.messages = messages
            if !messages.isEmpty {
                state.isExpanded = true
            }
        }
    }
}
