import Foundation
@testable import Hush
import Testing

@MainActor
struct RoutingInvariantTests {
    // MARK: - Helpers

    private func makeContainer(provider: some LLMProvider) -> AppContainer {
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
            activeConversationId: "conv-A"
        )
        container.resetConversation()
        return container
    }

    private func makeContainerWithPersistence(
        provider: some LLMProvider
    ) throws -> AppContainer {
        var registry = ProviderRegistry()
        registry.register(provider)

        let db = try DatabaseManager.inMemory()
        let persistence = ChatPersistenceCoordinator(dbManager: db)

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
            persistence: persistence
        )
        container.resetConversation()
        return container
    }

    private func waitForCompletion(
        _ container: AppContainer,
        timeout: Duration = .seconds(5)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while container.isSending, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - Append Routing

    @Test("appendMessage routes to correct bucket, not active messages if different")
    func appendRouting() {
        let container = makeContainer(provider: MockProvider(id: "mock"))
        container.appendMessage(
            ChatMessage(role: .user, content: "hello A"),
            toConversation: "conv-A"
        )
        container.appendMessage(
            ChatMessage(role: .user, content: "hello B"),
            toConversation: "conv-B"
        )

        let msgsA = container.messagesForConversation("conv-A")
        let msgsB = container.messagesForConversation("conv-B")

        #expect(msgsA.count == 1)
        #expect(msgsA.first?.content == "hello A")
        #expect(msgsB.count == 1)
        #expect(msgsB.first?.content == "hello B")

        #expect(container.messages.count == 1)
        #expect(container.messages.first?.content == "hello A")
    }

    // MARK: - Update Routing

    @Test("updateMessage updates only the owning conversation bucket")
    func updateRouting() {
        let container = makeContainer(provider: MockProvider(id: "mock"))

        let msgA = ChatMessage(role: .assistant, content: "draft-A")
        let msgB = ChatMessage(role: .assistant, content: "draft-B")

        container.appendMessage(msgA, toConversation: "conv-A")
        container.appendMessage(msgB, toConversation: "conv-B")

        container.updateMessage(at: 0, inConversation: "conv-B", content: "final-B")

        #expect(container.messagesForConversation("conv-A").first?.content == "draft-A")
        #expect(container.messagesForConversation("conv-B").first?.content == "final-B")
        #expect(container.messages.first?.content == "draft-A")
    }

    // MARK: - Background Stream Routing

    @Test("Background conversation stream writes deltas to its own bucket")
    func backgroundStreamRouting() async throws {
        let provider = SlowLabeledProvider(id: "mock", deltaText: "bg")
        let container = makeContainer(provider: provider)

        container.sendDraft("send to A")

        let streamDeadline = ContinuousClock.now + .seconds(2)
        while container.messages.last(where: { $0.role == .assistant }) == nil,
              ContinuousClock.now < streamDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }

        try await Task.sleep(for: .milliseconds(50))

        let convA = container.messagesForConversation("conv-A")
        let assistantInA = convA.last(where: { $0.role == .assistant })
        #expect(assistantInA != nil)
        let assistantContent = try #require(assistantInA?.content)
        #expect(!assistantContent.isEmpty)
        #expect("bg".hasPrefix(assistantContent))

        let convB = container.messagesForConversation("conv-B")
        let assistantInB = convB.last(where: { $0.role == .assistant })
        #expect(assistantInB == nil)

        try await waitForCompletion(container)

        let completedAssistantContent = container.messagesForConversation("conv-A")
            .last(where: { $0.role == .assistant })?
            .content
        #expect(completedAssistantContent?.contains("bg") == true)

        container.stopActiveRequest()
    }

    // MARK: - Unread Completion

    @Test("Background completion marks unread, active completion does not")
    func unreadCompletionRouting() {
        let container = makeContainer(provider: MockProvider(id: "mock"))

        container.markUnreadCompletion(forConversation: "conv-A")
        #expect(!container.unreadCompletions.contains("conv-A"))

        container.markUnreadCompletion(forConversation: "conv-B")
        #expect(container.unreadCompletions.contains("conv-B"))

        container.clearUnreadCompletion(forConversation: "conv-B")
        #expect(!container.unreadCompletions.contains("conv-B"))
    }

    // MARK: - Mid-Stream Switch Routing

    @Test("Switching active conversation mid-stream keeps deltas routed to owning conversation")
    func midStreamSwitchRouting() async throws {
        let provider = SlowLabeledProvider(id: "mock", deltaText: "owned")
        let container = try makeContainerWithPersistence(provider: provider)

        container.sendDraft("start stream on A")
        let convA = try #require(container.activeConversationId)

        let streamDeadline = ContinuousClock.now + .seconds(2)
        while container.messages.last(where: { $0.role == .assistant }) == nil,
              ContinuousClock.now < streamDeadline
        {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(container.messages.last(where: { $0.role == .assistant }) != nil)

        let switchTargetId = "conv-switch-target"
        container.activateConversation(conversationId: switchTargetId)

        try await Task.sleep(for: .milliseconds(100))
        #expect(container.activeConversationId == switchTargetId)

        let completionDeadline = ContinuousClock.now + .seconds(5)
        while container.runningConversationIds.contains(convA),
              ContinuousClock.now < completionDeadline
        {
            try await Task.sleep(for: .milliseconds(20))
        }

        let convAMessages = container.messagesForConversation(convA)
        let assistantInA = convAMessages.last(where: { $0.role == .assistant })
        #expect(assistantInA != nil)
        #expect(assistantInA?.content.contains("owned") == true)

        let switchTargetMessages = container.messagesForConversation(switchTargetId)
        let assistantInTarget = switchTargetMessages.last(where: { $0.role == .assistant })
        #expect(assistantInTarget == nil)
    }
}

// MARK: - Test Provider

private actor SlowLabeledProvider: LLMProvider {
    nonisolated let id: String
    let deltaText: String

    init(id: String, deltaText: String) {
        self.id = id
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
        let text = deltaText
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(requestID: requestID))
                for _ in 0 ..< 30 {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(15))
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
