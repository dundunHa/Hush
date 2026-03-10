import AppKit
import Foundation
@testable import Hush
import Testing

// swiftlint:disable file_length
@MainActor
struct RequestCoordinatorStreamingUIFlushTests {
    private func makeContainer(
        provider: some LLMProvider,
        streamingPresentationPolicy: StreamingPresentationPolicy? = .testingFast
    ) -> AppContainer {
        var registry = ProviderRegistry()
        registry.register(provider)

        let settings = AppSettings(
            providerConfigurations: [.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard
        )

        let container = AppContainer.forTesting(
            settings: settings,
            registry: registry,
            activeConversationId: "test-conv",
            streamingPresentationPolicyOverride: streamingPresentationPolicy
        )
        container.resetConversation()
        return container
    }

    private func waitForCompletion(_ container: AppContainer, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func attachActiveScene(
        _ container: AppContainer
    ) throws -> (pool: HotScenePool, scene: ConversationViewController, conversationID: String) {
        let conversationID = try #require(container.activeConversationId)
        let pool = HotScenePool(capacity: 2)
        container.registerHotScenePool(pool)
        let scene = ConversationViewController(container: container, theme: container.settings.theme)
        _ = pool.switchTo(conversationID: conversationID, messageCount: 0, generation: 1) {
            scene
        }
        return (pool, scene, conversationID)
    }

    private func syncSceneSnapshot(
        _ scene: ConversationViewController,
        from container: AppContainer
    ) {
        scene.applyConversationState(
            conversationId: container.activeConversationId,
            messages: container.messages,
            isSending: container.isActiveConversationSending,
            generation: container.activeConversationRenderGeneration,
            container: container
        )
    }

    @Test("Final content is correct after rapid deltas")
    func finalContentIsCorrectAfterRapidDeltas() async throws {
        let deltaCount = 200
        let deltaText = "x"
        let provider = RapidDeltaProvider(id: "mock", deltaCount: deltaCount, deltaText: deltaText)
        let container = makeContainer(provider: provider)

        container.sendDraft("hello")

        try await waitForCompletion(container)

        #expect(container.activeRequest == nil)

        let lastAssistant = container.messages.last(where: { $0.role == .assistant })
        let expected = String(repeating: deltaText, count: deltaCount)
        #expect(lastAssistant?.content == expected)
    }

    @Test("UI flush count is bounded below delta count")
    func uiFlushCountIsBounded() async throws {
        let deltaCount = 200
        let deltaText = "y"
        let provider = RapidDeltaProvider(id: "mock", deltaCount: deltaCount, deltaText: deltaText)
        let container = makeContainer(provider: provider)

        container.sendDraft("hello")

        // Poll and count distinct content values seen on the assistant message
        var observedContentVersions: Set<String> = []
        let deadline = ContinuousClock.now + .seconds(5)
        while container.activeRequest != nil, ContinuousClock.now < deadline {
            if let lastMsg = container.messages.last, lastMsg.role == .assistant {
                observedContentVersions.insert(lastMsg.content)
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        // Capture final state
        if let lastMsg = container.messages.last, lastMsg.role == .assistant {
            observedContentVersions.insert(lastMsg.content)
        }

        // With 200 deltas and ~100ms throttle, we expect far fewer than 200 distinct UI states.
        // Allow generous upper bound to avoid flakiness (e.g., ≤ 80).
        #expect(observedContentVersions.count < 80)

        // Verify final content is still correct
        let expected = String(repeating: deltaText, count: deltaCount)
        #expect(container.messages.last(where: { $0.role == .assistant })?.content == expected)
    }

    @Test("Large first delta is revealed incrementally instead of appearing all at once")
    func largeFirstDeltaRevealsIncrementally() async throws {
        let burst = String(repeating: "x", count: 200)
        let provider = SingleBurstProvider(
            id: "mock",
            deltaText: burst,
            completionDelay: .milliseconds(250)
        )
        let container = makeContainer(provider: provider)
        let (pool, scene, _) = try attachActiveScene(container)
        _ = pool

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while (container.activeRequest?.accumulatedText ?? "") != burst, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        let initialVisible = try #require(container.messages.last(where: { $0.role == .assistant })?.content)
        #expect(initialVisible.count == StreamingPresentationPolicy.testingFast.initialRevealCharacters)
        #expect(initialVisible != burst)

        let revealDeadline = ContinuousClock.now + .seconds(1)
        while (scene.lastStreamingPushContentForTesting?.count ?? 0) <= initialVisible.count,
              ContinuousClock.now < revealDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        let progressedVisible = try #require(scene.lastStreamingPushContentForTesting)
        #expect(progressedVisible.count > initialVisible.count)
        #expect(progressedVisible.count < burst.count)

        container.stopActiveRequest()
    }

    @Test("Completed streams stay running until terminal catch-up finishes")
    func completedStreamsWaitForCatchUpBeforeFinalizing() async throws {
        let burst = String(repeating: "z", count: 180)
        let provider = SingleBurstProvider(id: "mock", deltaText: burst)
        let container = makeContainer(provider: provider)

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while (container.activeRequest?.accumulatedText ?? "") != burst, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        let visibleWhileCatchingUp = try #require(container.messages.last(where: { $0.role == .assistant })?.content)
        #expect(container.activeRequest != nil)
        #expect(visibleWhileCatchingUp.count < burst.count)

        try await waitForCompletion(container)

        #expect(container.messages.last(where: { $0.role == .assistant })?.content == burst)
    }

    @Test("Production streaming policy keeps advancing without force-revealing the remainder")
    func productionPolicyKeepsAdvancingWithoutForceReveal() async throws {
        let productionPolicy = StreamingPresentationPolicy.production
        let burst = String(
            repeating: "q",
            count: Int(productionPolicy.fastestCharactersPerSecond) + 12
        )
        let provider = SingleBurstProvider(id: "mock", deltaText: burst)
        let container = makeContainer(
            provider: provider,
            streamingPresentationPolicy: productionPolicy
        )
        let (pool, scene, _) = try attachActiveScene(container)
        _ = pool

        container.sendDraft("hello")

        let accumulationDeadline = ContinuousClock.now + .seconds(2)
        while (container.activeRequest?.accumulatedText ?? "") != burst,
              ContinuousClock.now < accumulationDeadline
        {
            try await Task.sleep(for: .milliseconds(5))
        }

        let initialVisible = try #require(container.messages.last(where: { $0.role == .assistant })?.content)
        #expect(container.activeRequest != nil)
        #expect(initialVisible.count == productionPolicy.initialRevealCharacters)
        #expect(initialVisible.count < burst.count)

        let fastPathDeadline = ContinuousClock.now + .milliseconds(300)
        while (scene.lastStreamingPushContentForTesting?.count ?? 0) <= initialVisible.count,
              ContinuousClock.now < fastPathDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        let progressedFastPath = try #require(scene.lastStreamingPushContentForTesting)
        #expect(progressedFastPath.count > initialVisible.count)
        #expect(progressedFastPath.count < burst.count)

        try await Task.sleep(for: .milliseconds(260))

        let visibleAfterQuarterSecond = try #require(container.messages.last(where: { $0.role == .assistant })?.content)
        #expect(container.activeRequest != nil)
        #expect(visibleAfterQuarterSecond.count > initialVisible.count)
        #expect(visibleAfterQuarterSecond.count < burst.count)

        try await waitForCompletion(container, timeout: .seconds(3))

        #expect(container.activeRequest == nil)
        #expect(container.messages.last(where: { $0.role == .assistant })?.content == burst)
    }

    @Test("Visible streaming cell keeps advancing across long fast-path updates")
    func visibleStreamingCellKeepsAdvancingOnLongBurst() async throws {
        let burst = String(repeating: "v", count: 240)
        let provider = SingleBurstProvider(
            id: "mock",
            deltaText: burst,
            completionDelay: .seconds(2)
        )
        let container = makeContainer(provider: provider)
        let (pool, scene, _) = try attachActiveScene(container)
        _ = pool

        container.sendDraft("hello")

        let assistantDeadline = ContinuousClock.now + .seconds(2)
        while container.messages.last(where: { $0.role == .assistant }) == nil,
              ContinuousClock.now < assistantDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        let assistantRow = try #require(container.messages.indices.last)
        syncSceneSnapshot(scene, from: container)
        scene.messageTableViewForTesting.prepareCellForTesting(row: assistantRow)

        let progressionDeadline = ContinuousClock.now + .seconds(1)
        while (scene.messageTableViewForTesting.visibleCellForTesting(row: assistantRow)?
            .attributedStringForTesting.string.count ?? 0) < 120,
            ContinuousClock.now < progressionDeadline
        {
            scene.messageTableViewForTesting.prepareCellForTesting(row: assistantRow)
            try await Task.sleep(for: .milliseconds(20))
        }

        let visibleCell = try #require(
            scene.messageTableViewForTesting.visibleCellForTesting(row: assistantRow)
        )
        let visibleCount = visibleCell.attributedStringForTesting.string.count
        #expect(visibleCount >= 120)
        #expect(visibleCount < burst.count)

        container.stopActiveRequest()
    }

    @Test("Stop flushes and preserves final content")
    func stopFlushesAndPreservesFinalContent() async throws {
        let deltaCount = 50
        let deltaText = "s"
        let provider = SlowDeltaProvider(id: "mock", deltaCount: deltaCount, deltaText: deltaText)
        let container = makeContainer(provider: provider)

        container.sendDraft("hello")

        // Wait for some deltas to arrive
        let streamDeadline = ContinuousClock.now + .seconds(2)
        while container.messages.last(where: { $0.role == .assistant }) == nil,
              ContinuousClock.now < streamDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        // Let a few more deltas flow
        try await Task.sleep(for: .milliseconds(100))

        container.stopActiveRequest()

        #expect(container.activeRequest == nil)

        let lastAssistant = container.messages.last(where: { $0.role == .assistant })
        #expect(lastAssistant != nil)
        // Content must not be empty — some deltas were accumulated
        #expect(lastAssistant?.content.isEmpty == false)
        // Content should consist only of the delta text characters
        #expect(lastAssistant?.content.allSatisfy { $0 == Character(deltaText) } == true)
    }

    @Test("Complete flushes and preserves final content")
    func completeFlushesAndPreservesFinalContent() async throws {
        let deltaCount = 100
        let deltaText = "c"
        let provider = RapidDeltaProvider(id: "mock", deltaCount: deltaCount, deltaText: deltaText)
        let container = makeContainer(provider: provider)

        container.sendDraft("hello")

        try await waitForCompletion(container)

        #expect(container.activeRequest == nil)

        let expected = String(repeating: deltaText, count: deltaCount)
        let lastAssistant = container.messages.last(where: { $0.role == .assistant })
        #expect(lastAssistant?.content == expected)
    }

    @Test("cancelAll cleans up pending flush without crash")
    func cancelAllCleansUpPendingFlush() async throws {
        let deltaCount = 50
        let deltaText = "z"
        let provider = SlowDeltaProvider(id: "mock", deltaCount: deltaCount, deltaText: deltaText)
        let container = makeContainer(provider: provider)

        container.sendDraft("hello")

        // Wait for streaming to start
        let streamDeadline = ContinuousClock.now + .seconds(2)
        while container.messages.last(where: { $0.role == .assistant }) == nil,
              ContinuousClock.now < streamDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        container.requestCoordinator.cancelAll()

        #expect(container.activeRequest == nil)
        // No crash is the primary assertion; queue and state should be clean
        #expect(container.pendingQueue.isEmpty)
    }

    @Test("resetConversation clears messages and state without crash")
    func resetConversationClearsStateWithoutCrash() async throws {
        let deltaCount = 50
        let deltaText = "r"
        let provider = SlowDeltaProvider(id: "mock", deltaCount: deltaCount, deltaText: deltaText)
        let container = makeContainer(provider: provider)

        container.sendDraft("hello")

        // Wait for streaming to start
        let streamDeadline = ContinuousClock.now + .seconds(2)
        while container.messages.last(where: { $0.role == .assistant }) == nil,
              ContinuousClock.now < streamDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        container.resetConversation()

        #expect(container.messages.isEmpty)
        // No crash is the primary assertion; queue and state should be clean
        #expect(container.pendingQueue.isEmpty)
    }

    @Test("Fast-track flush is throttled and eventually pushes latest content")
    func fastTrackFlushIsThrottledAndPushesLatestContent() async throws {
        let deltaCount = 200
        let deltaText = "f"
        let provider = RapidDeltaProvider(id: "mock", deltaCount: deltaCount, deltaText: deltaText)
        let container = makeContainer(provider: provider)
        let (pool, scene, _) = try attachActiveScene(container)
        _ = pool

        container.sendDraft("hello")
        try await waitForCompletion(container)

        let expected = String(repeating: deltaText, count: deltaCount)
        #expect(scene.streamingPushCountForTesting > 0)
        #expect(scene.streamingPushCountForTesting < deltaCount)
        #expect(scene.lastStreamingPushContentForTesting == expected)
    }

    @Test("Stopping request flushes both fast and slow tracks")
    func stoppingRequestFlushesBothTracks() async throws {
        let provider = BurstThenWaitProvider(id: "mock")
        let container = makeContainer(provider: provider)
        let (pool, scene, _) = try attachActiveScene(container)
        _ = pool

        container.sendDraft("hello")

        let deadline = ContinuousClock.now + .seconds(2)
        while (container.activeRequest?.accumulatedText ?? "") != "ABC", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        container.stopActiveRequest()

        let finalAssistant = container.messages.last(where: { $0.role == .assistant })?.content
        #expect(finalAssistant == "ABC")
        #expect(scene.lastStreamingPushContentForTesting == "ABC")
    }

    @Test("cancelThrottleTasksForConversation clears pending tasks for evicted conversation")
    func cancelThrottleTasksForConversationClearsPendingTasks() async throws {
        let provider = SlowDeltaProvider(id: "mock", deltaCount: 50, deltaText: "e")
        let container = makeContainer(provider: provider)

        container.sendDraft("hello")

        let streamDeadline = ContinuousClock.now + .seconds(2)
        while container.messages.last(where: { $0.role == .assistant }) == nil,
              ContinuousClock.now < streamDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        let conversationId = try #require(container.activeConversationId)
        #expect(container.requestCoordinator.hasPendingThrottleTasksForConversation(conversationId)
            || container.requestCoordinator.isConversationRunning(conversationId))

        container.requestCoordinator.cancelThrottleTasksForConversation(conversationId)

        #expect(!container.requestCoordinator.hasPendingThrottleTasksForConversation(conversationId))

        container.stopActiveRequest()
    }
}

// MARK: - Test Providers

private actor RapidDeltaProvider: LLMProvider {
    nonisolated let id: String
    let deltaCount: Int
    let deltaText: String

    init(id: String, deltaCount: Int = 200, deltaText: String = "x") {
        self.id = id
        self.deltaCount = deltaCount
        self.deltaText = deltaText
    }

    // swiftlint:disable async_without_await
    nonisolated func availableModels(
        context _: ProviderInvocationContext
    ) async throws -> [ModelDescriptor] {
        [ModelDescriptor(id: "mock-text-1", displayName: "Mock", capabilities: [.text])]
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, content: "unused")
    }

    // swiftlint:enable async_without_await

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let count = deltaCount
        let text = deltaText
        return AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID))
            for _ in 0 ..< count {
                continuation.yield(.delta(requestID: requestID, text: text))
            }
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
        }
    }
}

