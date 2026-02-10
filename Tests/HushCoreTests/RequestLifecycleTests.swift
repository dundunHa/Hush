import Foundation
import XCTest
@testable import HushCore
@testable import HushProviders
@testable import HushApp

// MARK: - Test Helpers

/// A provider with artificially slow `availableModels()` for preflight timeout testing.
struct SlowPreflightProvider: LLMProvider {
    let id: String
    let delay: Duration

    init(id: String = "slow-preflight", delay: Duration = .seconds(10)) {
        self.id = id
        self.delay = delay
    }

    func availableModels() async throws -> [ModelDescriptor] {
        try await Task.sleep(for: delay)
        return [
            ModelDescriptor(id: "model-1", displayName: "Model 1", capabilities: [.text])
        ]
    }

    func send(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, content: "reply")
    }

    func sendStreaming(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        requestID: RequestID
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

/// A provider that never completes its stream, for generation timeout testing.
struct HangingStreamProvider: LLMProvider {
    let id: String

    init(id: String = "hanging") {
        self.id = id
    }

    func availableModels() async throws -> [ModelDescriptor] {
        [ModelDescriptor(id: "mock-text-1", displayName: "Model", capabilities: [.text])]
    }

    func send(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, content: "reply")
    }

    func sendStreaming(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        requestID: RequestID
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID))
            // Never yields completed or failed — stream hangs
            continuation.onTermination = { _ in }
        }
    }
}

/// A provider that intentionally keeps emitting after cancellation to test stale-event suppression.
struct LateEventAfterCancelProvider: LLMProvider {
    let id: String

    init(id: String = "mock") {
        self.id = id
    }

    func availableModels() async throws -> [ModelDescriptor] {
        [ModelDescriptor(id: "mock-text-1", displayName: "Model", capabilities: [.text])]
    }

    func send(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, content: "reply")
    }

    func sendStreaming(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        requestID: RequestID
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started(requestID: requestID))
                try? await Task.sleep(for: .milliseconds(20))
                continuation.yield(.delta(requestID: requestID, text: "first"))

                // Emit a second chunk much later; by then request may already be stopped.
                try? await Task.sleep(for: .milliseconds(180))
                continuation.yield(.delta(requestID: requestID, text: "late"))
                continuation.yield(.completed(requestID: requestID))
                continuation.finish()
            }

            // Intentionally left empty to simulate a provider that does not stop promptly.
            continuation.onTermination = { _ in }
        }
    }
}

/// A provider that fails streaming with an unstructured non-RequestError payload.
struct UnstructuredErrorProvider: LLMProvider {
    let id: String

    init(id: String = "mock") {
        self.id = id
    }

    func availableModels() async throws -> [ModelDescriptor] {
        [ModelDescriptor(id: "mock-text-1", displayName: "Model", capabilities: [.text])]
    }

    func send(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters
    ) async throws -> ChatMessage {
        ChatMessage(role: .assistant, content: "reply")
    }

    func sendStreaming(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        requestID: RequestID
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.started(requestID: requestID))
                try? await Task.sleep(for: .milliseconds(20))
                continuation.finish(throwing: NSError(
                    domain: "UnstructuredErrorProvider",
                    code: -1009,
                    userInfo: [NSLocalizedDescriptionKey: "socket closed"]
                ))
            }
        }
    }
}

