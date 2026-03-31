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
    private let messageAssetStore: (any MessageAssetStore)?

    // MARK: - Scheduler State

    private(set) var schedulerState = SchedulerState()

    // MARK: - Per-Session Stream State

    private var sessionFlushState: [RequestID: SessionFlushState] = [:]
    private var sessionSnapshots: [RequestID: QueueItemSnapshot] = [:]
    private var sessionDebugInfo: [RequestID: MessageDebugInfo] = [:]

    // MARK: - Testing Overrides

    var preflightTimeoutOverride: Duration?
    var generationTimeoutOverride: Duration?
    var streamingPresentationPolicyOverride: StreamingPresentationPolicy?

    // MARK: - Init

    init(
        container: AppContainer,
        persistence: ChatPersistenceCoordinator?,
        credentialResolver: CredentialResolver,
        messageAssetStore: (any MessageAssetStore)?
    ) {
        self.container = container
        self.persistence = persistence
        self.credentialResolver = credentialResolver
        self.messageAssetStore = messageAssetStore
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
        sessionSnapshots.removeAll()
        sessionDebugInfo.removeAll()
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

    private func shouldPersistConversation(for requestID: RequestID) -> Bool {
        sessionSnapshots[requestID]?.persistenceBehavior == .persistent
    }

    private func shouldPersistConversation(for snapshot: QueueItemSnapshot) -> Bool {
        snapshot.persistenceBehavior == .persistent
    }
}

// MARK: - Message Trace

extension RequestCoordinator {
    private func initializeDebugInfo(for snapshot: QueueItemSnapshot) {
        sessionDebugInfo[snapshot.id] = MessageDebugInfo(
            requestID: snapshot.id.description,
            providerID: snapshot.providerID,
            modelID: snapshot.modelID,
            traceEvents: [
                makeTraceEvent(
                    category: .lifecycle,
                    title: "User message queued",
                    summary: "Queued request for provider \(snapshot.providerID)",
                    sections: traceSections([
                        ("Prompt", trimmedDebugPreview(snapshot.prompt))
                    ])
                )
            ]
        )
        syncDebugInfoToMessages(requestID: snapshot.id)
    }

    private func mergeDebugInfo(
        _ debugInfo: MessageDebugInfo,
        for requestID: RequestID
    ) {
        mutateDebugInfo(for: requestID) { current in
            current = current.merged(with: debugInfo)
        }
    }

    private func appendTraceEvent(
        for requestID: RequestID,
        category: MessageTraceEventCategory,
        title: String,
        summary: String? = nil,
        sections: [MessageTraceSection] = []
    ) {
        mutateDebugInfo(for: requestID) { current in
            current = current.appendingTraceEvent(
                makeTraceEvent(
                    category: category,
                    title: title,
                    summary: summary,
                    sections: sections
                )
            )
        }
    }

    private func mutateDebugInfo(
        for requestID: RequestID,
        _ mutate: (inout MessageDebugInfo) -> Void
    ) {
        guard var current = sessionDebugInfo[requestID]
            ?? (sessionSnapshots[requestID] != nil ? MessageDebugInfo() : nil)
        else {
            return
        }
        mutate(&current)
        sessionDebugInfo[requestID] = current
        syncDebugInfoToMessages(requestID: requestID)
    }

    private func syncDebugInfoToMessages(requestID: RequestID) {
        guard let container,
              let snapshot = sessionSnapshots[requestID],
              let debugInfo = sessionDebugInfo[requestID]
        else {
            return
        }
        let debugInfoJSON = debugInfo.prettyJSONString()
        var messageIDs: [UUID] = [snapshot.userMessageID]
        if let assistantMessageID = container.requestStates[requestID]?.assistantMessageID {
            messageIDs.append(assistantMessageID)
        }
        let uniqueMessageIDs = Array(Set(messageIDs))
        container.updateMessagesDebugInfo(
            uniqueMessageIDs,
            inConversation: snapshot.conversationId,
            debugInfoJSON: debugInfoJSON
        )
        if shouldPersistConversation(for: requestID) {
            for messageID in uniqueMessageIDs {
                try? persistence?.updateMessageDebugInfo(
                    messageId: messageID.uuidString,
                    debugInfoJSON: debugInfoJSON
                )
            }
        }
    }

