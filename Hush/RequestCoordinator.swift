// swiftlint:disable file_length
import Foundation
import os

private let logger = Logger(subsystem: "com.hush.app", category: "RequestCoordinator")

@MainActor
final class RequestCoordinator {
    // MARK: - Dependencies

    private weak var container: AppContainer?
    private let persistence: ChatPersistenceCoordinator?
    private let credentialResolver: CredentialResolver

    // MARK: - Scheduler State

    private(set) var schedulerState = SchedulerState()

    // MARK: - Per-Session Stream State

    private var sessionFlushState: [RequestID: SessionFlushState] = [:]

    // MARK: - Testing Overrides

    var preflightTimeoutOverride: Duration?
    var generationTimeoutOverride: Duration?
    var streamingPresentationPolicyOverride: StreamingPresentationPolicy?

    // MARK: - Init

    init(
        container: AppContainer,
        persistence: ChatPersistenceCoordinator?,
        credentialResolver: CredentialResolver
    ) {
        self.container = container
        self.persistence = persistence
        self.credentialResolver = credentialResolver
    }

    private var streamingPresentationPolicy: StreamingPresentationPolicy {
        streamingPresentationPolicyOverride ?? RenderConstants.streamingPresentationPolicy
    }

    // MARK: - Public Interface

    func submitRequest(_ snapshot: QueueItemSnapshot) {
        guard let container else { return }
        let canStartImmediately =
            schedulerState.runningSessions.count < schedulerState.maxConcurrent
                && !RequestScheduler.isConversationRunning(snapshot.conversationId, state: schedulerState)

        if canStartImmediately {
            startSession(snapshot)
        } else {
            RequestScheduler.enqueue(
                snapshot,
                activeConversationId: container.activeConversationId,
                state: &schedulerState
            )
            let queued = RequestScheduler.totalQueuedCount(state: schedulerState)
            let capacity = RuntimeConstants.pendingQueueCapacity
            container.statusMessage = "Queued (\(queued)/\(capacity))"
        }
        container.syncPublishedSchedulerState()
    }

    func stopConversation(_ conversationId: String) {
        guard let container else { return }
        guard let (requestID, _) = schedulerState.runningSessions.first(where: {
            $0.value.conversationId == conversationId
        }) else {
            container.statusMessage = "No active request to stop"
            return
        }
        stopSession(requestID: requestID)
    }

    func cancelAll() {
        shutdown()
        container?.syncPublishedSchedulerState()
    }

    func shutdown() {
        for (_, session) in schedulerState.runningSessions {
            session.streamTask?.cancel()
        }
        schedulerState.runningSessions.removeAll()
        schedulerState.activeQueue.removeAll()
        schedulerState.backgroundQueues.removeAll()
        for (_, flushState) in sessionFlushState {
            flushState.pendingFastFlush?.cancel()
            flushState.pendingUIFlush?.cancel()
            flushState.pendingStreamingFlush?.cancel()
            flushState.pendingRevealTask?.cancel()
        }
        sessionFlushState.removeAll()
    }

    func updateMaxConcurrent(_ limit: Int) {
        schedulerState.maxConcurrent = max(1, limit)
        advanceQueue()
    }

    func rebalanceForActiveSwitch(newActiveConversationId: String?) {
        RequestScheduler.rebalanceForActiveSwitch(
            newActiveConversationId: newActiveConversationId,
            state: &schedulerState
        )
    }

    var isQueueFull: Bool {
        !RequestScheduler.canAcceptSubmission(state: schedulerState)
    }

    var hasAnyRunning: Bool {
        !schedulerState.runningSessions.isEmpty
    }

    var totalQueuedCount: Int {
        RequestScheduler.totalQueuedCount(state: schedulerState)
    }

    func isConversationRunning(_ conversationId: String) -> Bool {
        RequestScheduler.isConversationRunning(conversationId, state: schedulerState)
    }

    func conversationsWithRunning() -> Set<String> {
        RequestScheduler.conversationsWithRunning(state: schedulerState)
    }

    func conversationsWithQueued() -> [String: Int] {
        RequestScheduler.conversationsWithQueued(state: schedulerState)
    }

