import Foundation

// MARK: - Request Identity

public struct RequestID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let value: UUID

    public init() {
        self.value = UUID()
    }

    public init(value: UUID) {
        self.value = value
    }

    public var description: String { value.uuidString }
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
    case providerMissing(providerID: String)
    case providerDisabled(providerID: String)
    case providerNotRegistered(providerID: String)
    case modelInvalid(modelID: String, providerID: String)
    case preflightTimeout(seconds: Double)
    case generationTimeout(seconds: Double)
    case remoteError(provider: String, message: String)
    case queueFull(capacity: Int)
    case cancelled
}

extension RequestError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .providerMissing(let id):
            "Provider '\(id)' not found in configuration"
        case .providerDisabled(let id):
            "Provider '\(id)' is disabled"
        case .providerNotRegistered(let id):
            "No runtime implementation registered for provider '\(id)'"
        case .modelInvalid(let modelID, let providerID):
            "Model '\(modelID)' is not available from provider '\(providerID)'"
        case .preflightTimeout(let seconds):
            "Preflight validation timed out after \(String(format: "%.1f", seconds))s"
        case .generationTimeout(let seconds):
            "Generation timed out after \(String(format: "%.0f", seconds))s"
        case .remoteError(let provider, let message):
            "Remote error from '\(provider)': \(message)"
        case .queueFull(let capacity):
            "Request queue is full (max \(capacity))"
        case .cancelled:
            "Request was cancelled"
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
    public var status: ActiveRequestStatus
    public var accumulatedText: String
    public var assistantMessageID: UUID?

    public init(requestID: RequestID) {
        self.requestID = requestID
        self.status = .preflight
        self.accumulatedText = ""
        self.assistantMessageID = nil
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
    public let createdAt: Date

    public init(
        id: RequestID = RequestID(),
        prompt: String,
        providerID: String,
        modelID: String,
        parameters: ModelParameters,
        userMessageID: UUID,
        createdAt: Date = .now
    ) {
        self.id = id
        self.prompt = prompt
        self.providerID = providerID
        self.modelID = modelID
        self.parameters = parameters
        self.userMessageID = userMessageID
        self.createdAt = createdAt
    }
}