@MainActor
private func waitForIdle(_ container: AppContainer, timeout: Duration = .seconds(5)) async {
    let deadline = ContinuousClock.now + timeout
    while container.isSending && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func makeContainer(
    provider: any LLMProvider = MockProvider(id: "mock"),
    settings: AppSettings = .default
) -> AppContainer {
    var registry = ProviderRegistry()
    registry.register(provider)
    return AppContainer.forTesting(settings: settings, registry: registry)
}

// MARK: - 5.1 Single Active Stream + FIFO Queue Progression

final class SingleActiveStreamTests: XCTestCase {

    @MainActor
    func testFirstSendStartsActiveStream() async throws {
        let container = makeContainer()
        container.draft = "Hello"
        container.sendDraft()

        XCTAssertNotNil(container.activeRequest)
        XCTAssertTrue(container.isSending)
        XCTAssertTrue(container.pendingQueue.isEmpty)

        await waitForIdle(container)
    }

    @MainActor
    func testSecondSendQueuesInsteadOfStartingNewStream() async throws {
        let slowMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: ["a", "b", "c"],
                delayPerChunk: .milliseconds(200)
            )
        )
        let container = makeContainer(provider: slowMock)

        container.draft = "First"
        container.sendDraft()

        XCTAssertNotNil(container.activeRequest)
        let firstRequestID = container.activeRequest?.requestID

        container.draft = "Second"
        container.sendDraft()

        // Should be queued, not a second active stream
        XCTAssertEqual(container.pendingQueue.count, 1)
        XCTAssertEqual(container.activeRequest?.requestID, firstRequestID)

        await waitForIdle(container)
    }

    @MainActor
    func testFIFOQueueProgressionAfterCompletion() async throws {
        let fastMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: ["reply"],
                delayPerChunk: .milliseconds(50)
            )
        )
        let container = makeContainer(provider: fastMock)

        // Send two messages quickly — second gets queued
        container.draft = "First"
        container.sendDraft()
        container.draft = "Second"
        container.sendDraft()

        XCTAssertEqual(container.pendingQueue.count, 1)

        // Wait for both to complete
        await waitForIdle(container)

        // Both completed: 2 user messages + 2 assistant messages
        let userCount = container.messages.filter { $0.role == .user }.count
        let assistantCount = container.messages.filter { $0.role == .assistant }.count
        XCTAssertEqual(userCount, 2)
        XCTAssertEqual(assistantCount, 2)
        XCTAssertTrue(container.pendingQueue.isEmpty)
        XCTAssertNil(container.activeRequest)
    }
}

// MARK: - 5.2 Submission Snapshot Integrity

final class SnapshotIntegrityTests: XCTestCase {

    @MainActor
    func testQueuedRequestUsesSnapshotNotLiveSettings() async throws {
        let slowMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: ["a", "b"],
                delayPerChunk: .milliseconds(300)
            )
        )
        let container = makeContainer(provider: slowMock)

        // Send first message with temperature 0.7
        container.draft = "First"
        container.sendDraft()

        // Change temperature while first is active
        container.settings.parameters.temperature = 0.1

        // Send second with new temperature — but snapshot should capture 0.1
        container.draft = "Second"
        container.sendDraft()

        XCTAssertEqual(container.pendingQueue.count, 1)
        let queuedSnapshot = container.pendingQueue.first

        // Queued snapshot captured at submission time: temperature = 0.1
        XCTAssertEqual(queuedSnapshot?.parameters.temperature, 0.1)
        XCTAssertEqual(queuedSnapshot?.providerID, "mock")
        XCTAssertEqual(queuedSnapshot?.modelID, "mock-text-1")

        await waitForIdle(container)
    }

    @MainActor
    func testSnapshotCapturesPromptAndProvider() async throws {
        let slowMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: ["a"],
                delayPerChunk: .milliseconds(300)
            )
        )
        let container = makeContainer(provider: slowMock)

        container.draft = "First"
        container.sendDraft()

        container.draft = "Captured prompt"
        container.sendDraft()

        let snapshot = container.pendingQueue.first
        XCTAssertEqual(snapshot?.prompt, "Captured prompt")
        XCTAssertEqual(snapshot?.providerID, "mock")

        await waitForIdle(container)
    }
}

// MARK: - 5.3 Queue-Full Atomic Rejection

final class QueueFullRejectionTests: XCTestCase {

