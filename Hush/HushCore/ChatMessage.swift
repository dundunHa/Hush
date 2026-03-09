import Foundation

public nonisolated enum ChatRole: String, Codable, CaseIterable, Sendable {
    case system
    case user
    case assistant
    case tool
}

public nonisolated enum MessageAttachmentKind: String, Codable, CaseIterable, Sendable {
    case image
}

public nonisolated struct MessageAttachment: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: MessageAttachmentKind
    public let localRelativePath: String
    public let mimeType: String
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let sha256: String
    public let sourcePrompt: String
    public let providerMetadataJSON: String?

    public init(
        id: UUID = UUID(),
        kind: MessageAttachmentKind,
        localRelativePath: String,
        mimeType: String,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        sha256: String,
        sourcePrompt: String,
        providerMetadataJSON: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.localRelativePath = localRelativePath
        self.mimeType = mimeType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.sha256 = sha256
        self.sourcePrompt = sourcePrompt
        self.providerMetadataJSON = providerMetadataJSON
    }
}

public nonisolated struct MessageDebugInfo: Codable, Equatable, Sendable {
    public var requestID: String?
    public var providerID: String?
    public var modelID: String?
    public var requestKind: String?
    public var routeDecision: String?
    public var endpoint: String?
    public var requestURL: String?
    public var httpMethod: String?
    public var requestHeaders: [String: String]?
    public var requestBodyJSON: String?
    public var responseStatusCode: Int?
    public var responseBodyPreview: String?
    public var providerError: String?
    public var descriptorModelType: String?
    public var descriptorSupportedOutputs: [String]?
    public var descriptorRawMetadataJSON: String?

    public init(
        requestID: String? = nil,
        providerID: String? = nil,
        modelID: String? = nil,
        requestKind: String? = nil,
        routeDecision: String? = nil,
        endpoint: String? = nil,
        requestURL: String? = nil,
        httpMethod: String? = nil,
        requestHeaders: [String: String]? = nil,
        requestBodyJSON: String? = nil,
        responseStatusCode: Int? = nil,
        responseBodyPreview: String? = nil,
        providerError: String? = nil,
        descriptorModelType: String? = nil,
        descriptorSupportedOutputs: [String]? = nil,
        descriptorRawMetadataJSON: String? = nil
    ) {
        self.requestID = requestID
        self.providerID = providerID
        self.modelID = modelID
        self.requestKind = requestKind
        self.routeDecision = routeDecision
        self.endpoint = endpoint
        self.requestURL = requestURL
        self.httpMethod = httpMethod
        self.requestHeaders = requestHeaders
        self.requestBodyJSON = requestBodyJSON
        self.responseStatusCode = responseStatusCode
        self.responseBodyPreview = responseBodyPreview
        self.providerError = providerError
        self.descriptorModelType = descriptorModelType
        self.descriptorSupportedOutputs = descriptorSupportedOutputs
        self.descriptorRawMetadataJSON = descriptorRawMetadataJSON
    }

    public func merged(with other: MessageDebugInfo) -> MessageDebugInfo {
        MessageDebugInfo(
            requestID: other.requestID ?? requestID,
            providerID: other.providerID ?? providerID,
            modelID: other.modelID ?? modelID,
            requestKind: other.requestKind ?? requestKind,
            routeDecision: other.routeDecision ?? routeDecision,
            endpoint: other.endpoint ?? endpoint,
            requestURL: other.requestURL ?? requestURL,
            httpMethod: other.httpMethod ?? httpMethod,
            requestHeaders: mergedHeaders(base: requestHeaders, override: other.requestHeaders),
            requestBodyJSON: other.requestBodyJSON ?? requestBodyJSON,
            responseStatusCode: other.responseStatusCode ?? responseStatusCode,
            responseBodyPreview: other.responseBodyPreview ?? responseBodyPreview,
            providerError: other.providerError ?? providerError,
            descriptorModelType: other.descriptorModelType ?? descriptorModelType,
            descriptorSupportedOutputs: other.descriptorSupportedOutputs ?? descriptorSupportedOutputs,
            descriptorRawMetadataJSON: other.descriptorRawMetadataJSON ?? descriptorRawMetadataJSON
        )
    }

    public func prettyJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func mergedHeaders(
        base: [String: String]?,
        override: [String: String]?
    ) -> [String: String]? {
        guard let override else { return base }
        guard var merged = base else { return override }
        for (key, value) in override {
            merged[key] = value
        }
        return merged
    }
}

public nonisolated struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let role: ChatRole
    public let content: String
    public let attachments: [MessageAttachment]
    public let debugInfoJSON: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        attachments: [MessageAttachment] = [],
        debugInfoJSON: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.debugInfoJSON = debugInfoJSON
        self.createdAt = createdAt
    }

    public func updatingContent(_ content: String) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            attachments: attachments,
            debugInfoJSON: debugInfoJSON,
            createdAt: createdAt
        )
    }

    public func updatingAttachments(_ attachments: [MessageAttachment]) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            attachments: attachments,
            debugInfoJSON: debugInfoJSON,
            createdAt: createdAt
        )
    }

    public func updatingDebugInfo(_ debugInfoJSON: String?) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            attachments: attachments,
            debugInfoJSON: debugInfoJSON,
            createdAt: createdAt
        )
    }
}
