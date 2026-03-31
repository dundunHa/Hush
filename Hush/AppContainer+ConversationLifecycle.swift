import AppKit
import Combine
import Foundation
import os
import SwiftUI

struct ConversationPageSnapshot {
    let messages: [ChatMessage]
    let hasMoreOlderMessages: Bool
    let oldestLoadedOrderIndex: Int?
}

struct ConversationMessageStats {
    let messageCount: Int
    let assistantCount: Int
    let longAssistantCount: Int
    let totalChars: Int
}

struct ConversationSwitchTrace {
    let generation: UInt64
    let conversationId: String
    let startedAt: Date
    var snapshotAppliedAt: Date?
    var layoutReadyAt: Date?
    var didLogRichRenderReady: Bool
    var didLogPresentedRendered: Bool
    var didLogRenderCacheHitRate: Bool
}

enum ConversationSwitchDebug {
    private static let logger = Logger(subsystem: "com.hush.app", category: "SwitchRender")

    static var isEnabled: Bool {
        #if DEBUG
            guard let raw = ProcessInfo.processInfo.environment["HUSH_SWITCH_DEBUG"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            else {
                return false
            }
            return raw == "1" || raw == "true" || raw == "yes"
        #else
            return false
        #endif
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        logger.debug("\(message, privacy: .public)")
        #if DEBUG
            print("[SwitchDebug] \(message)")
        #endif
    }
}

func makeConversationMessageStats(_ messages: [ChatMessage]) -> ConversationMessageStats {
    var assistantCount = 0
    var longAssistantCount = 0
    var totalChars = 0

    for message in messages {
        totalChars += message.content.count
        guard message.role == .assistant else { continue }
        assistantCount += 1
        if message.content.count > RenderConstants.progressiveRenderThresholdChars {
            longAssistantCount += 1
        }
    }

    return ConversationMessageStats(
        messageCount: messages.count,
        assistantCount: assistantCount,
        longAssistantCount: longAssistantCount,
        totalChars: totalChars
    )
}

extension AppContainer {
    // MARK: - Conversation Activation

    func activateConversation(conversationId: String) {
        beginConversationActivation(conversationId: conversationId, allowSameConversation: false)
    }

    func retryActiveConversationLoad() {
        guard let conversationId = activeConversationId else { return }
        beginConversationActivation(conversationId: conversationId, allowSameConversation: true)
    }

    private func beginConversationActivation(
        conversationId: String,
        allowSameConversation: Bool
    ) {
        if !allowSameConversation {
            guard conversationId != activeConversationId else { return }
        }

        // User activity: cancel any pending idle prewarm work immediately.
        idlePrewarmTask?.cancel()

        guard let persistence else {
            activeConversationLoadError = "Persistence unavailable"
            isActiveConversationLoading = false
            return
        }

        activeConversationLoadError = nil
        isActiveConversationLoading = true

        cacheCurrentConversationSnapshotIfNeeded()

        conversationLoadTask?.cancel()
        conversationLoadGeneration &+= 1
        let generation = conversationLoadGeneration
        activeConversationRenderGeneration = generation
        messageRenderRuntime.setActiveConversation(
            conversationID: conversationId,
            generation: generation
        )
        let previousConversationId = activeConversationId

        // Sync current active messages into bucket before switching away
        if let prevId = activeConversationId, !messages.isEmpty {
            messagesByConversationId[prevId] = messages
        }

        requestCoordinator.rebalanceForActiveSwitch(newActiveConversationId: conversationId)

        activeConversationSwitchTrace = ConversationSwitchTrace(
            generation: generation,
            conversationId: conversationId,
            startedAt: .now,
            snapshotAppliedAt: nil,
            layoutReadyAt: nil,
            didLogRichRenderReady: false,
            didLogPresentedRendered: false,
            didLogRenderCacheHitRate: false
        )
        ConversationSwitchDebug.log(
            "start generation=\(generation) from=\(previousConversationId ?? "nil") to=\(conversationId)"
        )

        isLoadingOlderMessages = false
        if !applyCachedConversationSnapshotIfAvailable(conversationId: conversationId, generation: generation) {
            ConversationSwitchDebug.log(
                "cache-miss generation=\(generation) conversation=\(conversationId)"
            )
            messages = []
            hasMoreOlderMessages = false
            oldestLoadedOrderIndex = nil
            activeConversationId = conversationId
            statusMessage = "Loading thread..."
        }

        syncStreamingContentForActiveConversationIfNeeded(conversationId: conversationId)

        conversationLoadTask = makeConversationLoadTask(
            persistence: persistence,
            conversationId: conversationId,
            generation: generation
        )

        scheduleSwitchAwayPrewarmIfNeeded(from: previousConversationId, persistence: persistence)
        scheduleIdlePrewarmIfNeeded()
    }

