import Foundation

/// Configuration for controllable mock streaming behavior.
public struct MockStreamBehavior: Sendable {
    public let chunks: [String]
    public let delayPerChunk: Duration
    public let failAfterChunks: Int?
    public let failureError: RequestError?

    public init(
        chunks: [String] = ["Mock", " response", " streaming"],
        delayPerChunk: Duration = .milliseconds(50),
        failAfterChunks: Int? = nil,
        failureError: RequestError? = nil
    ) {
        self.chunks = chunks
        self.delayPerChunk = delayPerChunk
        self.failAfterChunks = failAfterChunks
        self.failureError = failureError
    }

    public static let `default` = MockStreamBehavior()

    public static func failing(
        after chunks: Int = 0,
        error: RequestError = .remoteError(provider: "mock", message: "Simulated failure")
    ) -> MockStreamBehavior {
        MockStreamBehavior(
            failAfterChunks: chunks,
            failureError: error
        )
    }
}

public struct MockProvider: LLMProvider {
    public let id: String
    public let streamBehavior: MockStreamBehavior

    public init(id: String = "mock", streamBehavior: MockStreamBehavior = .default) {
        self.id = id
        self.streamBehavior = streamBehavior
    }

    public func availableModels() async throws -> [ModelDescriptor] {
        [
            ModelDescriptor(
                id: "mock-text-1",
                displayName: "Mock Text v1",
                capabilities: [.text]
            ),
            ModelDescriptor(
                id: "mock-vision-1",
                displayName: "Mock Vision v1",
                capabilities: [.text, .image]
            )
        ]
    }

    public func send(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters
    ) async throws -> ChatMessage {
        let latestPrompt = messages.last(where: { $0.role == .user })?.content ?? ""
        let reply = "Mock[\(modelID)] temp=\(String(format: "%.2f", parameters.temperature)): \(latestPrompt)"
        return ChatMessage(role: .assistant, content: reply)
    }

    public func sendStreaming(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        requestID: RequestID
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let behavior = streamBehavior
        let providerID = id

        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.started(requestID: requestID))

                for (index, chunk) in behavior.chunks.enumerated() {
                    try Task.checkCancellation()

                    if let failAt = behavior.failAfterChunks, index >= failAt {
                        let error = behavior.failureError ?? .remoteError(
                            provider: providerID,
                            message: "Simulated failure"
                        )
                        continuation.yield(.failed(requestID: requestID, error: error))
                        continuation.finish()
                        return
                    }

                    try await Task.sleep(for: behavior.delayPerChunk)
                    try Task.checkCancellation()

                    continuation.yield(.delta(requestID: requestID, text: chunk))
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
