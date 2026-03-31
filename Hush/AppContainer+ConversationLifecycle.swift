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

    private func syncStreamingContentForActiveConversationIfNeeded(conversationId: String) {
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

    private func syncPresentedStreamingMessageIntoBucketsIfNeeded(
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
    private func applyConversationSnapshot(
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

    private func cacheConversationSnapshot(
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

    // MARK: - Conversation Switch Tracing

    func markConversationSwitchLayoutReady() {
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.conversationId == activeConversationId else { return }
        guard trace.layoutReadyAt == nil else { return }

        trace.layoutReadyAt = .now
        let layoutReadyAt = trace.layoutReadyAt ?? .now
        let snapshotLagMs: Int?
        let snapshotLag: String
        if let snapshotAt = trace.snapshotAppliedAt {
            let lag = Int(layoutReadyAt.timeIntervalSince(snapshotAt) * 1000)
            snapshotLagMs = lag
            snapshotLag = "\(lag)ms"
        } else {
            snapshotLagMs = nil
            snapshotLag = "n/a"
        }
        let totalElapsedMs = Int(layoutReadyAt.timeIntervalSince(trace.startedAt) * 1000)
        PerfTrace.duration(
            PerfTrace.Event.switchLayoutReady,
            ms: Double(totalElapsedMs),
            fields: [
                "generation": "\(trace.generation)",
                "conversation": trace.conversationId
            ]
        )
        if let snapshotLagMs {
            PerfTrace.duration(
                PerfTrace.Event.switchSnapshotToLayoutReady,
                ms: Double(snapshotLagMs),
                fields: [
                    "generation": "\(trace.generation)",
                    "conversation": trace.conversationId
                ]
            )
        }
        ConversationSwitchDebug.log(
            "layout-ready generation=\(trace.generation) conversation=\(trace.conversationId) " +
                "snapshot->layout=\(snapshotLag) total=\(totalElapsedMs)ms"
        )
        activeConversationSwitchTrace = trace
    }

    func reportActiveConversationRichRenderReadyIfNeeded() {
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.conversationId == activeConversationId else { return }
        guard let snapshotAppliedAt = trace.snapshotAppliedAt else { return }
        guard !trace.didLogRichRenderReady else { return }

        trace.didLogRichRenderReady = true
        let now = Date.now
        let snapshotElapsedMs = Int(now.timeIntervalSince(snapshotAppliedAt) * 1000)
        let totalElapsedMs = Int(now.timeIntervalSince(trace.startedAt) * 1000)
        let stats = makeConversationMessageStats(messages)
        PerfTrace.duration(
            PerfTrace.Event.switchRichReady,
            ms: Double(totalElapsedMs),
            fields: [
                "generation": "\(trace.generation)",
                "conversation": trace.conversationId,
                "messages": "\(stats.messageCount)"
            ]
        )
        PerfTrace.duration(
            PerfTrace.Event.switchSnapshotToRichReady,
            ms: Double(snapshotElapsedMs),
            fields: [
                "generation": "\(trace.generation)",
                "conversation": trace.conversationId,
                "messages": "\(stats.messageCount)"
            ]
        )
        ConversationSwitchDebug.log(
            "rich-ready generation=\(trace.generation) conversation=\(trace.conversationId) " +
                "snapshot->rich=\(snapshotElapsedMs)ms total=\(totalElapsedMs)ms " +
                "messages=\(stats.messageCount) longAssistants=\(stats.longAssistantCount)"
        )
        activeConversationSwitchTrace = nil
    }

    func reportSwitchPresentedRenderedFromReloadIfNeeded(
        conversationId: String?,
        generation: UInt64,
        renderCacheHits: Int,
        renderCacheMisses: Int,
        contentWidth: Int
    ) {
        guard let conversationId else { return }
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.generation == generation else { return }
        guard trace.conversationId == conversationId else { return }

        let hits = max(0, renderCacheHits)
        let misses = max(0, renderCacheMisses)
        let total = hits + misses

        if !trace.didLogRenderCacheHitRate, total > 0 {
            let hitRate = Double(hits) / Double(total)
            PerfTrace.count(
                PerfTrace.Event.renderCacheHitRate,
                fields: [
                    "generation": "\(generation)",
                    "conversation": conversationId,
                    "hits": "\(hits)",
                    "misses": "\(misses)",
                    "hit_rate": String(format: "%.2f", hitRate)
                ]
            )
            trace.didLogRenderCacheHitRate = true
        }

        guard !trace.didLogPresentedRendered else {
            activeConversationSwitchTrace = trace
            return
        }
        guard total > 0 else {
            activeConversationSwitchTrace = trace
            return
        }

        let mode = misses > 0 ? "cache-miss-reload" : "cache-hit-reload"
        let elapsedMs = Int(Date.now.timeIntervalSince(trace.startedAt) * 1000)
        PerfTrace.duration(
            PerfTrace.Event.switchPresentedRendered,
            ms: Double(elapsedMs),
            fields: [
                "generation": "\(generation)",
                "conversation": conversationId,
                "mode": mode,
                "content_width": "\(contentWidth)",
                "hits": "\(hits)",
                "misses": "\(misses)"
            ]
        )

        trace.didLogPresentedRendered = true
        activeConversationSwitchTrace = trace
    }

    func reportHotSceneSwitchPresentedRenderedIfNeeded(
        conversationId: String,
        generation: UInt64
    ) {
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.generation == generation else { return }
        guard trace.conversationId == conversationId else { return }

        if trace.snapshotAppliedAt == nil {
            trace.snapshotAppliedAt = .now
            let elapsedMs = Int(trace.snapshotAppliedAt!.timeIntervalSince(trace.startedAt) * 1000)
            let stats = makeConversationMessageStats(messages)
            PerfTrace.duration(
                PerfTrace.Event.switchSnapshotApplied,
                ms: Double(elapsedMs),
                fields: [
                    "generation": "\(generation)",
                    "conversation": conversationId,
                    "source": "hot-scene",
                    "messages": "\(stats.messageCount)"
                ]
            )
        }

        if !trace.didLogRenderCacheHitRate {
            PerfTrace.count(
                PerfTrace.Event.renderCacheHitRate,
                fields: [
                    "generation": "\(generation)",
                    "conversation": conversationId,
                    "hits": "0",
                    "misses": "0",
                    "hit_rate": "n/a",
                    "mode": "hot-scene"
                ]
            )
            trace.didLogRenderCacheHitRate = true
        }

        if !trace.didLogPresentedRendered {
            let elapsedMs = Int(Date.now.timeIntervalSince(trace.startedAt) * 1000)
            PerfTrace.duration(
                PerfTrace.Event.switchPresentedRendered,
                ms: Double(elapsedMs),
                fields: [
                    "generation": "\(generation)",
                    "conversation": conversationId,
                    "mode": "hot-scene"
                ]
            )
            trace.didLogPresentedRendered = true
        }

        activeConversationSwitchTrace = trace
        markConversationSwitchLayoutReady()
        reportActiveConversationRichRenderReadyIfNeeded()
    }

    var cachedConversationIDsForTesting: [String] {
        conversationPageCacheOrder
    }

    func runStartupPrewarmForTesting() async {
        await performStartupPrewarmIfNeeded()
    }

    private func markConversationSwitchSnapshotAppliedIfNeeded(
        conversationId: String,
        generation: UInt64,
        source: String,
        stats: ConversationMessageStats
    ) {
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.generation == generation else { return }
        guard trace.conversationId == conversationId else { return }
        guard trace.snapshotAppliedAt == nil else { return }

        trace.snapshotAppliedAt = .now
        let elapsedMs = Int(trace.snapshotAppliedAt!.timeIntervalSince(trace.startedAt) * 1000)
        PerfTrace.duration(
            PerfTrace.Event.switchSnapshotApplied,
            ms: Double(elapsedMs),
            fields: [
                "generation": "\(generation)",
                "conversation": conversationId,
                "source": source,
                "messages": "\(stats.messageCount)"
            ]
        )
        ConversationSwitchDebug.log(
            "snapshot-applied source=\(source) generation=\(generation) conversation=\(conversationId) " +
                "elapsed=\(elapsedMs)ms messages=\(stats.messageCount) assistants=\(stats.assistantCount) " +
                "longAssistants=\(stats.longAssistantCount) chars=\(stats.totalChars)"
        )
        activeConversationSwitchTrace = trace
    }

    func scheduleStartupPrewarmIfNeeded() {
        ConversationSwitchDebug.log("startup-prewarm-scheduled")
        startupPrewarmTask?.cancel()
        startupPrewarmTask = Task { [weak self] in
            guard let self else { return }
            await self.performStartupPrewarmIfNeeded()
        }
    }

    private func performStartupPrewarmIfNeeded() async {
        guard let persistence else { return }

        let candidateIDs = Array(
            sidebarThreads
                .map(\.id)
                .filter { $0 != activeConversationId }
                .prefix(RenderConstants.startupPrewarmConversationCount)
        )
        guard !candidateIDs.isEmpty else {
            ConversationSwitchDebug.log("startup-prewarm-skip no-candidates")
            return
        }

        ConversationSwitchDebug.log(
            "startup-prewarm-begin candidates=\(candidateIDs.count) active=\(activeConversationId ?? "nil")"
        )

        for conversationId in candidateIDs {
            if Task.isCancelled { return }

            do {
                let fetchStartedAt = Date.now
                let page = try await Task.detached(priority: .utility) {
                    try persistence.fetchMessagePage(
                        conversationId: conversationId,
                        beforeOrderIndex: nil,
                        limit: RenderConstants.startupPrewarmMessageLimit
                    )
                }.value

                if Task.isCancelled { return }

                let snapshot = ConversationPageSnapshot(
                    messages: page.messages,
                    hasMoreOlderMessages: page.hasMoreOlderMessages,
                    oldestLoadedOrderIndex: page.oldestOrderIndex
                )
                cacheConversationSnapshot(conversationId: conversationId, snapshot: snapshot)
                let fetchMs = Int(Date.now.timeIntervalSince(fetchStartedAt) * 1000)
                let stats = makeConversationMessageStats(page.messages)
                let prewarmedCount = await prewarmRenderCache(
                    for: page.messages,
                    conversationID: conversationId
                )
                ConversationSwitchDebug.log(
                    "startup-prewarm-done conversation=\(conversationId) fetchMs=\(fetchMs) " +
                        "messages=\(stats.messageCount) assistants=\(stats.assistantCount) " +
                        "longAssistants=\(stats.longAssistantCount) prewarmedAssistants=\(prewarmedCount)"
                )
            } catch {
                ConversationSwitchDebug.log(
                    "startup-prewarm-failed conversation=\(conversationId) error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func prewarmRenderCache(
        for messages: [ChatMessage],
        conversationID: String?,
        availableWidth: CGFloat = HushSpacing.chatContentMaxWidth
    ) async -> Int {
        let assistants = messages.filter { $0.role == .assistant }
        guard !assistants.isEmpty else { return 0 }

        let targetMessages = assistants.suffix(RenderConstants.startupRenderPrewarmAssistantMessageCap)
        guard !targetMessages.isEmpty else { return 0 }

        let style = RenderStyle.fromTheme(settings.theme, fontSettings: settings.fontSettings)
        let inputs = targetMessages.map {
            MessageRenderInput(
                content: $0.content,
                availableWidth: availableWidth,
                style: style,
                isStreaming: false
            )
        }
        await messageRenderRuntime.prewarm(inputs: inputs, protectFor: conversationID)
        return targetMessages.count
    }

    func scheduleStreamingCompletePrewarmIfNeeded(
        conversationID: String,
        finalAssistantContent: String
    ) {
        guard conversationID != activeConversationId else { return }
        guard !finalAssistantContent.isEmpty else { return }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await Task.yield()

            let isHotScene = self.hotScenePool?.hotConversationIDs.contains(conversationID) ?? false
            if isHotScene {
                let messages = self.messagesForConversation(conversationID)
                _ = await self.prewarmRenderCache(for: messages, conversationID: conversationID)
                return
            }

            let style = RenderStyle.fromTheme(self.settings.theme, fontSettings: self.settings.fontSettings)
            let input = MessageRenderInput(
                content: finalAssistantContent,
                availableWidth: HushSpacing.chatContentMaxWidth,
                style: style,
                isStreaming: false
            )
            await self.messageRenderRuntime.prewarm(
                inputs: [input],
                protectFor: conversationID
            )
        }
    }

    func performResizeCacheCleanup(
        contentWidth: CGFloat,
        hotConversationIDs: [String]
    ) async {
        guard contentWidth > 0 else { return }

        messageRenderRuntime.clearAllProtections()

        var targets: [String] = []
        if let activeConversationId {
            targets.append(activeConversationId)
        }
        targets.append(contentsOf: hotConversationIDs)

        var seen: Set<String> = []
        for conversationID in targets where seen.insert(conversationID).inserted {
            let messages = messagesForConversation(conversationID)
            _ = await prewarmRenderCache(
                for: messages,
                conversationID: conversationID,
                availableWidth: contentWidth
            )
            await Task.yield()
        }
    }

    private func noteUserActivityForIdlePrewarm() {
        scheduleIdlePrewarmIfNeeded()
    }

    func cancelIdlePrewarmFromCoordinator() {
        idlePrewarmTask?.cancel()
    }

    func scheduleIdlePrewarmFromCoordinator() {
        scheduleIdlePrewarmIfNeeded()
    }

    private func scheduleIdlePrewarmIfNeeded() {
        idlePrewarmTask?.cancel()
        idlePrewarmTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .seconds(RenderConstants.idlePrewarmDelay))
            if Task.isCancelled { return }
            guard !self.isActiveConversationSending else { return }

            let conversationIDs = self.hotConversationIDsForIdlePrewarm()
            guard !conversationIDs.isEmpty else { return }

            for conversationID in conversationIDs {
                if Task.isCancelled { return }
                guard let snapshot = self.conversationPageCache[conversationID] else { continue }
                _ = await self.prewarmRenderCache(
                    for: snapshot.messages,
                    conversationID: conversationID
                )
            }
        }
    }

    private func hotConversationIDsForIdlePrewarm() -> [String] {
        let active = activeConversationId
        return Array(
            conversationPageCacheOrder
                .reversed()
                .filter { $0 != active }
                .prefix(RenderConstants.startupPrewarmConversationCount)
        )
    }

    private func scheduleSwitchAwayPrewarmIfNeeded(
        from previousConversationId: String?,
        persistence: ChatPersistenceCoordinator
    ) {
        guard let previousConversationId else { return }

        let activatedConversationId = activeConversationId
        let adjacent = sidebarAdjacentConversationIDs(around: previousConversationId)
            .filter { $0 != activatedConversationId }

        guard !adjacent.isEmpty else { return }

        switchAwayPrewarmTask?.cancel()
        switchAwayPrewarmTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await Task.yield()

            for conversationID in adjacent {
                if Task.isCancelled { return }
                let messages = self.messagesForPrewarm(conversationId: conversationID, persistence: persistence)
                if messages.isEmpty { continue }
                _ = await self.prewarmRenderCache(
                    for: messages,
                    conversationID: conversationID
                )
                await Task.yield()
            }
        }
    }

    private func sidebarAdjacentConversationIDs(around conversationId: String) -> [String] {
        guard let idx = sidebarThreads.firstIndex(where: { $0.id == conversationId }) else { return [] }

        var candidates: [String] = []
        if idx > 0 {
            candidates.append(sidebarThreads[idx - 1].id)
        }
        if idx + 1 < sidebarThreads.count {
            candidates.append(sidebarThreads[idx + 1].id)
        }

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }

    private func messagesForPrewarm(
        conversationId: String,
        persistence: ChatPersistenceCoordinator
    ) -> [ChatMessage] {
        if let snapshot = conversationPageCache[conversationId] {
            return snapshot.messages
        }
        if let bucket = messagesByConversationId[conversationId] {
            return bucket
        }
        return (try? persistence.fetchMessagePage(
            conversationId: conversationId,
            beforeOrderIndex: nil,
            limit: RenderConstants.startupPrewarmMessageLimit
        ).messages) ?? []
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
                try await messageAssetStore?.deleteAllAssets()
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

    // MARK: - Settings Persistence (Debounced)

    func persistSettingsIfNeeded(previous: AppSettings) {
        guard previous != settings else { return }
        isDirty = true
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: RuntimeConstants.settingsDebounceInterval)
                self.performSave()
            } catch {
                // Cancelled — a newer debounce or flush superseded this one
            }
        }
    }

    private func performSave() {
        guard isDirty else { return }
        do {
            try preferencesRepository?.save(settings)
            isDirty = false
        } catch {
            // Keep dirty for retry on next debounce cycle or flush
            statusMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    /// Force-save pending settings immediately. Call at lifecycle boundaries
    /// (app background/inactive scene phase transitions).
    func flushSettings() {
        debounceTask?.cancel()
        debounceTask = nil
        performSave()
    }
}