    private func applyCachedConversationSnapshotIfAvailable(
        conversationId: String,
        generation: UInt64
    ) -> Bool {
        guard let cached = conversationPageCache[conversationId] else { return false }

        let snapshotToApply = resolvedCachedConversationSnapshot(
            cached,
            conversationId: conversationId
        )
        let stats = makeConversationMessageStats(snapshotToApply.messages)
        ConversationSwitchDebug.log(
            "cache-hit generation=\(generation) conversation=\(conversationId) " +
                "messages=\(stats.messageCount) assistants=\(stats.assistantCount) " +
                "longAssistants=\(stats.longAssistantCount) chars=\(stats.totalChars)"
        )
        applyConversationSnapshot(snapshotToApply, conversationId: conversationId)
        markConversationSwitchSnapshotAppliedIfNeeded(
            conversationId: conversationId,
            generation: generation,
            source: "cache",
            stats: stats
        )
        statusMessage = "Ready"
        return true
    }

    private func resolvedCachedConversationSnapshot(
        _ cached: ConversationPageSnapshot,
        conversationId: String
    ) -> ConversationPageSnapshot {
        guard let bucket = messagesByConversationId[conversationId],
              bucket != cached.messages
        else {
            return cached
        }

        let pageSize = RuntimeConstants.conversationMessagePageSize
        let bounded = Array(bucket.suffix(pageSize))
        return ConversationPageSnapshot(
            messages: bounded,
            hasMoreOlderMessages: cached.hasMoreOlderMessages,
            oldestLoadedOrderIndex: cached.oldestLoadedOrderIndex
        )
    }

    private func makeConversationLoadTask(
        persistence: ChatPersistenceCoordinator,
        conversationId: String,
        generation: UInt64
    ) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                let fetchStartedAt = Date.now
                let pageSize = RuntimeConstants.conversationMessagePageSize
                ConversationSwitchDebug.log(
                    "db-fetch-start generation=\(generation) conversation=\(conversationId) " +
                        "limit=\(pageSize)"
                )
                let page = try await Task.detached(priority: .userInitiated) {
                    try persistence.fetchMessagePage(
                        conversationId: conversationId,
                        beforeOrderIndex: nil,
                        limit: pageSize
                    )
                }.value
                try Task.checkCancellation()

