import Foundation

extension AppContainer {
    // MARK: - Quick Bar Actions

    func toggleQuickBar() {
        if showQuickBar {
            showQuickBar = false
        } else {
            prepareQuickBarSessionIfNeeded()
            showQuickBar = true
        }
    }

    func closeQuickBar() {
        showQuickBar = false
    }

    func updateQuickBarDraft(_ draft: String) {
        mutateQuickBarState { state in
            state.draft = draft
        }
    }

    func selectQuickBarModel(id: String) {
        prepareQuickBarSessionIfNeeded()
        mutateQuickBarState { state in
            state.selectedModelID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func selectQuickBarProvider(id: String) {
        prepareQuickBarSessionIfNeeded()
        guard let config = settings.providerConfigurations.first(where: {
            $0.id == id && $0.isEnabled
        }) else {
            return
        }

        let defaultModelID = config.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateQuickBarState { state in
            state.providerID = id
            state.selectedModelID = defaultModelID
        }
    }

    func resetQuickBarConversation() {
        guard !isQuickBarSending else { return }
        prepareQuickBarSessionIfNeeded(forceReset: true)
    }

    func continueQuickBarInMainChat() {
        guard !isQuickBarSending else { return }
        guard let quickBarConversationId = quickBarState.conversationId,
              !quickBarState.messages.isEmpty
        else {
            return
        }

        cacheCurrentConversationSnapshotIfNeeded()
        let messages = quickBarState.messages
        messagesByConversationId[quickBarConversationId] = messages
        let titleSeed = messages.first(where: { $0.role == .user })?.content
        let resolvedTitle = ConversationSidebarTitleFormatter.makeTitle(
            conversationTitle: nil,
            firstUserContent: titleSeed
        )
        let lastActivityAt = messages.last?.createdAt ?? .now
        upsertSidebarThread(
            conversationId: quickBarConversationId,
            title: resolvedTitle,
            lastActivityAt: lastActivityAt
        )

        let snapshot = ConversationPageSnapshot(
            messages: messages,
            hasMoreOlderMessages: false,
            oldestLoadedOrderIndex: nil
        )
        activateConversationSnapshot(
            snapshot,
            conversationId: quickBarConversationId,
            status: "Quick Bar chat opened in main window"
        )

        showQuickBar = false
        NotificationCenter.default.post(name: .hushActivateMainWindow, object: nil)
    }
}