private actor SlowDeltaProvider: LLMProvider {
    nonisolated let id: String
    let deltaCount: Int
    let deltaText: String

    init(id: String, deltaCount: Int = 50, deltaText: String = "s") {
        self.id = id
        self.deltaCount = deltaCount
        self.deltaText = deltaText
    }

    // swiftlint:disable async_without_await
    nonisolated func availableModels(
        context _: ProviderInvocationContext
    ) async throws -> [ModelDescriptor] {
        [ModelDescriptor(id: "mock-text-1", displayName: "Mock", capabilities: [.text])]
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, content: "unused")
    }

    // swiftlint:enable async_without_await

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let count = deltaCount
        let text = deltaText
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(requestID: requestID))
                for _ in 0 ..< count {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(10))
                    try Task.checkCancellation()
                    continuation.yield(.delta(requestID: requestID, text: text))
                }
                continuation.yield(.completed(requestID: requestID))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private actor SingleBurstProvider: LLMProvider {
    nonisolated let id: String
    let deltaText: String
    let completionDelay: Duration

    init(id: String, deltaText: String, completionDelay: Duration = .zero) {
        self.id = id
        self.deltaText = deltaText
        self.completionDelay = completionDelay
    }

    // swiftlint:disable async_without_await
    nonisolated func availableModels(
        context _: ProviderInvocationContext
    ) async throws -> [ModelDescriptor] {
        [ModelDescriptor(id: "mock-text-1", displayName: "Mock", capabilities: [.text])]
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, content: "unused")
    }

    // swiftlint:enable async_without_await

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let text = deltaText
        let delay = completionDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(requestID: requestID))
                continuation.yield(.delta(requestID: requestID, text: text))
                if delay > .zero {
                    try await Task.sleep(for: delay)
                }
                continuation.yield(.completed(requestID: requestID))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

private actor BurstThenWaitProvider: LLMProvider {
    nonisolated let id: String

    init(id: String) {
        self.id = id
    }

    // swiftlint:disable async_without_await
    nonisolated func availableModels(
        context _: ProviderInvocationContext
    ) async throws -> [ModelDescriptor] {
        [ModelDescriptor(id: "mock-text-1", displayName: "Mock", capabilities: [.text])]
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, content: "unused")
    }

    // swiftlint:enable async_without_await

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(requestID: requestID))
                continuation.yield(.delta(requestID: requestID, text: "A"))
                continuation.yield(.delta(requestID: requestID, text: "B"))
                continuation.yield(.delta(requestID: requestID, text: "C"))
                try await Task.sleep(for: .seconds(1))
                continuation.yield(.completed(requestID: requestID))
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

// swiftlint:enable file_length