    func runningRequest(forConversation conversationId: String) -> ActiveRequestState? {
        guard let container else { return nil }
        guard let (requestID, _) = schedulerState.runningSessions.first(where: {
            $0.value.conversationId == conversationId
        }) else { return nil }
        return container.requestStates[requestID]
    }
}

// MARK: - Session Lifecycle

extension RequestCoordinator {
    private func startSession(_ snapshot: QueueItemSnapshot) {
        guard let container else { return }
        let requestState = ActiveRequestState(
            requestID: snapshot.id,
            conversationId: snapshot.conversationId
        )
        container.requestStates[snapshot.id] = requestState

        let task = Task { [weak self] in
            guard let self else { return }
            await self.executeRequest(snapshot)
        }

        schedulerState.runningSessions[snapshot.id] = RunningSession(
            requestID: snapshot.id,
            conversationId: snapshot.conversationId,
            streamTask: task
        )
        sessionFlushState[snapshot.id] = SessionFlushState()
        container.cancelIdlePrewarmFromCoordinator()
        container.statusMessage = "Processing..."
        container.syncPublishedSchedulerState()
    }

    private func stopSession(requestID: RequestID) {
        guard let container else { return }
        guard let state = container.requestStates[requestID],
              !state.isTerminal else { return }
        let hadContent = !state.accumulatedText.isEmpty
        let owningConversationId = state.conversationId

        container.requestStates[requestID]?.status = .stopped
        container.requestStates[requestID]?.revealAll()
        flushPendingUIUpdate(requestID: requestID, contentSource: .accumulated)
        cleanupFlushState(requestID: requestID)

        if let msgID = container.requestStates[requestID]?.assistantMessageID {
            try? persistence?.finalizeAssistantMessage(
                messageId: msgID.uuidString,
                content: container.requestStates[requestID]?.accumulatedText ?? "",
                status: .stopped
            )
        }
        if !hadContent {
            let stoppedMessage = ChatMessage(role: .assistant, content: "[Request stopped]")
            container.appendMessage(stoppedMessage, toConversation: owningConversationId)
            if !owningConversationId.isEmpty {
                try? persistence?.persistSystemMessage(
                    stoppedMessage,
                    conversationId: owningConversationId,
                    status: .stopped
                )
            }
        }

        schedulerState.runningSessions[requestID]?.streamTask?.cancel()
        schedulerState.runningSessions.removeValue(forKey: requestID)
        container.requestStates.removeValue(forKey: requestID)
        container.statusMessage = "Request stopped"
        container.syncPublishedSchedulerState()
        container.scheduleIdlePrewarmFromCoordinator()
        advanceQueue()
    }

    private func completeSession(requestID: RequestID) {
        guard let container else { return }
        guard let state = container.requestStates[requestID],
              !state.isTerminal else { return }
        let owningConversationId = state.conversationId

        container.requestStates[requestID]?.status = .completed
        container.requestStates[requestID]?.revealAll()
        flushPendingUIUpdate(requestID: requestID, contentSource: .accumulated)
        cleanupFlushState(requestID: requestID)

        if let msgID = container.requestStates[requestID]?.assistantMessageID {
            try? persistence?.finalizeAssistantMessage(
                messageId: msgID.uuidString,
                content: container.requestStates[requestID]?.accumulatedText ?? "",
                status: .completed
            )
        }

        let isBackground = owningConversationId != container.activeConversationId
        let finalAssistantContent = state.accumulatedText
        if isBackground {
            container.scheduleStreamingCompletePrewarmIfNeeded(
                conversationID: owningConversationId,
                finalAssistantContent: finalAssistantContent
            )
        }
        schedulerState.runningSessions.removeValue(forKey: requestID)
        container.requestStates.removeValue(forKey: requestID)
        container.statusMessage = isBackground ? "Background request complete" : "Response complete"

        container.syncPublishedSchedulerState()
        container.scheduleIdlePrewarmFromCoordinator()
        advanceQueue()
    }