                guard let self, generation == self.conversationLoadGeneration else { return }
                let fetchMs = Int(Date.now.timeIntervalSince(fetchStartedAt) * 1000)
                let stats = makeConversationMessageStats(page.messages)
                ConversationSwitchDebug.log(
                    "db-fetch-done generation=\(generation) conversation=\(conversationId) fetchMs=\(fetchMs) " +
                        "messages=\(stats.messageCount) assistants=\(stats.assistantCount) " +
                        "longAssistants=\(stats.longAssistantCount) chars=\(stats.totalChars)"
                )
                let snapshot = ConversationPageSnapshot(
                    messages: page.messages,
                    hasMoreOlderMessages: page.hasMoreOlderMessages,
                    oldestLoadedOrderIndex: page.oldestOrderIndex
                )
                _ = self.applyConversationSnapshot(snapshot, conversationId: conversationId)
                self.markConversationSwitchSnapshotAppliedIfNeeded(
                    conversationId: conversationId,
                    generation: generation,
                    source: "db",
                    stats: stats
                )
                self.cacheConversationSnapshot(conversationId: conversationId, snapshot: snapshot)
                self.isActiveConversationLoading = false
                self.activeConversationLoadError = nil
                self.statusMessage = "Ready"
            } catch is CancellationError {
                ConversationSwitchDebug.log(
                    "db-fetch-cancelled generation=\(generation) conversation=\(conversationId)"
                )
                guard let self else { return }
                guard generation == self.conversationLoadGeneration else { return }
                guard self.activeConversationId == conversationId else { return }
                guard self.messages.isEmpty else { return }

                if self.activeConversationSwitchTrace?.generation == generation {
                    self.activeConversationSwitchTrace = nil
                }
                self.isActiveConversationLoading = false
                self.activeConversationLoadError = "Loading cancelled"
                self.statusMessage = "Loading cancelled"
            } catch {
                guard let self, generation == self.conversationLoadGeneration else { return }
                if self.activeConversationSwitchTrace?.generation == generation {
                    self.activeConversationSwitchTrace = nil
                }
                ConversationSwitchDebug.log(
                    "db-fetch-failed generation=\(generation) conversation=\(conversationId) " +
                        "error=\(error.localizedDescription)"
                )
                self.isActiveConversationLoading = false
                self.activeConversationLoadError = error.localizedDescription
                self.statusMessage = "Failed to load thread: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    func loadOlderMessagesIfNeeded() async -> Bool {
        guard !isLoadingOlderMessages else { return false }
        guard hasMoreOlderMessages else { return false }
        guard let persistence, let conversationId = activeConversationId else { return false }
        guard let beforeOrderIndex = oldestLoadedOrderIndex else {
            hasMoreOlderMessages = false
            return false
        }

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        let pageSize = RuntimeConstants.conversationMessagePageSize

        do {
            let page = try await Task.detached(priority: .userInitiated) {
                try persistence.fetchMessagePage(
                    conversationId: conversationId,
                    beforeOrderIndex: beforeOrderIndex,
                    limit: pageSize
                )
            }.value

            guard conversationId == activeConversationId else { return false }

            hasMoreOlderMessages = page.hasMoreOlderMessages
            if let oldestOrderIndex = page.oldestOrderIndex {
                oldestLoadedOrderIndex = oldestOrderIndex
            }

            let existingIDs = Set(messages.map(\.id))
            let incoming = page.messages.filter { !existingIDs.contains($0.id) }
            guard !incoming.isEmpty else { return false }

            messages = incoming + messages
            cacheCurrentConversationSnapshotIfNeeded()
            return true
        } catch {
            statusMessage = "Failed to load earlier messages: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func loadMoreSidebarThreadsIfNeeded() async -> Bool {
        guard !isLoadingMoreSidebarThreads else { return false }
        guard hasMoreSidebarThreads else { return false }
        guard let persistence else { return false }

        let loadGeneration = sidebarThreadsLoadGeneration
        let cursor = sidebarThreadsCursor
        isLoadingMoreSidebarThreads = true
        defer { isLoadingMoreSidebarThreads = false }

        do {
            let page = try await Task.detached(priority: .userInitiated) {
                try persistence.fetchSidebarThreadsPage(
                    cursor: cursor,
                    limit: 10
                )
            }.value

            if let delay = sidebarThreadsLoadApplyDelayOverride {
                try? await Task.sleep(for: delay)
            }

            guard loadGeneration == sidebarThreadsLoadGeneration else {
                return false
            }

            hasMoreSidebarThreads = page.hasMore
            sidebarThreadsCursor = page.nextCursor

            let existingIDs = Set(sidebarThreads.map(\.id))
            let incoming = page.threads.filter { !existingIDs.contains($0.id) }
            guard !incoming.isEmpty else { return false }

            sidebarThreads.append(contentsOf: incoming)
            return true
        } catch {
            guard loadGeneration == sidebarThreadsLoadGeneration else {
                return false
            }
            statusMessage = "Failed to load more threads: \(error.localizedDescription)"
            return false
        }
    }
}