    private func currentDebugInfoJSON(for requestID: RequestID) -> String? {
        sessionDebugInfo[requestID]?.prettyJSONString()
    }

    private func finalizedDebugInfoJSON(
        for requestID: RequestID,
        errorDescription: String,
        fallbackJSON: String?
    ) -> String? {
        if let fallback = MessageDebugInfo.decode(from: fallbackJSON) {
            mergeDebugInfo(fallback, for: requestID)
        }

        mutateDebugInfo(for: requestID) { current in
            current.providerError = errorDescription
            current = current.appendingTraceEvent(
                makeTraceEvent(
                    category: .error,
                    title: "Request failed",
                    summary: errorDescription
                )
            )
        }

        return currentDebugInfoJSON(for: requestID) ?? fallbackJSON
    }

    private func makeTraceEvent(
        category: MessageTraceEventCategory,
        title: String,
        summary: String? = nil,
        sections: [MessageTraceSection] = []
    ) -> MessageTraceEvent {
        MessageTraceEvent(
            category: category,
            title: title,
            summary: summary,
            sections: sections
        )
    }

    private func traceSections(_ pairs: [(String, String?)]) -> [MessageTraceSection] {
        pairs.compactMap { title, content in
            guard let content, !content.isEmpty else { return nil }
            return MessageTraceSection(title: title, content: content)
        }
    }
}

// MARK: - Message Trace

extension RequestCoordinator {
    private func initializeDebugInfo(for snapshot: QueueItemSnapshot) {
        sessionDebugInfo[snapshot.id] = MessageDebugInfo(
            requestID: snapshot.id.description,
            providerID: snapshot.providerID,
            modelID: snapshot.modelID,
            traceEvents: [
                makeTraceEvent(
                    category: .lifecycle,
                    title: "User message queued",
                    summary: "Queued request for provider \(snapshot.providerID)",
                    sections: traceSections([
                        ("Prompt", trimmedDebugPreview(snapshot.prompt))
                    ])
                )
            ]
        )
        syncDebugInfoToMessages(requestID: snapshot.id)
    }

    private func mergeDebugInfo(
        _ debugInfo: MessageDebugInfo,
        for requestID: RequestID
    ) {
        mutateDebugInfo(for: requestID) { current in
            current = current.merged(with: debugInfo)
        }
    }

    private func appendTraceEvent(
        for requestID: RequestID,
        category: MessageTraceEventCategory,
        title: String,
        summary: String? = nil,
        sections: [MessageTraceSection] = []
    ) {
        mutateDebugInfo(for: requestID) { current in
            current = current.appendingTraceEvent(
                makeTraceEvent(
                    category: category,
                    title: title,
                    summary: summary,
                    sections: sections
                )
            )
        }
    }

    private func mutateDebugInfo(
        for requestID: RequestID,
        _ mutate: (inout MessageDebugInfo) -> Void
    ) {
        guard var current = sessionDebugInfo[requestID]
            ?? (sessionSnapshots[requestID] != nil ? MessageDebugInfo() : nil)
        else {
            return
        }
        mutate(&current)
        sessionDebugInfo[requestID] = current
        syncDebugInfoToMessages(requestID: requestID)
    }

    private func syncDebugInfoToMessages(requestID: RequestID) {
        guard let container,
              let snapshot = sessionSnapshots[requestID],
              let debugInfo = sessionDebugInfo[requestID]
        else {
            return
        }
        let debugInfoJSON = debugInfo.prettyJSONString()
        var messageIDs: [UUID] = [snapshot.userMessageID]
        if let assistantMessageID = container.requestStates[requestID]?.assistantMessageID {
            messageIDs.append(assistantMessageID)
        }
        let uniqueMessageIDs = Array(Set(messageIDs))
        container.updateMessagesDebugInfo(
            uniqueMessageIDs,
            inConversation: snapshot.conversationId,
            debugInfoJSON: debugInfoJSON
        )
        for messageID in uniqueMessageIDs {
            try? persistence?.updateMessageDebugInfo(
                messageId: messageID.uuidString,
                debugInfoJSON: debugInfoJSON
            )
        }
    }