    private func failSession(requestID: RequestID, error: RequestError) {
        guard let container else { return }
        guard let state = container.requestStates[requestID],
              !state.isTerminal else { return }
        let owningConversationId = state.conversationId
        let errorDescription = error.errorDescription ?? "Unknown error"

        container.requestStates[requestID]?.status = .failed(error)
        logger.error("[Request] Request failed: \(errorDescription)")
        container.requestStates[requestID]?.revealAll()
        flushPendingUIUpdate(requestID: requestID, contentSource: .accumulated)
        cleanupFlushState(requestID: requestID)

        if let msgID = container.requestStates[requestID]?.assistantMessageID {
            try? persistence?.finalizeAssistantMessage(
                messageId: msgID.uuidString,
                content: container.requestStates[requestID]?.accumulatedText ?? "",
                status: .failed
            )
        }

        let errorMessage = ChatMessage(role: .assistant, content: "Error: \(errorDescription)")
        container.appendMessage(errorMessage, toConversation: owningConversationId)
        logger.info("[Request] Error message added to chat: \(errorDescription)")
        if !owningConversationId.isEmpty {
            try? persistence?.persistSystemMessage(
                errorMessage,
                conversationId: owningConversationId,
                status: .failed
            )
        }

        container.statusMessage = errorDescription
        schedulerState.runningSessions[requestID]?.streamTask?.cancel()
        schedulerState.runningSessions.removeValue(forKey: requestID)
        container.requestStates.removeValue(forKey: requestID)

        container.syncPublishedSchedulerState()
        container.scheduleIdlePrewarmFromCoordinator()
        advanceQueue()
    }
}

// MARK: - Request Execution

extension RequestCoordinator {
    private func resolveProvider(
        _ snapshot: QueueItemSnapshot
    ) -> (config: ProviderConfiguration, provider: any LLMProvider)? {
        guard let container else { return nil }
        let requestID = snapshot.id
        logger.info("[Request] Resolving provider: \(snapshot.providerID)")
        guard let config = container.settings.providerConfigurations.first(where: { $0.id == snapshot.providerID }) else {
            logger.error("[Request] Provider not found in configuration: \(snapshot.providerID)")
            failSession(requestID: requestID, error: .providerMissing(providerID: snapshot.providerID, providerName: nil))
            return nil
        }
        logger.info("[Request] Found provider config: \(config.name) (type: \(config.type.rawValue), enabled: \(config.isEnabled))")
        guard config.isEnabled else {
            logger.error("[Request] Provider is disabled: \(config.name)")
            failSession(requestID: requestID, error: .providerDisabled(providerID: snapshot.providerID, providerName: config.name))
            return nil
        }
        let provider = container.ensureProviderRegistered(for: config)
        logger.info("[Request] Provider resolved successfully: \(config.name)")
        return (config, provider)
    }

    private func resolveInvocationContext(
        config: ProviderConfiguration,
        providerID: String,
        requestID: RequestID
    ) -> ProviderInvocationContext? {
        logger.info("[Request] Resolving invocation context for: \(config.name)")
        var bearerToken: String?
        #if DEBUG
            let skipCredential = config.type == .mock
        #else
            let skipCredential = false
        #endif
        if !skipCredential {
            do {
                bearerToken = try credentialResolver.resolve(
                    providerID: providerID,
                    credentialRef: config.credentialRef
                )
                logger.info("[Request] Credential resolved successfully")
            } catch let error as CredentialResolutionError {
                logger.error("[Request] Credential resolution failed: \(error.errorDescription ?? "Unknown")")
                failSession(
                    requestID: requestID,
                    error: .credentialResolution(
                        providerID: providerID,
                        providerName: config.name,
                        message: error.errorDescription ?? "Unknown credential error"
                    )
                )
                return nil
            } catch {
                logger.error("[Request] Credential resolution failed: \(error.localizedDescription)")
                failSession(
                    requestID: requestID,
                    error: .credentialResolution(
                        providerID: providerID,
                        providerName: config.name,
                        message: error.localizedDescription
                    )
                )
                return nil
            }
        }
        logger.info("[Request] Invocation context created with endpoint: \(config.endpoint)")
        return ProviderInvocationContext(endpoint: config.endpoint, bearerToken: bearerToken)
    }

