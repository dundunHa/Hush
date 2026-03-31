import Foundation

enum SendDraftDestination {
    case activeConversation
    case quickBar
}

extension AppContainer {
    @discardableResult
    func sendDraft(_ text: String) -> Bool {
        sendDraft(text, destination: .activeConversation)
    }

    @discardableResult
    func sendDraft(_ text: String, destination: SendDraftDestination) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if requestCoordinator.isQueueFull {
            statusMessage = "Queue full – request rejected (max \(RuntimeConstants.pendingQueueCapacity))"
            return false
        }

        guard let route = resolveSendRoute(for: destination) else {
            return false
        }

        let userMessage = ChatMessage(role: .user, content: trimmed)
        appendMessage(userMessage, toConversation: route.conversationId)

        switch destination {
        case .activeConversation:
            updateSidebarThreadsAfterUserMessage(
                userMessage,
                conversationId: route.conversationId
            )
            cacheCurrentConversationSnapshotIfNeeded()
        case .quickBar:
            updateSidebarThreadsAfterUserMessage(
                userMessage,
                conversationId: route.conversationId
            )
            mutateQuickBarState { state in
                state.isExpanded = true
            }
        }

        if route.persistenceBehavior == .persistent, !route.conversationId.isEmpty {
            try? persistence?.persistUserMessage(userMessage, conversationId: route.conversationId)
        }

        let snapshot = QueueItemSnapshot(
            prompt: trimmed,
            providerID: route.providerID,
            modelID: route.modelID,
            parameters: settings.parameters,
            userMessageID: userMessage.id,
            conversationId: route.conversationId,
            persistenceBehavior: route.persistenceBehavior
        )

        requestCoordinator.submitRequest(snapshot)
        return true
    }

    func updateSidebarThreadsAfterUserMessage(
        _ message: ChatMessage,
        conversationId: String
    ) {
        let derivedTitle = ConversationSidebarTitleFormatter.topicTitle(from: message.content)
        let resolvedTitle: String
        if let existing = sidebarThreads.first(where: { $0.id == conversationId }),
           existing.title != ConversationSidebarTitleFormatter.placeholderTitle
        {
            resolvedTitle = existing.title
        } else {
            resolvedTitle = derivedTitle
        }

        upsertSidebarThread(
            conversationId: conversationId,
            title: resolvedTitle,
            lastActivityAt: message.createdAt
        )
    }

    func upsertSidebarThread(
        conversationId: String,
        title: String,
        lastActivityAt: Date
    ) {
        if let existingIndex = sidebarThreads.firstIndex(where: { $0.id == conversationId }) {
            sidebarThreads.remove(at: existingIndex)
            sidebarThreads.insert(
                ConversationSidebarThread(
                    id: conversationId,
                    title: title,
                    lastActivityAt: lastActivityAt
                ),
                at: 0
            )
        } else {
            sidebarThreads.insert(
                ConversationSidebarThread(
                    id: conversationId,
                    title: title,
                    lastActivityAt: lastActivityAt
                ),
                at: 0
            )
        }
    }

    @discardableResult
    func quickBarSubmit(_ text: String? = nil) -> Bool {
        let draft = text ?? quickBarState.draft
        let didSend = sendDraft(draft, destination: .quickBar)
        if didSend {
            mutateQuickBarState { state in
                state.draft = ""
                state.isExpanded = true
            }
        }
        return didSend
    }

    struct SendRoute {
        let conversationId: String
        let providerID: String
        let modelID: String
        let persistenceBehavior: ConversationPersistenceBehavior
    }

    func resolveSendRoute(for destination: SendDraftDestination) -> SendRoute? {
        switch destination {
        case .activeConversation:
            guard let conversationId = activeConversationId else {
                statusMessage = "No active conversation available"
                return nil
            }
            let providerID = settings.selectedProviderID.trimmingCharacters(in: .whitespacesAndNewlines)
            let modelID = settings.selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !providerID.isEmpty, !modelID.isEmpty else {
                statusMessage = "Choose a provider and model before sending"
                return nil
            }
            return SendRoute(
                conversationId: conversationId,
                providerID: providerID,
                modelID: modelID,
                persistenceBehavior: .persistent
            )
        case .quickBar:
            guard hasConfiguredProvider else {
                statusMessage = "Add a provider to start chatting"
                return nil
            }

            prepareQuickBarSessionIfNeeded()
            let defaults = resolveQuickBarDefaults()
            guard let conversationId = ensureQuickBarConversationId() else {
                statusMessage = "Quick Bar is not ready yet"
                return nil
            }
            guard !defaults.providerID.isEmpty, !defaults.modelID.isEmpty else {
                statusMessage = "Choose a model before sending"
                return nil
            }

            mutateQuickBarState { state in
                state.providerID = defaults.providerID
                state.selectedModelID = defaults.modelID
                state.isExpanded = true
            }

            return SendRoute(
                conversationId: conversationId,
                providerID: defaults.providerID,
                modelID: defaults.modelID,
                persistenceBehavior: .persistent
            )
        }
    }

    func prepareQuickBarSessionIfNeeded(forceReset: Bool = false) {
        let defaults = resolveQuickBarDefaults()

        if forceReset || quickBarState.conversationId == nil {
            let preservedDraft = forceReset ? "" : quickBarState.draft
            quickBarGeneration &+= 1
            quickBarState = QuickBarSessionState(
                conversationId: nil,
                messages: [],
                draft: preservedDraft,
                isExpanded: false,
                providerID: defaults.providerID,
                selectedModelID: defaults.modelID,
                generation: quickBarGeneration
            )
            return
        }

        mutateQuickBarState { state in
            if state.providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.providerID = defaults.providerID
            }
            if state.selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.selectedModelID = defaults.modelID
            }
        }
    }

    func ensureQuickBarConversationId() -> String? {
        if let conversationId = quickBarState.conversationId {
            return conversationId
        }

        let conversationId: String
        if let persistence, let createdConversationId = try? persistence.createNewConversation() {
            conversationId = createdConversationId
        } else {
            conversationId = UUID().uuidString
        }

        quickBarGeneration &+= 1
        mutateQuickBarState { state in
            state.conversationId = conversationId
            state.generation = quickBarGeneration
        }
        if messagesByConversationId[conversationId] == nil {
            messagesByConversationId[conversationId] = quickBarState.messages
        }
        return conversationId
    }

    func resolveQuickBarDefaults() -> (providerID: String, modelID: String) {
        let currentQuickBarProviderID = quickBarState.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedProviderID = settings.selectedProviderID.trimmingCharacters(in: .whitespacesAndNewlines)

        let provider = settings.providerConfigurations.first(where: {
            $0.id == currentQuickBarProviderID && $0.isEnabled
        }) ?? settings.providerConfigurations.first(where: {
            $0.id == selectedProviderID && $0.isEnabled
        }) ?? fallbackProviderConfiguration()

        let providerID = provider?.id ?? currentQuickBarProviderID
        let quickBarModelID = quickBarState.selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedModelID = settings.selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultModelID = provider?.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let modelID = [quickBarModelID, selectedModelID, defaultModelID].first(where: { !$0.isEmpty }) ?? ""

        return (providerID, modelID)
    }

    func stopActiveRequest() {
        guard let conversationId = activeConversationId else { return }
        requestCoordinator.stopConversation(conversationId)
    }

    func stopQuickBarRequest() {
        guard let conversationId = quickBarState.conversationId else { return }
        requestCoordinator.stopConversation(conversationId)
    }
}
