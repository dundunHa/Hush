import Foundation

public struct ProviderInvocationContext: Sendable, Equatable {
    public let endpoint: String
    public let bearerToken: String?

    public init(endpoint: String, bearerToken: String? = nil) {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
    }
}

public protocol LLMProvider: Sendable {
    var id: String { get }
    func availableModels(context: ProviderInvocationContext) async throws -> [ModelDescriptor]
    func send(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        context: ProviderInvocationContext
    ) async throws -> ChatMessage

    /// Streaming generation that yields stream events correlated by request ID.
    /// Implementations must yield exactly one terminal event (completed or failed).
    func sendStreaming(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        requestID: RequestID,
        context: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error>
}