    private func executeRequest(_ snapshot: QueueItemSnapshot) async {
        guard let container else { return }
        let requestID = snapshot.id
        guard let (config, provider) = resolveProvider(snapshot) else { return }
        guard let invocationContext = resolveInvocationContext(
            config: config,
            providerID: snapshot.providerID,
            requestID: requestID
        ) else { return }

        let preflightTimeout = preflightTimeoutOverride ?? RuntimeConstants.preflightTimeout
        do {
            try await preflightModelValidation(
                provider: provider,
                modelID: snapshot.modelID,
                providerID: snapshot.providerID,
                providerName: config.name,
                settings: PreflightValidationSettings(
                    timeout: preflightTimeout,
                    invocationContext: invocationContext,
                    catalogRepository: container.catalogRepository
                )
            )
        } catch let error as RequestError {
            failSession(requestID: requestID, error: error)
            return
        } catch is CancellationError {
            return
        } catch {
            failSession(
                requestID: requestID,
                error: .remoteError(provider: snapshot.providerID, message: error.localizedDescription)
            )
            return
        }

        guard let reqState = container.requestStates[requestID], !reqState.isTerminal else { return }
        container.requestStates[requestID]?.status = .streaming

        let contextMessages = messagesForExecution(snapshot: snapshot)

        let stream = provider.sendStreaming(
            messages: contextMessages,
            modelID: snapshot.modelID,
            parameters: snapshot.parameters,
            requestID: requestID,
            context: invocationContext
        )
        await consumeStream(stream, requestID: requestID, providerID: snapshot.providerID)
    }

