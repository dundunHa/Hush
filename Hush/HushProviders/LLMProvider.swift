import Foundation

public protocol LLMProvider: Sendable {
    var id: String { get }
    func availableModels() async throws -> [ModelDescriptor]
    func send(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters
    ) async throws -> ChatMessage

    /// Streaming generation that yields stream events correlated by request ID.
    /// Implementations must yield exactly one terminal event (completed or failed).
    func sendStreaming(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        requestID: RequestID
    ) -> AsyncThrowingStream<StreamEvent, Error>
}