    @MainActor
    func testQueueFullRejectsWithNoSideEffects() async throws {
        let slowMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: Array(repeating: "x", count: 20),
                delayPerChunk: .milliseconds(200)
            )
        )
        let container = makeContainer(provider: slowMock)

        // Send first (starts active)
        container.draft = "Active"
        container.sendDraft()

        // Fill the queue to capacity (5 pending)
        for i in 1...RuntimeConstants.pendingQueueCapacity {
            container.draft = "Queued \(i)"
            container.sendDraft()
        }

        XCTAssertEqual(container.pendingQueue.count, RuntimeConstants.pendingQueueCapacity)
        let messageCountBefore = container.messages.count
        let queueCountBefore = container.pendingQueue.count

        // This should be rejected atomically
        container.draft = "Overflow"
        container.sendDraft()

        // No user message appended, no queue item added
        XCTAssertEqual(container.messages.count, messageCountBefore)
        XCTAssertEqual(container.pendingQueue.count, queueCountBefore)
        XCTAssertTrue(container.statusMessage.contains("Queue full"))

        // Rejected send returns before draft clear, so input remains for user retry.
        XCTAssertEqual(container.draft, "Overflow")

        // Cleanup
        container.resetConversation()
    }
}

// MARK: - 5.4 Stop/Cancel, Stale-Event Suppression, Auto-Advance

final class StopCancelTests: XCTestCase {

    @MainActor
    func testStopCancelsActiveAndPreservesQueue() async throws {
        let slowMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: Array(repeating: "x", count: 20),
                delayPerChunk: .milliseconds(200)
            )
        )
        let container = makeContainer(provider: slowMock)

        container.draft = "First"
        container.sendDraft()
        let firstRequestID = container.activeRequest?.requestID

        container.draft = "Second"
        container.sendDraft()

        // Wait a moment for the stream to start
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(container.pendingQueue.count, 1)

        // Stop active request — queue auto-advances so a new request starts immediately
        container.stopActiveRequest()

        // The second request should now be active (different from the first)
        XCTAssertNotEqual(container.activeRequest?.requestID, firstRequestID)
        XCTAssertTrue(container.pendingQueue.isEmpty, "Queue should be empty after auto-advance")

        await waitForIdle(container)

        // After everything completes, both messages should have responses
        let assistantCount = container.messages.filter { $0.role == .assistant }.count
        XCTAssertGreaterThanOrEqual(assistantCount, 2)
        XCTAssertNil(container.activeRequest)
    }

    @MainActor
    func testStopWithoutActiveRequestIsNoOp() async throws {
        let container = makeContainer()

        let messagesBefore = container.messages.count
        let queueBefore = container.pendingQueue.count

        container.stopActiveRequest()

        XCTAssertEqual(container.messages.count, messagesBefore)
        XCTAssertEqual(container.pendingQueue.count, queueBefore)
        XCTAssertEqual(container.statusMessage, "No active request to stop")
    }

    @MainActor
    func testStopWithNoContentAddsStoppedMessage() async throws {
        let slowMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: Array(repeating: "x", count: 20),
                delayPerChunk: .seconds(5)
            )
        )
        let container = makeContainer(provider: slowMock)

        container.draft = "Hello"
        container.sendDraft()

        // Wait just enough for preflight, but not for any deltas
        try await Task.sleep(for: .milliseconds(100))

        container.stopActiveRequest()

        // Should have user message + "[Request stopped]" assistant message
        let stoppedMessages = container.messages.filter { $0.content == "[Request stopped]" }
        XCTAssertEqual(stoppedMessages.count, 1)
    }

    @MainActor
    func testAutoAdvanceAfterStop() async throws {
        let slowMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: ["done"],
                delayPerChunk: .milliseconds(100)
            )
        )
        let container = makeContainer(provider: slowMock)

        container.draft = "First"
        container.sendDraft()
        container.draft = "Second"
        container.sendDraft()

        // Stop immediately — second should auto-advance
        container.stopActiveRequest()

        // Wait for second to complete
        await waitForIdle(container)

        XCTAssertNil(container.activeRequest)
        XCTAssertTrue(container.pendingQueue.isEmpty)
    }

    @MainActor
    func testLateEventsAfterStopAreIgnored() async throws {
        let provider = LateEventAfterCancelProvider(id: "mock")
        let container = makeContainer(provider: provider)

        container.draft = "Hello"
        container.sendDraft()

        // Let first delta arrive, then stop before late delta.
        try await Task.sleep(for: .milliseconds(80))
        let assistantBeforeStop = container.messages.last(where: { $0.role == .assistant })?.content ?? ""
        XCTAssertTrue(assistantBeforeStop.contains("first"))

        container.stopActiveRequest()
        XCTAssertEqual(container.statusMessage, "Request stopped")

        // Wait past late-emission window.
        try await Task.sleep(for: .milliseconds(260))

        let assistantMessages = container.messages.filter { $0.role == .assistant }
        XCTAssertTrue(assistantMessages.contains(where: { $0.content.contains("first") }))
        XCTAssertFalse(assistantMessages.contains(where: { $0.content.contains("late") }))
        XCTAssertEqual(container.statusMessage, "Request stopped")
    }
}

