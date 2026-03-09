import Foundation
@testable import Hush
import Testing

struct MockProviderTests {
    private let dummyContext = ProviderInvocationContext(endpoint: "https://mock.test")

    // MARK: - availableModels

    @Test("availableModels returns two fixed descriptors")
    func availableModelsReturnsFixedList() async throws {
        let provider = MockProvider()
        let models = try await provider.availableModels(context: dummyContext)

        #expect(models.count == 2)
        #expect(models[0].id == "mock-text-1")
        #expect(models[0].capabilities == [.text])
        #expect(models[1].id == "mock-vision-1")
        #expect(models[1].capabilities == [.text, .image])
    }

    // MARK: - send (non-streaming)

    @Test("send returns formatted reply with modelID, temperature, and last user content")
    func sendReturnsFormattedReply() async throws {
        let provider = MockProvider()
        let messages = [
            ChatMessage(role: .system, content: "You are helpful"),
            ChatMessage(role: .user, content: "Hello")
        ]

        let reply = try await provider.send(
            messages: messages,
            modelID: "mock-text-1",
            parameters: .standard,
            context: dummyContext
        )

        #expect(reply.role == .assistant)
        #expect(reply.content == "Mock[mock-text-1] temp=0.70: Hello")
    }

    @Test("send with no user message uses empty content fallback")
    func sendNoUserMessageFallback() async throws {
        let provider = MockProvider()
        let messages = [ChatMessage(role: .system, content: "System only")]

        let reply = try await provider.send(
            messages: messages,
            modelID: "test-model",
            parameters: .standard,
            context: dummyContext
        )

        #expect(reply.content == "Mock[test-model] temp=0.70: ")
    }

    // MARK: - MockStreamBehavior.failing factory

    @Test("failing factory sets failAfterChunks and default error")
    func failingFactoryDefaults() {
        let behavior = MockStreamBehavior.failing(after: 2)

        #expect(behavior.failAfterChunks == 2)
        #expect(behavior.failureError == .remoteError(provider: "mock", message: "Simulated failure"))
    }

    @Test("failing factory with custom error preserves it")
    func failingFactoryCustomError() {
        let customError = RequestError.remoteError(provider: "custom", message: "Boom")
        let behavior = MockStreamBehavior.failing(after: 1, error: customError)

        #expect(behavior.failAfterChunks == 1)
        #expect(behavior.failureError == customError)
    }

    // MARK: - sendStreaming with failing behavior

    @Test("sendStreaming with failing(after: 0) emits started then failed, no deltas")
    func streamingFailImmediately() async throws {
        let provider = MockProvider(streamBehavior: .failing(after: 0))
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "m",
            parameters: .standard,
            requestID: requestID,
            context: dummyContext
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 2)
        #expect(events[0] == .started(requestID: requestID))
        if case let .failed(id, error) = events[1] {
            #expect(id == requestID)
            #expect(error == .remoteError(provider: "mock", message: "Simulated failure"))
        } else {
            Issue.record("Expected .failed event, got \(events[1])")
        }
    }

    @Test("sendStreaming with failing(after: 2) emits started, 2 deltas, then failed")
    func streamingFailAfterTwoChunks() async throws {
        let provider = MockProvider(streamBehavior: .failing(after: 2))
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "m",
            parameters: .standard,
            requestID: requestID,
            context: dummyContext
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 4)
        #expect(events[0] == .started(requestID: requestID))
        #expect(events[1] == .delta(requestID: requestID, text: "Mock"))
        #expect(events[2] == .delta(requestID: requestID, text: " response"))
        if case .failed = events[3] {
            // expected
        } else {
            Issue.record("Expected .failed event, got \(events[3])")
        }
    }
}
