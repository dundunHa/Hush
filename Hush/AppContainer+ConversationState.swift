import Foundation
import SwiftUI

extension AppContainer {
    // MARK: - Conversation Management

    func resetConversation() {
        cacheCurrentConversationSnapshotIfNeeded()
        activeConversationSwitchTrace = nil

        conversationLoadTask?.cancel()
        conversationLoadTask = nil

        if let prevId = activeConversationId, !messages.isEmpty {
            messagesByConversationId[prevId] = messages
        }

        messages.removeAll()
        isLoadingOlderMessages = false
        hasMoreOlderMessages = false
        oldestLoadedOrderIndex = nil
        isActiveConversationLoading = false
        activeConversationLoadError = nil
        statusMessage = "Conversation cleared"

        if let persistence {
            activeConversationId = try? persistence.createNewConversation()
            conversationLoadGeneration &+= 1
            activeConversationRenderGeneration = conversationLoadGeneration
            messageRenderRuntime.setActiveConversation(
                conversationID: activeConversationId,
                generation: activeConversationRenderGeneration
            )
        } else {
            conversationLoadGeneration &+= 1
            activeConversationRenderGeneration = conversationLoadGeneration
            messageRenderRuntime.setActiveConversation(
                conversationID: activeConversationId,
                generation: activeConversationRenderGeneration
            )
        }

        requestCoordinator.rebalanceForActiveSwitch(newActiveConversationId: activeConversationId)
    }

    func deleteConversation(conversationId: String) {
        if requestCoordinator.isConversationRunning(conversationId) {
            requestCoordinator.stopConversation(conversationId)
        }
        guard let persistence else { return }

        messageRenderRuntime.clearProtection(conversationID: conversationId)

        do {
            try persistence.deleteConversation(id: conversationId)
        } catch {
            statusMessage = "Failed to delete: \(error.localizedDescription)"
            return
        }

        sidebarThreads.removeAll { $0.id == conversationId }
        conversationPageCache.removeValue(forKey: conversationId)
        conversationPageCacheOrder.removeAll { $0 == conversationId }
        messagesByConversationId.removeValue(forKey: conversationId)

        if activeConversationId == conversationId {
            resetConversation()
        }
    }

    func syncStreamingContentForActiveConversationIfNeeded(conversationId: String) {
        guard conversationId == activeConversationId else { return }
        guard let running = requestCoordinator.runningRequest(forConversation: conversationId) else { return }
        guard let messageID = running.assistantMessageID else { return }
        syncPresentedStreamingMessageIntoBucketsIfNeeded(
            conversationId: conversationId,
            messageID: messageID,
            content: running.presentedText
        )
        pushStreamingContent(
            conversationId: conversationId,
            messageID: messageID,
            content: running.presentedText
        )
    }

    func syncPresentedStreamingMessageIntoBucketsIfNeeded(
        conversationId: String,
        messageID: UUID,
        content: String
    ) {
        var didUpdateActiveMessages = false

        if conversationId == activeConversationId,
           let activeIndex = messages.lastIndex(where: { $0.id == messageID }),
           messages[activeIndex].content != content
        {
            let existing = messages[activeIndex]
            messages[activeIndex] = existing.updatingContent(content)
            didUpdateActiveMessages = true
        }

        if var bucket = messagesByConversationId[conversationId] {
            if let bucketIndex = bucket.lastIndex(where: { $0.id == messageID }),
               bucket[bucketIndex].content != content
            {
                let existing = bucket[bucketIndex]
                bucket[bucketIndex] = existing.updatingContent(content)
                messagesByConversationId[conversationId] = bucket
            } else if didUpdateActiveMessages {
                messagesByConversationId[conversationId] = messages
            }
        } else if didUpdateActiveMessages {
            messagesByConversationId[conversationId] = messages
        }
    }

    func archiveConversation(conversationId: String) {
        if requestCoordinator.isConversationRunning(conversationId) {
            statusMessage = "Stop active request before archiving"
            return
        }
        guard let persistence else { return }

        do {
            try persistence.archiveConversation(id: conversationId)
        } catch {
            statusMessage = "Failed to archive: \(error.localizedDescription)"
            return
        }

        sidebarThreads.removeAll { $0.id == conversationId }

        if activeConversationId == conversationId {
            resetConversation()
        }
    }

    func unarchiveConversation(conversationId: String) {
        guard let persistence else { return }

        do {
            try persistence.unarchiveConversation(id: conversationId)
        } catch {
            statusMessage = "Failed to unarchive: \(error.localizedDescription)"
            return
        }

        // Re-insert into sidebar sorted by lastActivityAt
        if let threads = try? persistence.fetchSidebarThreads(limit: 200) {
            if let restored = threads.first(where: { $0.id == conversationId }) {
                let insertIndex = sidebarThreads.firstIndex(where: {
                    $0.lastActivityAt < restored.lastActivityAt
                }) ?? sidebarThreads.endIndex
                sidebarThreads.insert(restored, at: insertIndex)
            }
        }
    }

    func fetchArchivedThreads() -> [ConversationSidebarThread] {
        guard let persistence else { return [] }
        return (try? persistence.fetchArchivedThreads()) ?? []
    }