    private func currentDebugInfoJSON(for requestID: RequestID) -> String? {
        sessionDebugInfo[requestID]?.prettyJSONString()
    }

    private func finalizedDebugInfoJSON(
        for requestID: RequestID,
        errorDescription: String,
        fallbackJSON: String?
    ) -> String? {
        if let fallback = MessageDebugInfo.decode(from: fallbackJSON) {
            mergeDebugInfo(fallback, for: requestID)
        }

        mutateDebugInfo(for: requestID) { current in
            current.providerError = errorDescription
            current = current.appendingTraceEvent(
                makeTraceEvent(
                    category: .error,
                    title: "Request failed",
                    summary: errorDescription
                )
            )
        }

        return currentDebugInfoJSON(for: requestID) ?? fallbackJSON
    }

    private func makeTraceEvent(
        category: MessageTraceEventCategory,
        title: String,
        summary: String? = nil,
        sections: [MessageTraceSection] = []
    ) -> MessageTraceEvent {
        MessageTraceEvent(
            category: category,
            title: title,
            summary: summary,
            sections: sections
        )
    }

    private func traceSections(_ pairs: [(String, String?)]) -> [MessageTraceSection] {
        pairs.compactMap { title, content in
            guard let content, !content.isEmpty else { return nil }
            return MessageTraceSection(title: title, content: content)
        }
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
        sessionSnapshots[snapshot.id] = snapshot
        sessionFlushState[snapshot.id] = SessionFlushState()
        initializeDebugInfo(for: snapshot)
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

        appendTraceEvent(
            for: requestID,
            category: .lifecycle,
            title: "Request stopped",
            summary: "Stopped before the provider finished responding"
        )
        let stoppedDebugInfoJSON = currentDebugInfoJSON(for: requestID)

        container.requestStates[requestID]?.status = .stopped
        container.requestStates[requestID]?.revealAll()
        flushPendingUIUpdate(requestID: requestID, contentSource: .accumulated)
        cleanupFlushState(requestID: requestID)

        if shouldPersistConversation(for: requestID),
           let msgID = container.requestStates[requestID]?.assistantMessageID
        {
            try? persistence?.finalizeAssistantMessage(
                messageId: msgID.uuidString,
                content: container.requestStates[requestID]?.accumulatedText ?? "",
                status: .stopped
            )
        }
        if !hadContent {
            let stoppedMessage = ChatMessage(
                role: .assistant,
                content: "[Request stopped]",
                debugInfoJSON: stoppedDebugInfoJSON
            )
            container.appendMessage(stoppedMessage, toConversation: owningConversationId)
            if shouldPersistConversation(for: requestID), !owningConversationId.isEmpty {
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
        let flushState = sessionFlushState[requestID]

        appendTraceEvent(
            for: requestID,
            category: .response,
            title: "Response completed",
            summary: "Received \(state.accumulatedText.count) characters",
            sections: traceSections([
                ("SSE Delta Count", flushState.map { String($0.deltaChunkCount) }),
                ("Delta Preview", trimmedDebugPreview(flushState?.deltaPreview)),
                ("Assistant Preview", trimmedDebugPreview(state.accumulatedText))
            ])
        )

        container.requestStates[requestID]?.status = .completed
        container.requestStates[requestID]?.revealAll()
        flushPendingUIUpdate(requestID: requestID, contentSource: .accumulated)
        cleanupFlushState(requestID: requestID)

        if shouldPersistConversation(for: requestID),
           let msgID = container.requestStates[requestID]?.assistantMessageID
        {
            try? persistence?.finalizeAssistantMessage(
                messageId: msgID.uuidString,
                content: container.requestStates[requestID]?.accumulatedText ?? "",
                status: .completed
            )
        }

        let isBackground = owningConversationId != container.activeConversationId
        let finalAssistantContent = state.accumulatedText
        if isBackground, shouldPersistConversation(for: requestID) {
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

    private func failSession(
        requestID: RequestID,
        error: RequestError,
        debugInfoJSON: String? = nil
    ) {
        guard let container else { return }
        guard let state = container.requestStates[requestID],
              !state.isTerminal else { return }
        let owningConversationId = state.conversationId
        let errorDescription = error.errorDescription ?? "Unknown error"
        let resolvedDebugInfoJSON = finalizedDebugInfoJSON(
            for: requestID,
            errorDescription: errorDescription,
            fallbackJSON: debugInfoJSON
        )

        container.requestStates[requestID]?.status = .failed(error)
        logger.error("[Request] Request failed: \(errorDescription)")
        container.requestStates[requestID]?.revealAll()
        flushPendingUIUpdate(requestID: requestID, contentSource: .accumulated)
        cleanupFlushState(requestID: requestID)

        if shouldPersistConversation(for: requestID),
           let msgID = container.requestStates[requestID]?.assistantMessageID
        {
            try? persistence?.finalizeAssistantMessage(
                messageId: msgID.uuidString,
                content: container.requestStates[requestID]?.accumulatedText ?? "",
                status: .failed
            )
        }

        let errorMessage = ChatMessage(
            role: .assistant,
            content: "Error: \(errorDescription)",
            debugInfoJSON: resolvedDebugInfoJSON
        )
        container.appendMessage(errorMessage, toConversation: owningConversationId)
        logger.info("[Request] Error message added to chat: \(errorDescription)")
        if shouldPersistConversation(for: requestID), !owningConversationId.isEmpty {
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
        appendTraceEvent(
            for: requestID,
            category: .lifecycle,
            title: "Provider resolved",
            summary: "Using provider \(config.name)",
            sections: traceSections([
                ("Provider ID", config.id),
                ("Provider Type", config.type.rawValue)
            ])
        )
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
                    apiKey: config.apiKey
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
        mutateDebugInfo(for: requestID) { current in
            current.endpoint = config.endpoint
            current = current.appendingTraceEvent(
                makeTraceEvent(
                    category: .lifecycle,
                    title: "Invocation context ready",
                    summary: "Resolved endpoint and credentials",
                    sections: traceSections([
                        ("Endpoint", config.endpoint),
                        ("Credential", skipCredential ? "Skipped in debug for mock provider" : "Resolved bearer token")
                    ])
                )
            )
        }
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
        let modelDescriptor: ModelDescriptor
        do {
            modelDescriptor = try await preflightModelValidation(
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
        let routeOutputs = modelDescriptor.supportedOutputs.map(\.rawValue).joined(separator: ",")
        let routeLogMessage =
            "[Request] Model route decision: model=\(snapshot.modelID), "
                + "type=\(modelDescriptor.modelType.rawValue), outputs=\(routeOutputs)"
        logger.info("\(routeLogMessage, privacy: .public)")
        mutateDebugInfo(for: requestID) { current in
            let supportedOutputs = modelDescriptor.supportedOutputs.map(\.rawValue)
            let requestKind = self.modelProducesImageOutput(modelDescriptor) ? "image_generation" : "chat_completion"
            let routeTarget = requestKind == "image_generation"
                ? "provider.send"
                : "provider.sendStreaming"
            current.requestKind = requestKind
            current.routeDecision =
                "RequestCoordinator routed to \(routeTarget) because "
                    + "modelType=\(modelDescriptor.modelType.rawValue) and "
                    + "supportedOutputs=\(supportedOutputs.joined(separator: ","))"
            current.descriptorModelType = modelDescriptor.modelType.rawValue
            current.descriptorSupportedOutputs = supportedOutputs
            current.descriptorRawMetadataJSON = self.trimmedDebugPreview(modelDescriptor.rawMetadataJSON)
            current = current.appendingTraceEvent(
                makeTraceEvent(
                    category: .lifecycle,
                    title: "Model validated",
                    summary: "Resolved \(modelDescriptor.modelType.rawValue) model",
                    sections: traceSections([
                        ("Model ID", snapshot.modelID),
                        ("Model Type", modelDescriptor.modelType.rawValue),
                        ("Supported Outputs", supportedOutputs.joined(separator: ", ")),
                        ("Route Decision", current.routeDecision)
                    ])
                )
            )
        }

        let contextMessages = messagesForExecution(snapshot: snapshot)

        if modelProducesImageOutput(modelDescriptor) {
            logger.info("[Request] Routing image-capable model '\(snapshot.modelID)' through provider.send(...)")
            await executeImageRequest(
                snapshot: snapshot,
                provider: provider,
                modelDescriptor: modelDescriptor,
                contextMessages: contextMessages,
                context: invocationContext
            )
            return
        }

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
    ) async throws -> ModelDescriptor {
        logger.info("[Preflight] Validating model '\(modelID)' for provider '\(providerName ?? providerID)'")
        if let repo = settings.catalogRepository {
            do {
                let status = try repo.refreshStatus(forProviderID: providerID)
                logger.info("[Preflight] Catalog cache status: hasUsableCache=\(status.hasUsableCache)")

                if status.hasUsableCache {
                    let cachedModels = try repo.models(forProviderID: providerID)
                    logger.info("[Preflight] Found \(cachedModels.count) cached models")
                    if let model = cachedModels.first(where: { $0.id == modelID }) {
                        logger.info("[Preflight] Model validation passed (from cache)")
                        return model
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

        return try await withThrowingTaskGroup(of: ModelDescriptor.self) { group in
            group.addTask {
                let models = try await provider.availableModels(context: settings.invocationContext)
                guard let model = models.first(where: { $0.id == modelID }) else {
                    throw RequestError.modelInvalid(modelID: modelID, providerID: providerID, providerName: providerName)
                }
                return model
            }
            group.addTask { [timeout = settings.timeout] in
                try await Task.sleep(for: timeout)
                let (sec, atto) = timeout.components
                let totalSeconds = Double(sec) + Double(atto) * 1e-18
                throw RequestError.preflightTimeout(seconds: totalSeconds)
            }
            guard let result = try await group.next() else {
                throw RequestError.remoteError(provider: providerID, message: "Model preflight produced no result")
            }
            group.cancelAll()
            return result
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

    private func modelProducesImageOutput(_ descriptor: ModelDescriptor) -> Bool {
        descriptor.modelType == .image || descriptor.supportedOutputs.contains(.image)
    }

    private func executeImageRequest(
        snapshot: QueueItemSnapshot,
        provider: any LLMProvider,
        modelDescriptor: ModelDescriptor,
        contextMessages: [ChatMessage],
        context: ProviderInvocationContext
    ) async {
        guard let container else { return }
        let requestID = snapshot.id
        let baseDebugInfo = makeImageRequestDebugInfo(
            snapshot: snapshot,
            modelDescriptor: modelDescriptor,
            context: context
        )
        mergeDebugInfo(baseDebugInfo, for: requestID)

        let imageTimeout = generationTimeoutOverride ?? RuntimeConstants.imageGenerationTimeout
        let timeoutTask = makeGenerationTimeoutTask(requestID: requestID, timeout: imageTimeout)
        defer { timeoutTask.cancel() }

        let imageTimeoutSec = durationSeconds(imageTimeout)
        logger.info("[Image] Starting image generation: model=\(snapshot.modelID), timeout=\(imageTimeoutSec)s")
        let startTime = ContinuousClock.now

        do {
            let response = try await provider.send(
                messages: contextMessages,
                modelID: snapshot.modelID,
                parameters: snapshot.parameters,
                context: context
            )
            if let debugInfo = response.debugInfo {
                mergeDebugInfo(debugInfo, for: requestID)
            }

            guard let state = container.requestStates[requestID], !state.isTerminal else { return }

            let providerElapsed = ContinuousClock.now - startTime
            let responsePreview = String(response.text.prefix(50))
            let responseSummary =
                "[Image] Provider responded: text=\(responsePreview), "
                    + "attachments=\(response.attachments.count), elapsed=\(providerElapsed)"
            logger.info("\(responseSummary, privacy: .public)")

            let attachments: [MessageAttachment]
            let assistantMessageID = UUID()
            if response.attachments.isEmpty {
                attachments = []
            } else if let messageAssetStore {
                attachments = try await messageAssetStore.materialize(
                    attachments: response.attachments,
                    conversationId: snapshot.conversationId,
                    messageId: assistantMessageID
                )
                logger.info("[Image] Assets materialized: \(attachments.count) attachment(s) persisted locally")
            } else {
                throw RequestError.remoteError(
                    provider: snapshot.providerID,
                    message: "Image assets could not be persisted locally"
                )
            }

            guard !attachments.isEmpty else {
                throw RequestError.remoteError(
                    provider: snapshot.providerID,
                    message: "Image generation did not produce a renderable attachment"
                )
            }

            let assistantMessage = ChatMessage(
                id: assistantMessageID,
                role: .assistant,
                content: response.text.isEmpty ? "Generated image." : response.text,
                attachments: attachments,
                debugInfoJSON: currentDebugInfoJSON(for: requestID)
            )
            container.requestStates[requestID]?.assistantMessageID = assistantMessage.id
            container.appendMessage(assistantMessage, toConversation: snapshot.conversationId)

            if shouldPersistConversation(for: snapshot), !snapshot.conversationId.isEmpty {
                try persistence?.persistSystemMessage(
                    assistantMessage,
                    conversationId: snapshot.conversationId,
                    status: .completed
                )
            }

            if shouldPersistConversation(for: snapshot),
               snapshot.conversationId != container.activeConversationId
            {
                container.markUnreadCompletion(forConversation: snapshot.conversationId)
            }

            appendTraceEvent(
                for: requestID,
                category: .response,
                title: "Image response completed",
                summary: "Received \(attachments.count) attachment(s)",
                sections: traceSections([
                    ("Assistant Preview", trimmedDebugPreview(assistantMessage.content)),
                    ("Attachment Count", String(attachments.count))
                ])
            )

            let totalElapsed = ContinuousClock.now - startTime
            logger.info("[Image] Image generation complete: messageID=\(assistantMessageID), totalElapsed=\(totalElapsed)")
            finishImageSession(requestID: requestID, conversationId: snapshot.conversationId)
        } catch is CancellationError {
            return
        } catch let error as ProviderRequestDebugFailure {
            let elapsed = ContinuousClock.now - startTime
            logger.error("[Image] Image generation failed after \(elapsed): \(error.message)")
            let mergedDebugInfo = baseDebugInfo.merged(with: error.debugInfo)
            mergeDebugInfo(mergedDebugInfo, for: requestID)
            failSession(
                requestID: requestID,
                error: .remoteError(provider: error.providerID, message: error.message),
                debugInfoJSON: mergedDebugInfo.prettyJSONString()
            )
        } catch let error as RequestError {
            let elapsed = ContinuousClock.now - startTime
            logger.error("[Image] Image generation failed after \(elapsed): \(error.errorDescription ?? "unknown")")
            mergeDebugInfo(baseDebugInfo, for: requestID)
            failSession(
                requestID: requestID,
                error: error,
                debugInfoJSON: baseDebugInfo.prettyJSONString()
            )
        } catch {
            let elapsed = ContinuousClock.now - startTime
            logger.error("[Image] Image generation failed after \(elapsed): \(error.localizedDescription)")
            var mergedDebugInfo = baseDebugInfo
            mergedDebugInfo.providerError = error.localizedDescription
            mergeDebugInfo(mergedDebugInfo, for: requestID)
            failSession(
                requestID: requestID,
                error: .remoteError(provider: snapshot.providerID, message: error.localizedDescription),
                debugInfoJSON: mergedDebugInfo.prettyJSONString()
            )
        }
    }

    private func finishImageSession(requestID: RequestID, conversationId: String) {
        guard let container else { return }
        guard let state = container.requestStates[requestID], !state.isTerminal else { return }
        container.requestStates[requestID]?.status = .completed
        cleanupFlushState(requestID: requestID)
        schedulerState.runningSessions.removeValue(forKey: requestID)
        container.requestStates.removeValue(forKey: requestID)
        container.statusMessage = conversationId == container.activeConversationId
            ? "Response complete"
            : "Background request complete"
        container.syncPublishedSchedulerState()
        container.scheduleIdlePrewarmFromCoordinator()
        advanceQueue()
    }

    private func durationSeconds(_ duration: Duration) -> Double {
        let (sec, atto) = duration.components
        return Double(sec) + Double(atto) * 1e-18
    }

    private func makeImageRequestDebugInfo(
        snapshot: QueueItemSnapshot,
        modelDescriptor: ModelDescriptor,
        context: ProviderInvocationContext
    ) -> MessageDebugInfo {
        let supportedOutputs = modelDescriptor.supportedOutputs.map(\.rawValue)
        return MessageDebugInfo(
            requestID: snapshot.id.description,
            providerID: snapshot.providerID,
            modelID: snapshot.modelID,
            requestKind: "image_generation",
            routeDecision: "RequestCoordinator routed to provider.send because "
                + "modelType=\(modelDescriptor.modelType.rawValue) and "
                + "supportedOutputs=\(supportedOutputs.joined(separator: ","))",
            endpoint: context.endpoint,
            descriptorModelType: modelDescriptor.modelType.rawValue,
            descriptorSupportedOutputs: supportedOutputs,
            descriptorRawMetadataJSON: trimmedDebugPreview(modelDescriptor.rawMetadataJSON)
        )
    }

    private func trimmedDebugPreview(_ value: String?, limit: Int = 4096) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if value.count <= limit {
            return value
        }
        return String(value.prefix(limit)) + "... [truncated]"
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
        case let .debug(rid, info) where rid == requestID:
            mergeDebugInfo(info, for: requestID)
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

        if !isActiveConversation, shouldPersistConversation(for: requestID) {
            container.markUnreadCompletion(forConversation: owningConversationId)
        }

        container.requestStates[requestID]?.appendDelta(text)
        if let flushState = sessionFlushState[requestID] {
            flushState.deltaChunkCount += 1
            let remainingPreviewBudget = max(0, 1024 - flushState.deltaPreview.count)
            if remainingPreviewBudget > 0 {
                flushState.deltaPreview += String(text.prefix(remainingPreviewBudget))
            }
        }
        let accumulated = container.requestStates[requestID]?.flushText() ?? ""

        if let msgID = container.requestStates[requestID]?.assistantMessageID {
            ensureRevealLoopRunning(requestID: requestID)
            throttledStreamingFlush(requestID: requestID, messageId: msgID.uuidString, content: accumulated)
            return
        }

        let initialPresented = primePresentedContent(requestID: requestID)
        let newMessage = ChatMessage(
            role: .assistant,
            content: initialPresented,
            debugInfoJSON: currentDebugInfoJSON(for: requestID)
        )
        container.requestStates[requestID]?.assistantMessageID = newMessage.id
        container.appendMessage(newMessage, toConversation: owningConversationId)

        if let flushState = sessionFlushState[requestID] {
            flushState.lastRevealAt = ContinuousClock.now
            flushState.lastUIFlush = ContinuousClock.now
            flushState.latestPresentedLength = initialPresented.count
        }

        if shouldPersistConversation(for: requestID), !owningConversationId.isEmpty {
            let persistedDraft = ChatMessage(
                id: newMessage.id,
                role: .assistant,
                content: accumulated,
                debugInfoJSON: currentDebugInfoJSON(for: requestID),
                createdAt: newMessage.createdAt
            )
            try? persistence?.persistAssistantDraft(
                persistedDraft,
                conversationId: owningConversationId,
                requestId: requestID.value.uuidString
            )
        }

        syncDebugInfoToMessages(requestID: requestID)

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
    var deltaChunkCount: Int = 0
    var deltaPreview: String = ""
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
        guard shouldPersistConversation(for: requestID) else { return }
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
        sessionSnapshots.removeValue(forKey: requestID)
        sessionDebugInfo.removeValue(forKey: requestID)
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

        func flushStateCountForTesting() -> Int {
            sessionFlushState.count
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