    private func preflightModelValidation(
        provider: any LLMProvider,
        modelID: String,
        providerID: String,
        providerName: String?,
        settings: PreflightValidationSettings
    ) async throws {
        logger.info("[Preflight] Validating model '\(modelID)' for provider '\(providerName ?? providerID)'")
        if let repo = settings.catalogRepository {
            do {
                let status = try repo.refreshStatus(forProviderID: providerID)
                logger.info("[Preflight] Catalog cache status: hasUsableCache=\(status.hasUsableCache)")

                if status.hasUsableCache {
                    let cachedModels = try repo.models(forProviderID: providerID)
                    logger.info("[Preflight] Found \(cachedModels.count) cached models")
                    if cachedModels.contains(where: { $0.id == modelID }) {
                        logger.info("[Preflight] Model validation passed (from cache)")
                        return
                    } else {
                        logger.error("[Preflight] Model '\(modelID)' not found in cached models")
                        throw RequestError.modelInvalid(modelID: modelID, providerID: providerID, providerName: providerName)
                    }
                } else {
                    logger.info("[Preflight] No usable cache, falling back to live validation")
                }
            } catch let error as RequestError {
                throw error
            } catch {
                logger.info("[Preflight] Cache check failed: \(error.localizedDescription), falling back to live validation")
            }
        } else {
            logger.info("[Preflight] No catalog repository, using live validation")
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let models = try await provider.availableModels(context: settings.invocationContext)
                guard models.contains(where: { $0.id == modelID }) else {
                    throw RequestError.modelInvalid(modelID: modelID, providerID: providerID, providerName: providerName)
                }
            }
            group.addTask { [timeout = settings.timeout] in
                try await Task.sleep(for: timeout)
                let (sec, atto) = timeout.components
                let totalSeconds = Double(sec) + Double(atto) * 1e-18
                throw RequestError.preflightTimeout(seconds: totalSeconds)
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func isNonTerminalSession(requestID: RequestID) -> Bool {
        guard let container else { return false }
        guard let state = container.requestStates[requestID] else { return false }
        return !state.isTerminal
    }

    private struct PreflightValidationSettings {
        let timeout: Duration
        let invocationContext: ProviderInvocationContext
        let catalogRepository: (any ProviderCatalogRepository)?
    }

    private func durationSeconds(_ duration: Duration) -> Double {
        let (sec, atto) = duration.components
        return Double(sec) + Double(atto) * 1e-18
    }

    private func makeGenerationTimeoutTask(
        requestID: RequestID,
        timeout: Duration
    ) -> Task<Void, Never> {
        Task { [weak self, timeout] in
            guard let self else { return }
            do {
                try await Task.sleep(for: timeout)
                guard self.isNonTerminalSession(requestID: requestID) else { return }
                self.failSession(
                    requestID: requestID,
                    error: .generationTimeout(seconds: self.durationSeconds(timeout))
                )
            } catch {
                // Cancelled
            }
        }
    }

    private func handleStreamEvent(
        _ event: StreamEvent,
        requestID: RequestID,
        providerID _: String
    ) -> Bool {
        switch event {
        case let .started(rid) where rid == requestID:
            return false
        case let .delta(rid, text) where rid == requestID:
            handleDelta(requestID: requestID, text: text)
            return false
        case let .completed(rid) where rid == requestID:
            beginTerminalCompletion(requestID: requestID)
            return true
        case let .failed(rid, error) where rid == requestID:
            failSession(requestID: requestID, error: error)
            return true
        default:
            return false
        }
    }

    private func consumeStream(
        _ stream: AsyncThrowingStream<StreamEvent, Error>,
        requestID: RequestID,
        providerID: String
    ) async {
        let genTimeout = generationTimeoutOverride ?? RuntimeConstants.generationTimeout
        let timeoutTask = makeGenerationTimeoutTask(requestID: requestID, timeout: genTimeout)
        defer { timeoutTask.cancel() }
        do {
            for try await event in stream {
                guard isNonTerminalSession(requestID: requestID) else { break }
                if handleStreamEvent(event, requestID: requestID, providerID: providerID) {
                    return
                }
            }
            if isNonTerminalSession(requestID: requestID) {
                beginTerminalCompletion(requestID: requestID)
            }
        } catch is CancellationError {
            // Stop or timeout already handled
        } catch {
            if isNonTerminalSession(requestID: requestID) {
                failSession(
                    requestID: requestID,
                    error: .remoteError(provider: providerID, message: error.localizedDescription)
                )
            }
        }
    }

    private func beginTerminalCompletion(requestID: RequestID) {
        guard let container else { return }
        guard let state = container.requestStates[requestID],
              !state.isTerminal
        else { return }

        guard !state.accumulatedText.isEmpty else {
            completeSession(requestID: requestID)
            return
        }

        guard state.pendingPresentedCharacterCount > 0 else {
            completeSession(requestID: requestID)
            return
        }

        guard let flushState = sessionFlushState[requestID] else {
            completeSession(requestID: requestID)
            return
        }

        flushState.terminalCatchUpStartedAt = ContinuousClock.now
        flushState.pendingRevealTask?.cancel()
        flushState.pendingRevealTask = nil
        ensureRevealLoopRunning(requestID: requestID)
    }
}

// MARK: - Delta Handling

extension RequestCoordinator {
    private func handleDelta(requestID: RequestID, text: String) {
        guard let container else { return }
        guard container.requestStates[requestID] != nil else { return }
        let owningConversationId = container.requestStates[requestID]!.conversationId
        let isActiveConversation = owningConversationId == container.activeConversationId

        if !isActiveConversation {
            container.markUnreadCompletion(forConversation: owningConversationId)
        }

        container.requestStates[requestID]?.appendDelta(text)
        let accumulated = container.requestStates[requestID]?.flushText() ?? ""

        if let msgID = container.requestStates[requestID]?.assistantMessageID {
            ensureRevealLoopRunning(requestID: requestID)
            throttledStreamingFlush(requestID: requestID, messageId: msgID.uuidString, content: accumulated)
            return
        }

        let initialPresented = primePresentedContent(requestID: requestID)
        let newMessage = ChatMessage(role: .assistant, content: initialPresented)
        container.requestStates[requestID]?.assistantMessageID = newMessage.id
        container.appendMessage(newMessage, toConversation: owningConversationId)

        if let flushState = sessionFlushState[requestID] {
            flushState.lastRevealAt = ContinuousClock.now
            flushState.lastUIFlush = ContinuousClock.now
            flushState.latestPresentedLength = initialPresented.count
        }

        if !owningConversationId.isEmpty {
            let persistedDraft = ChatMessage(
                id: newMessage.id,
                role: .assistant,
                content: accumulated,
                createdAt: newMessage.createdAt
            )
            try? persistence?.persistAssistantDraft(
                persistedDraft,
                conversationId: owningConversationId,
                requestId: requestID.value.uuidString
            )
        }

        ensureRevealLoopRunning(requestID: requestID)
        throttledStreamingFlush(requestID: requestID, messageId: newMessage.id.uuidString, content: accumulated)
    }
}

// MARK: - Streaming Throttle (Per-Session)

private enum StreamingContentSource {
    case presented
    case accumulated
}

private final class SessionFlushState {
    static let streamingFlushInterval: Duration = .milliseconds(500)
    var lastFastFlush: ContinuousClock.Instant?
    var pendingFastFlush: Task<Void, Never>?
    var lastUIFlush: ContinuousClock.Instant?
    var pendingUIFlush: Task<Void, Never>?
    var lastStreamingFlush: ContinuousClock.Instant?
    var pendingStreamingFlush: Task<Void, Never>?
    var pendingRevealTask: Task<Void, Never>?
    var lastRevealAt: ContinuousClock.Instant?
    var revealBudget: Double = 0
    var terminalCatchUpStartedAt: ContinuousClock.Instant?
    var latestPresentedLength: Int = 0
}

extension RequestCoordinator {
    private func primePresentedContent(requestID: RequestID) -> String {
        guard let container else { return "" }
        guard var state = container.requestStates[requestID] else { return "" }

        let revealCharacters = min(
            streamingPresentationPolicy.initialRevealCharacters,
            state.pendingPresentedCharacterCount
        )
        let presented: String
        if revealCharacters > 0 {
            presented = state.revealBy(characters: revealCharacters)
        } else {
            presented = state.presentedText
        }

        container.requestStates[requestID] = state
        return presented
    }

    private func applyFastFlush(
        requestID: RequestID,
        conversationId: String,
        messageID: UUID,
        content: String
    ) {
        guard let container, container.activeConversationId == conversationId else { return }
        container.pushStreamingContent(
            conversationId: conversationId,
            messageID: messageID,
            content: content
        )
        sessionFlushState[requestID]?.lastFastFlush = ContinuousClock.now
    }

    private func currentContent(
        for requestID: RequestID,
        source: StreamingContentSource
    ) -> String {
        guard let container else { return "" }
        guard let reqState = container.requestStates[requestID] else { return "" }
        switch source {
        case .presented:
            return reqState.presentedText
        case .accumulated:
            return reqState.accumulatedText
        }
    }

    private func revealCharactersPerSecond(for requestID: RequestID) -> Double {
        guard let container else { return 0 }
        guard let flushState = sessionFlushState[requestID] else { return 0 }
        let pendingCharacters = container.requestStates[requestID]?.pendingPresentedCharacterCount ?? 0
        return streamingPresentationPolicy.charactersPerSecond(
            forPendingCharacters: pendingCharacters,
            isTerminalCatchUp: flushState.terminalCatchUpStartedAt != nil
        )
    }

    private func ensureRevealLoopRunning(requestID: RequestID) {
        guard let container else { return }
        guard let flushState = sessionFlushState[requestID],
              flushState.pendingRevealTask == nil,
              let state = container.requestStates[requestID],
              state.pendingPresentedCharacterCount > 0
        else { return }

        flushState.lastRevealAt = ContinuousClock.now
        flushState.revealBudget = 0
        flushState.pendingRevealTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.sessionFlushState[requestID]?.pendingRevealTask = nil
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: self.streamingPresentationPolicy.revealTickInterval)
                guard !Task.isCancelled else { return }
                guard self.performRevealTick(requestID: requestID) else { return }
            }
        }
    }

    @discardableResult
    private func performRevealTick(requestID: RequestID) -> Bool {
        guard let container else { return false }
        guard let flushState = sessionFlushState[requestID],
              var state = container.requestStates[requestID]
        else { return false }

        let now = ContinuousClock.now

        if let startedAt = flushState.terminalCatchUpStartedAt,
           let forceRevealAfter = streamingPresentationPolicy.terminalForceRevealAfter,
           now - startedAt >= forceRevealAfter
        {
            state.revealAll()
            container.requestStates[requestID] = state
            completeSession(requestID: requestID)
            return false
        }

        let elapsed: Duration
        if let lastRevealAt = flushState.lastRevealAt {
            elapsed = now - lastRevealAt
        } else {
            elapsed = streamingPresentationPolicy.revealTickInterval
        }
        flushState.lastRevealAt = now

        let revealCharactersPerSecond = revealCharactersPerSecond(for: requestID)
        guard revealCharactersPerSecond > 0 else { return false }

        flushState.revealBudget += durationSeconds(elapsed) * revealCharactersPerSecond
        let revealCharacters = min(
            state.pendingPresentedCharacterCount,
            Int(flushState.revealBudget.rounded(.towardZero))
        )
        guard revealCharacters > 0 else {
            return state.pendingPresentedCharacterCount > 0
        }
        flushState.revealBudget = max(0, flushState.revealBudget - Double(revealCharacters))

        let presented = state.revealBy(characters: revealCharacters)
        let hasPendingCharacters = state.pendingPresentedCharacterCount > 0
        container.requestStates[requestID] = state

        if hasPendingCharacters || flushState.terminalCatchUpStartedAt == nil {
            publishPresentedContent(requestID: requestID, content: presented)
        }

        if !hasPendingCharacters, flushState.terminalCatchUpStartedAt != nil {
            completeSession(requestID: requestID)
            return false
        }

        return hasPendingCharacters
    }

    private func publishPresentedContent(requestID: RequestID, content: String) {
        guard let container else { return }
        guard let reqState = container.requestStates[requestID],
              let messageID = reqState.assistantMessageID,
              let index = container.messagesForConversation(reqState.conversationId).lastIndex(where: { $0.id == messageID })
        else { return }

        let contentLength = content.count
        if sessionFlushState[requestID]?.latestPresentedLength == contentLength {
            return
        }
        sessionFlushState[requestID]?.latestPresentedLength = contentLength

        applyFastFlush(
            requestID: requestID,
            conversationId: reqState.conversationId,
            messageID: messageID,
            content: content
        )
        throttledUIFlush(
            requestID: requestID,
            conversationId: reqState.conversationId,
            index: index,
            contentSource: .presented
        )
    }

    private func throttledUIFlush(
        requestID: RequestID,
        conversationId: String,
        index: Int,
        contentSource: StreamingContentSource
    ) {
        guard let flushState = sessionFlushState[requestID] else { return }
        let now = ContinuousClock.now
        let interval = RenderConstants.streamingSlowFlushInterval
        if let lastFlush = flushState.lastUIFlush, now - lastFlush < interval {
            if flushState.pendingUIFlush == nil {
                flushState.pendingUIFlush = Task { @MainActor [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled else { return }
                    self.applyUIFlush(
                        requestID: requestID,
                        conversationId: conversationId,
                        contentSource: contentSource
                    )
                    self.sessionFlushState[requestID]?.pendingUIFlush = nil
                }
            }
        } else {
            guard let container else { return }
            flushState.pendingUIFlush?.cancel()
            flushState.pendingUIFlush = nil
            let content = currentContent(for: requestID, source: contentSource)
            container.updateMessage(at: index, inConversation: conversationId, content: content)
            flushState.lastUIFlush = now
        }
    }

    private func applyUIFlush(
        requestID: RequestID,
        conversationId: String,
        contentSource: StreamingContentSource
    ) {
        guard let container else { return }
        guard let reqState = container.requestStates[requestID],
              let msgID = reqState.assistantMessageID,
              let index = container.messagesForConversation(conversationId).lastIndex(where: { $0.id == msgID })
        else { return }
        let content = currentContent(for: requestID, source: contentSource)
        container.updateMessage(at: index, inConversation: conversationId, content: content)
        sessionFlushState[requestID]?.lastUIFlush = ContinuousClock.now
    }

    private func flushPendingUIUpdate(
        requestID: RequestID,
        contentSource: StreamingContentSource = .presented
    ) {
        guard let container else { return }
        guard let flushState = sessionFlushState[requestID] else { return }
        flushState.pendingRevealTask?.cancel()
        flushState.pendingRevealTask = nil
        flushState.lastRevealAt = nil
        flushState.revealBudget = 0
        flushState.terminalCatchUpStartedAt = nil
        flushState.pendingFastFlush?.cancel()
        flushState.pendingFastFlush = nil
        if let reqState = container.requestStates[requestID],
           let messageID = reqState.assistantMessageID
        {
            let content = currentContent(for: requestID, source: contentSource)
            applyFastFlush(
                requestID: requestID,
                conversationId: reqState.conversationId,
                messageID: messageID,
                content: content
            )
            flushState.latestPresentedLength = content.count
        }

        flushState.pendingUIFlush?.cancel()
        flushState.pendingUIFlush = nil
        if let reqState = container.requestStates[requestID] {
            applyUIFlush(
                requestID: requestID,
                conversationId: reqState.conversationId,
                contentSource: contentSource
            )
        }
    }

    private func throttledStreamingFlush(requestID: RequestID, messageId: String, content _: String) {
        guard let container else { return }
        guard let flushState = sessionFlushState[requestID] else { return }
        let now = ContinuousClock.now
        let interval = SessionFlushState.streamingFlushInterval
        if let lastFlush = flushState.lastStreamingFlush, now - lastFlush < interval {
            flushState.pendingStreamingFlush?.cancel()
            flushState.pendingStreamingFlush = Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                let currentContent = self.container?.requestStates[requestID]?.accumulatedText ?? ""
                try? self.persistence?.updateStreamingContent(
                    messageId: messageId,
                    content: currentContent
                )
                self.sessionFlushState[requestID]?.lastStreamingFlush = ContinuousClock.now
            }
        } else {
            flushState.pendingStreamingFlush?.cancel()
            flushState.pendingStreamingFlush = nil
            let currentContent = container.requestStates[requestID]?.accumulatedText ?? ""
            try? persistence?.updateStreamingContent(
                messageId: messageId,
                content: currentContent
            )
            flushState.lastStreamingFlush = now
        }
    }

    private func cleanupFlushState(requestID: RequestID) {
        if let flushState = sessionFlushState.removeValue(forKey: requestID) {
            flushState.pendingFastFlush?.cancel()
            flushState.pendingUIFlush?.cancel()
            flushState.pendingStreamingFlush?.cancel()
            flushState.pendingRevealTask?.cancel()
            flushState.lastRevealAt = nil
            flushState.revealBudget = 0
        }
    }

    func cancelThrottleTasksForConversation(_ conversationId: String) {
        guard let container else { return }
        let matchingRequestIDs = sessionFlushState.keys.filter { requestID in
            container.requestStates[requestID]?.conversationId == conversationId
        }
        for requestID in matchingRequestIDs {
            if let flushState = sessionFlushState[requestID] {
                flushState.pendingFastFlush?.cancel()
                flushState.pendingFastFlush = nil
                flushState.pendingUIFlush?.cancel()
                flushState.pendingUIFlush = nil
                flushState.pendingStreamingFlush?.cancel()
                flushState.pendingStreamingFlush = nil
            }
        }
    }
}

