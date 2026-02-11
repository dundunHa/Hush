import Foundation

// MARK: - Request Identity

public struct RequestID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: UUID

    public init() {
        value = UUID()
    }

    public init(value: UUID) {
        self.value = value
    }

    public var description: String {
        value.uuidString
    }
}

// MARK: - Stream Events

public enum StreamEvent: Sendable, Equatable {
    case started(requestID: RequestID)
    case delta(requestID: RequestID, text: String)
    case completed(requestID: RequestID)
    case failed(requestID: RequestID, error: RequestError)
}

// MARK: - Request Error Taxonomy

public enum RequestError: Error, Sendable, Equatable {
    case providerMissing(providerID: String, providerName: String?)
    case providerDisabled(providerID: String, providerName: String?)
    case providerNotRegistered(providerID: String, providerName: String?)
    case modelInvalid(modelID: String, providerID: String, providerName: String?)
    case catalogUnavailable(providerID: String, providerName: String?)
    case preflightTimeout(seconds: Double)
    case generationTimeout(seconds: Double)
    case remoteError(provider: String, message: String)
    case queueFull(capacity: Int)
    case cancelled
    case credentialResolution(providerID: String, providerName: String?, message: String)
}

extension RequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .providerMissing(providerID, providerName):
            "Provider '\(providerName ?? providerID)' not found in configuration"
        case let .providerDisabled(providerID, providerName):
            "Provider '\(providerName ?? providerID)' is disabled"
        case let .providerNotRegistered(providerID, providerName):
            "No runtime implementation registered for provider '\(providerName ?? providerID)'"
        case let .modelInvalid(modelID, providerID, providerName):
            "Model '\(modelID)' is not available from provider '\(providerName ?? providerID)'"
        case let .catalogUnavailable(providerID, providerName):
            "Model catalog unavailable for provider '\(providerName ?? providerID)'. Try refreshing the model list in Settings."
        case let .preflightTimeout(seconds):
            "Preflight validation timed out after \(String(format: "%.1f", seconds))s"
        case let .generationTimeout(seconds):
            "Generation timed out after \(String(format: "%.0f", seconds))s"
        case let .remoteError(provider, message):
            "Remote error from '\(provider)': \(message)"
        case let .queueFull(capacity):
            "Request queue is full (max \(capacity))"
        case .cancelled:
            "Request was cancelled"
        case let .credentialResolution(providerID, providerName, message):
            "Credential error for provider '\(providerName ?? providerID)': \(message)"
        }
    }
}

// MARK: - Active Request State

public enum ActiveRequestStatus: Sendable, Equatable {
    case preflight
    case streaming
    case completed
    case failed(RequestError)
    case stopped
}

public struct ActiveRequestState: Sendable, Equatable {
    public let requestID: RequestID
    public let conversationId: String
    public var status: ActiveRequestStatus
    public var assistantMessageID: UUID?

    private var textChunks: [String] = []
    private var assembledText: String?

    public var accumulatedText: String {
        get {
            assembledText ?? textChunks.joined()
        }
        set {
            textChunks = [newValue]
            assembledText = newValue
        }
    }

    public mutating func appendDelta(_ text: String) {
        textChunks.append(text)
        assembledText = nil
    }

    public mutating func flushText() -> String {
        let result = accumulatedText
        textChunks = [result]
        assembledText = result
        return result
    }

    public init(requestID: RequestID, conversationId: String) {
        self.requestID = requestID
        self.conversationId = conversationId
        status = .preflight
        assembledText = ""
        assistantMessageID = nil
    }

    public var isTerminal: Bool {
        switch status {
        case .completed, .failed, .stopped:
            return true
        case .preflight, .streaming:
            return false
        }
    }
}

// MARK: - Queue Item Snapshot

public struct QueueItemSnapshot: Sendable, Equatable, Identifiable {
    public let id: RequestID
    public let prompt: String
    public let providerID: String
    public let modelID: String
    public let parameters: ModelParameters
    public let userMessageID: UUID
    public let conversationId: String
    public let createdAt: Date

    public init(
        id: RequestID = RequestID(),
        prompt: String,
        providerID: String,
        modelID: String,
        parameters: ModelParameters,
        userMessageID: UUID,
        conversationId: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.prompt = prompt
        self.providerID = providerID
        self.modelID = modelID
        self.parameters = parameters
        self.userMessageID = userMessageID
        self.conversationId = conversationId
        self.createdAt = createdAt
    }
}