// MARK: - 5.5 Strict Provider Resolution

final class StrictProviderResolutionTests: XCTestCase {

    @MainActor
    func testMissingProviderFailsFast() async throws {
        var settings = AppSettings.default
        settings.selectedProviderID = "nonexistent"

        let container = makeContainer(settings: settings)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container)

        // Should have failed with provider missing error
        let errorMessages = container.messages.filter { $0.role == .assistant && $0.content.contains("not found") }
        XCTAssertEqual(errorMessages.count, 1)
        XCTAssertNil(container.activeRequest)
    }

    @MainActor
    func testDisabledProviderFailsFast() async throws {
        var settings = AppSettings.default
        settings.providerConfigurations = [
            ProviderConfiguration(
                id: "mock",
                name: "Mock",
                type: .mock,
                endpoint: "local://mock",
                apiKeyEnvironmentVariable: "",
                defaultModelID: "mock-text-1",
                isEnabled: false
            )
        ]

        let container = makeContainer(settings: settings)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container)

        let errorMessages = container.messages.filter { $0.role == .assistant && $0.content.contains("disabled") }
        XCTAssertEqual(errorMessages.count, 1)
    }

    @MainActor
    func testUnregisteredProviderFailsFast() async throws {
        // Config references "other-provider" but no runtime implementation registered
        var settings = AppSettings.default
        settings.selectedProviderID = "other-provider"
        settings.providerConfigurations.append(
            ProviderConfiguration(
                id: "other-provider",
                name: "Other",
                type: .custom,
                endpoint: "https://example.com",
                apiKeyEnvironmentVariable: "",
                defaultModelID: "model-1",
                isEnabled: true
            )
        )

        let container = makeContainer(settings: settings)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container)

        let errorMessages = container.messages.filter {
            $0.role == .assistant && $0.content.contains("No runtime implementation")
        }
        XCTAssertEqual(errorMessages.count, 1)
    }

    @MainActor
    func testNoFallbackToFirstProvider() async throws {
        // selected provider is invalid — should NOT fall back to mock
        var settings = AppSettings.default
        settings.selectedProviderID = "nonexistent"

        let container = makeContainer(settings: settings)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container)

        // No successful assistant response — only error
        let successMessages = container.messages.filter {
            $0.role == .assistant && !$0.content.starts(with: "Error:")
        }
        XCTAssertEqual(successMessages.count, 0)
    }
}

// MARK: - 5.6 Preflight Model Validation Timeout

final class PreflightValidationTests: XCTestCase {

    @MainActor
    func testInvalidModelFailsBeforeGeneration() async throws {
        var settings = AppSettings.default
        settings.selectedModelID = "nonexistent-model"

        let container = makeContainer(settings: settings)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container)

