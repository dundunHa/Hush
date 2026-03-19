import Foundation

public struct ProviderInvocationContext: Sendable, Equatable {
    public let endpoint: String
    public let bearerToken: String?

    public init(endpoint: String, bearerToken: String? = nil) {
        self.endpoint = endpoint
        self.bearerToken = bearerToken
    }
}

public struct ProviderImageAttachmentPayload: Sendable, Equatable {
    public let data: Data?
    public let remoteURL: String?
    public let mimeType: String?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let sourcePrompt: String
    public let providerMetadataJSON: String?

    public init(
        data: Data? = nil,
        remoteURL: String? = nil,
        mimeType: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        sourcePrompt: String,
        providerMetadataJSON: String? = nil
    ) {
        self.data = data
        self.remoteURL = remoteURL
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sourcePrompt = sourcePrompt
        self.providerMetadataJSON = providerMetadataJSON
    }
}

public enum ProviderResponseAttachment: Sendable, Equatable {
    case image(ProviderImageAttachmentPayload)
}

public struct ProviderResponse: Sendable, Equatable {
    public let text: String
    public let attachments: [ProviderResponseAttachment]
    public let debugInfo: MessageDebugInfo?

    public init(
        text: String = "",
        attachments: [ProviderResponseAttachment] = [],
        debugInfo: MessageDebugInfo? = nil
    ) {
        self.text = text
        self.attachments = attachments
        self.debugInfo = debugInfo
    }
}

public struct ProviderRequestDebugFailure: Error, Sendable, Equatable {
    public let providerID: String
    public let message: String
    public let debugInfo: MessageDebugInfo

    public init(
        providerID: String,
        message: String,
        debugInfo: MessageDebugInfo
    ) {
        self.providerID = providerID
        self.message = message
        self.debugInfo = debugInfo
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
    ) async throws -> ProviderResponse

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
