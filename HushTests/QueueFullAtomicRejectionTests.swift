import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Queue Full — atomic rejection preserves state integrity")
struct QueueFullAtomicRejectionTests {
    // MARK: - Helpers

    private func makeContainer() -> AppContainer {
        var registry = ProviderRegistry()
        registry.register(NeverFinishProvider(id: "mock"))

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
            activeConversationId: "conv-main"
        )
        container.resetConversation()
        return container
    }

    private func fillQueue(_ container: AppContainer) {
        for idx in 0 ..< RuntimeConstants.pendingQueueCapacity {
            let snap = QueueItemSnapshot(
                prompt: "fill-\(idx)",
                providerID: "mock",
                modelID: "mock-text-1",
                parameters: .standard,
                userMessageID: .init(),
                conversationId: "conv-main",
                createdAt: .now
            )
            container.requestCoordinator.submitRequest(snap)
        }
    }

    // MARK: - Rejection Tests

    @Test("sendDraft rejected when queue is full — no user message appended")
    func noUserMessageOnRejection() {
        let container = makeContainer()

        container.sendDraft("seed")
        fillQueue(container)

        let messageCountBefore = container.messages.count
        container.sendDraft("should be rejected")
        let messageCountAfter = container.messages.count

        #expect(messageCountAfter == messageCountBefore)
        #expect(container.statusMessage.contains("Queue full"))
    }

    @Test("sendDraft rejected when queue is full — queue count unchanged")
    func queueCountUnchangedOnRejection() {
        let container = makeContainer()

        container.sendDraft("seed")
        fillQueue(container)

        let queueCountBefore = container.requestCoordinator.totalQueuedCount
        container.sendDraft("overflow")
        let queueCountAfter = container.requestCoordinator.totalQueuedCount

        #expect(queueCountAfter == queueCountBefore)
    }

    @Test("sendDraft rejected when queue is full — draft is preserved")
    func draftPreservedOnRejection() {
        let container = makeContainer()

        container.sendDraft("seed")
        fillQueue(container)

        container.sendDraft("keep me")
    }

    @Test("Scheduler canAcceptSubmission returns false at capacity")
    func schedulerRejectsAtCapacity() {
        var state = SchedulerState()
        for idx in 0 ..< RuntimeConstants.pendingQueueCapacity {
            let snap = QueueItemSnapshot(
                prompt: "fill-\(idx)",
                providerID: "mock",
                modelID: "mock-text-1",
                parameters: .standard,
                userMessageID: .init(),
                conversationId: "conv-\(idx)",
                createdAt: .now
            )
            RequestScheduler.enqueue(snap, activeConversationId: "conv-0", state: &state)
        }

        #expect(!RequestScheduler.canAcceptSubmission(state: state))
    }
}

// MARK: - Test Provider

private actor NeverFinishProvider: LLMProvider {
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
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                }
                continuation.finish(throwing: CancellationError())
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