// MARK: - Testing Support

#if DEBUG
    extension RequestCoordinator {
        func hasPendingThrottleTasksForConversation(_ conversationId: String) -> Bool {
            guard let container else { return false }
            return sessionFlushState.contains { requestID, flushState in
                container.requestStates[requestID]?.conversationId == conversationId
                    && (flushState.pendingFastFlush != nil
                        || flushState.pendingUIFlush != nil
                        || flushState.pendingStreamingFlush != nil)
            }
        }
    }
#endif

// MARK: - Queue Management

extension RequestCoordinator {
    func advanceQueue() {
        guard let container else { return }
        while let selection = RequestScheduler.selectNext(
            state: &schedulerState,
            activeConversationId: container.activeConversationId
        ) {
            startSession(selection.snapshot)
        }
        container.syncPublishedSchedulerState()
    }

    private func messagesForExecution(snapshot: QueueItemSnapshot) -> [ChatMessage] {
        guard let container else { return [] }
        let bucket = container.messagesForConversation(snapshot.conversationId)
        guard let index = bucket.firstIndex(where: { $0.id == snapshot.userMessageID }) else {
            return applyContextLimit(bucket, limit: snapshot.parameters.contextMessageLimit)
        }
        let relevantMessages = Array(bucket[...index])
        return applyContextLimit(relevantMessages, limit: snapshot.parameters.contextMessageLimit)
    }

    private func applyContextLimit(_ messages: [ChatMessage], limit: Int?) -> [ChatMessage] {
        guard let limit = limit, limit > 0, messages.count > limit else {
            return messages
        }
        return Array(messages.suffix(limit))
    }
}
