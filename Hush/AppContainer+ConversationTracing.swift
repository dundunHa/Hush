import Foundation
import SwiftUI

extension AppContainer {
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

    func markConversationSwitchSnapshotAppliedIfNeeded(
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
                    conversationID: conversationId,
                    availableWidth: HushSpacing.chatContentMaxWidth
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
        availableWidth: CGFloat
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
                _ = await self.prewarmRenderCache(
                    for: messages,
                    conversationID: conversationID,
                    availableWidth: HushSpacing.chatContentMaxWidth
                )
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

    func scheduleIdlePrewarmIfNeeded() {
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
                    conversationID: conversationID,
                    availableWidth: HushSpacing.chatContentMaxWidth
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

    func scheduleSwitchAwayPrewarmIfNeeded(
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
                    conversationID: conversationID,
                    availableWidth: HushSpacing.chatContentMaxWidth
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
}