        let errorMessages = container.messages.filter {
            $0.role == .assistant && $0.content.contains("not available")
        }
        XCTAssertEqual(errorMessages.count, 1)
    }

    @MainActor
    func testPreflightTimeoutAborts() async throws {
        let slowProvider = SlowPreflightProvider(id: "mock", delay: .seconds(10))

        var registry = ProviderRegistry()
        registry.register(slowProvider)

        let container = AppContainer.forTesting(registry: registry)
        container.preflightTimeoutOverride = .milliseconds(100)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container, timeout: .seconds(3))

        let errorMessages = container.messages.filter {
            $0.role == .assistant && $0.content.contains("timed out")
        }
        XCTAssertEqual(errorMessages.count, 1)
        XCTAssertNil(container.activeRequest)
    }

    @MainActor
    func testPreflightFailurePreventsGeneration() async throws {
        // Use an invalid model — preflight should fail and no streaming should occur
        var settings = AppSettings.default
        settings.selectedModelID = "nonexistent"

        let container = makeContainer(settings: settings)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container)

        // Only 1 user message and 1 error assistant message — no streaming occurred
        XCTAssertEqual(container.messages.count, 2)
        XCTAssertEqual(container.messages[0].role, .user)
        XCTAssertEqual(container.messages[1].role, .assistant)
        XCTAssertTrue(container.messages[1].content.starts(with: "Error:"))
    }
}

// MARK: - 5.7 Generation Timeout and Remote Error Transparency

final class GenerationTimeoutAndErrorTests: XCTestCase {

    @MainActor
    func testGenerationTimeoutFailsRequest() async throws {
        let hangingProvider = HangingStreamProvider(id: "mock")

        var registry = ProviderRegistry()
        registry.register(hangingProvider)

        let container = AppContainer.forTesting(registry: registry)
        container.generationTimeoutOverride = .milliseconds(200)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container, timeout: .seconds(3))

        let errorMessages = container.messages.filter {
            $0.role == .assistant && $0.content.contains("timed out")
        }
        XCTAssertEqual(errorMessages.count, 1)
        XCTAssertNil(container.activeRequest)
    }

    @MainActor
    func testRemoteErrorIsSurfacedTransparently() async throws {
        let failingMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior.failing(
                after: 0,
                error: .remoteError(provider: "mock", message: "API rate limit exceeded")
            )
        )
        let container = makeContainer(provider: failingMock)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container)

        let errorMessages = container.messages.filter {
            $0.role == .assistant && $0.content.contains("API rate limit exceeded")
        }
        XCTAssertEqual(errorMessages.count, 1)
    }

    @MainActor
    func testPartialOutputPreservedOnFailure() async throws {
        // Fail after 2 chunks — partial content should remain
        let failingMock = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: ["Hello", " World", " More"],
                delayPerChunk: .milliseconds(50),
                failAfterChunks: 2,
                failureError: .remoteError(provider: "mock", message: "Connection lost")
            )
        )
        let container = makeContainer(provider: failingMock)

        container.draft = "Test"
        container.sendDraft()

        await waitForIdle(container)

        // The assistant message should have partial content (2 chunks streamed before failure)
        let assistantMessages = container.messages.filter { $0.role == .assistant }
        XCTAssertGreaterThanOrEqual(assistantMessages.count, 1)

        // The partial content "Hello World" should be preserved (no Error: message since deltas arrived)
        let hasPartialContent = assistantMessages.contains { $0.content.contains("Hello") }
        XCTAssertTrue(hasPartialContent)
    }

    @MainActor
    func testUnstructuredRemoteFailureStillSurfacesProviderIdentity() async throws {
        let provider = UnstructuredErrorProvider(id: "mock")
        let container = makeContainer(provider: provider)

        container.draft = "Hello"
        container.sendDraft()

        await waitForIdle(container)

        let errorMessages = container.messages.filter {
            $0.role == .assistant && $0.content.contains("Remote error from 'mock'")
        }
        XCTAssertEqual(errorMessages.count, 1)
        XCTAssertTrue(errorMessages[0].content.contains("socket closed"))
        XCTAssertTrue(container.statusMessage.contains("Remote error from 'mock'"))
    }
}