    @discardableResult
    func applyConversationSnapshot(
        _ snapshot: ConversationPageSnapshot,
        conversationId: String
    ) -> Bool {
        var didChange = false

        if messages != snapshot.messages {
            messages = snapshot.messages
            didChange = true
        }

        // Sync to message bucket
        messagesByConversationId[conversationId] = snapshot.messages

        if hasMoreOlderMessages != snapshot.hasMoreOlderMessages {
            hasMoreOlderMessages = snapshot.hasMoreOlderMessages
            didChange = true
        }

        if oldestLoadedOrderIndex != snapshot.oldestLoadedOrderIndex {
            oldestLoadedOrderIndex = snapshot.oldestLoadedOrderIndex
            didChange = true
        }

        if activeConversationId != conversationId {
            activeConversationId = conversationId
            didChange = true
        }

        return didChange
    }

    func activateConversationSnapshot(
        _ snapshot: ConversationPageSnapshot,
        conversationId: String,
        status: String
    ) {
        conversationLoadTask?.cancel()
        conversationLoadTask = nil
        activeConversationSwitchTrace = nil
        isActiveConversationLoading = false
        activeConversationLoadError = nil
        hasMoreOlderMessages = snapshot.hasMoreOlderMessages
        oldestLoadedOrderIndex = snapshot.oldestLoadedOrderIndex

        conversationLoadGeneration &+= 1
        activeConversationRenderGeneration = conversationLoadGeneration
        messageRenderRuntime.setActiveConversation(
            conversationID: conversationId,
            generation: activeConversationRenderGeneration
        )
        requestCoordinator.rebalanceForActiveSwitch(newActiveConversationId: conversationId)
        _ = applyConversationSnapshot(snapshot, conversationId: conversationId)
        cacheConversationSnapshot(conversationId: conversationId, snapshot: snapshot)
        clearUnreadCompletion(forConversation: conversationId)
        statusMessage = status
    }

    func cacheCurrentConversationSnapshotIfNeeded() {
        guard let conversationId = activeConversationId else { return }
        guard messages.count <= RuntimeConstants.conversationMessagePageSize else { return }
        if let running = requestCoordinator?.runningRequest(forConversation: conversationId),
           let messageID = running.assistantMessageID
        {
            syncPresentedStreamingMessageIntoBucketsIfNeeded(
                conversationId: conversationId,
                messageID: messageID,
                content: running.presentedText
            )
        }
        let snapshot = ConversationPageSnapshot(
            messages: messages,
            hasMoreOlderMessages: hasMoreOlderMessages,
            oldestLoadedOrderIndex: oldestLoadedOrderIndex
        )
        cacheConversationSnapshot(conversationId: conversationId, snapshot: snapshot)
    }

    func cacheConversationSnapshot(
        conversationId: String,
        snapshot: ConversationPageSnapshot
    ) {
        conversationPageCache[conversationId] = snapshot
        conversationPageCacheOrder.removeAll { $0 == conversationId }
        conversationPageCacheOrder.append(conversationId)

        while conversationPageCacheOrder.count > conversationPageCacheCapacity {
            let evicted = conversationPageCacheOrder.removeFirst()
            conversationPageCache.removeValue(forKey: evicted)
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .background || phase == .inactive else { return }
        flushSettings()
    }

    // MARK: - Data Management

    func fetchDataStats() async -> DataStats {
        guard let persistence else {
            return DataStats(databaseSizeBytes: 0, conversationCount: 0, messageCount: 0)
        }
        return await Task.detached(priority: .utility) {
            let size = persistence.databaseFileSize()
            let conversations = (try? persistence.conversationCount()) ?? 0
            let messages = (try? persistence.messageCount()) ?? 0
            return DataStats(databaseSizeBytes: size, conversationCount: conversations, messageCount: messages)
        }.value
    }

    func deleteAllChatHistory() async {
        guard !isSending else {
            statusMessage = "Stop active request before clearing data"
            return
        }
        guard let persistence else { return }
        let messageAssetStore = self.messageAssetStore

        sidebarThreadsLoadGeneration &+= 1

        do {
            try await Task.detached(priority: .userInitiated) {
                try messageAssetStore?.deleteAllAssets()
                try persistence.deleteAllChatData()
            }.value
        } catch {
            statusMessage = "Failed to clear data: \(error.localizedDescription)"
            return
        }

        sidebarThreads.removeAll()
        conversationPageCache.removeAll()
        conversationPageCacheOrder.removeAll()
        isLoadingMoreSidebarThreads = false
        sidebarThreadsCursor = nil
        hasMoreSidebarThreads = false

        messages.removeAll()
        isLoadingOlderMessages = false
        hasMoreOlderMessages = false
        oldestLoadedOrderIndex = nil
        activeConversationId = try? persistence.createNewConversation()
        conversationLoadGeneration &+= 1
        activeConversationRenderGeneration = conversationLoadGeneration
        messageRenderRuntime.setActiveConversation(
            conversationID: activeConversationId,
            generation: activeConversationRenderGeneration
        )
        statusMessage = "All chat history cleared"
    }
}
