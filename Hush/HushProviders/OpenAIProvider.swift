import Foundation
import os

private let logger = Logger(subsystem: "com.hush.app", category: "OpenAIProvider")

public struct OpenAIProvider: LLMProvider, Sendable {
    public let id: String
    private let httpClient: any HTTPClient

    public static let defaultEndpoint = "https://api.openai.com/v1"

    public init(id: String = "openai", httpClient: any HTTPClient = URLSessionHTTPClient()) {
        self.id = id
        self.httpClient = httpClient
    }

    // MARK: - Model Discovery

    public func availableModels(context: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        guard let token = context.bearerToken, !token.isEmpty else {
            throw RequestError.credentialResolution(
                providerID: id,
                providerName: nil,
                message: "Bearer token is required for OpenAI provider"
            )
        }

        let baseURL = try Self.normalizedEndpoint(context.endpoint, providerID: id)
        let url = "\(baseURL)/models"
        var request = HTTPRequest(method: "GET", url: url)
        request.setBearerAuth(token)

        let maskedToken = String(token.prefix(6)) + "***" + String(token.suffix(4))
        logger.notice("[CatalogRefresh] GET \(url)")
        logger.notice("[CatalogRefresh] Headers: Authorization=Bearer \(maskedToken)")

        let (data, statusCode) = try await mapHTTPError { try await httpClient.sendJSON(request) }

        let bodyPreview = String(data: data.prefix(2048), encoding: .utf8) ?? "<non-utf8>"
        logger.notice("[CatalogRefresh] Response status: \(statusCode)")
        logger.notice("[CatalogRefresh] Response body (\(data.count) bytes): \(bodyPreview)")

        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        logger.notice("[CatalogRefresh] Decoded \(response.data.count) models")
        return response.data.map { model in
            Self.normalizeOpenAIModel(model)
        }
    }

    // MARK: - Streaming Chat Generation

    // swiftlint:disable async_without_await
    public func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ChatMessage {
        throw RequestError.remoteError(
            provider: id,
            message: "Non-streaming send is not supported; use sendStreaming"
        )
    }

    // swiftlint:enable async_without_await

    public func sendStreaming(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        requestID: RequestID,
        context: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let input = StreamingExecutionInput(
            messages: messages,
            modelID: modelID,
            parameters: parameters,
            requestID: requestID,
            context: context
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                await runStreamingRequest(input, continuation: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private struct StreamingExecutionInput {
        let messages: [ChatMessage]
        let modelID: String
        let parameters: ModelParameters
        let requestID: RequestID
        let context: ProviderInvocationContext
    }

    private func runStreamingRequest(
        _ input: StreamingExecutionInput,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async {
        let providerID = id
        do {
            let request = try makeStreamingRequest(
                messages: input.messages,
                modelID: input.modelID,
                parameters: input.parameters,
                context: input.context,
                providerID: providerID
            )

            continuation.yield(.started(requestID: input.requestID))
            let sseStream = try await httpClient.streamSSE(request)
            logger.info("[Chat] SSE stream started, waiting for events...")

            try await processSSEStream(
                sseStream,
                requestID: input.requestID,
                continuation: continuation
            )
        } catch is CancellationError {
            continuation.finish()
        } catch let error as RequestError {
            finishWithFailure(error, requestID: input.requestID, continuation: continuation)
        } catch let error as HTTPError {
            let mapped = RequestError.remoteError(
                provider: providerID,
                message: error.errorDescription ?? error.localizedDescription
            )
            finishWithFailure(mapped, requestID: input.requestID, continuation: continuation)
        } catch {
            let mapped = RequestError.remoteError(
                provider: providerID,
                message: error.localizedDescription
            )
            finishWithFailure(mapped, requestID: input.requestID, continuation: continuation)
        }
    }

    private func makeStreamingRequest(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        context: ProviderInvocationContext,
        providerID: String
    ) throws -> HTTPRequest {
        guard let token = context.bearerToken, !token.isEmpty else {
            throw RequestError.credentialResolution(
                providerID: providerID,
                providerName: nil,
                message: "Bearer token is required for OpenAI provider"
            )
        }

        let baseURL = try Self.normalizedEndpoint(context.endpoint, providerID: providerID)
        let url = "\(baseURL)/chat/completions"
        logger.info("[Chat] Sending request to: \(url)")

        let useDefaults = parameters.useModelDefaults
        let body = OpenAIChatRequest(
            model: modelID,
            messages: messages.map { OpenAIChatMessage(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            temperature: useDefaults ? nil : parameters.temperature,
            topP: useDefaults ? nil : parameters.topP,
            topK: useDefaults ? nil : parameters.topK,
            maxCompletionTokens: useDefaults ? nil : parameters.maxTokens,
            presencePenalty: useDefaults ? nil : parameters.presencePenalty,
            frequencyPenalty: useDefaults ? nil : parameters.frequencyPenalty,
            reasoningEffort: Self.reasoningEffort(for: modelID, parameters: parameters)
        )

        let bodyData = try JSONEncoder().encode(body)
        var request = HTTPRequest(method: "POST", url: url, body: bodyData)
        request.setBearerAuth(token)
        request.headers["Content-Type"] = "application/json"
        request.headers["Accept"] = "text/event-stream"
        return request
    }

    private func processSSEStream(
        _ sseStream: AsyncThrowingStream<SSEEvent, Error>,
        requestID: RequestID,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var eventCount = 0
        for try await event in sseStream {
            eventCount += 1
            try Task.checkCancellation()
            if processSSEEventData(event.data, requestID: requestID, continuation: continuation) {
                logger.info("[Chat] Stream completed after \(eventCount) events")
                return
            }
        }

        logger.info("[Chat] SSE stream ended naturally after \(eventCount) events")
        continuation.yield(.completed(requestID: requestID))
        continuation.finish()
    }

    private func processSSEEventData(
        _ data: String,
        requestID: RequestID,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) -> Bool {
        // SSE data field may contain multiple lines (per SSE spec, multiple data: lines are joined with \n)
        // Each line could be a separate JSON object, so we need to process them individually
        let dataLines = data.split(separator: "\n", omittingEmptySubsequences: true)

        for dataLine in dataLines {
            let lineStr = String(dataLine)

            if lineStr == "[DONE]" {
                logger.info("[Chat] Received [DONE], completing stream")
                continuation.yield(.completed(requestID: requestID))
                continuation.finish()
                return true
            }

            guard let eventData = lineStr.data(using: .utf8) else {
                continue
            }

            do {
                let chunk = try JSONDecoder().decode(OpenAIChatChunk.self, from: eventData)
                if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                    continuation.yield(.delta(requestID: requestID, text: content))
                }
            } catch {
                logger.warning("[Chat] Failed to decode chunk: \(error.localizedDescription), raw: \(lineStr.prefix(300))")
            }
        }

        return false
    }

    private func finishWithFailure(
        _ error: RequestError,
        requestID: RequestID,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) {
        continuation.yield(.failed(requestID: requestID, error: error))
        continuation.finish()
    }

    // MARK: - Endpoint Validation

    private static let invalidPathSuffixes = [
        "/chat/completions",
        "/models",
        "/embeddings",
        "/completions"
    ]

    private static func normalizedEndpoint(_ raw: String, providerID: String) throws -> String {
        if raw.isEmpty {
            return defaultEndpoint
        }

        let lowered = raw.lowercased()
        for suffix in invalidPathSuffixes where lowered.hasSuffix(suffix) {
            throw RequestError.remoteError(
                provider: providerID,
                message: "Endpoint should be a base URL (e.g. \"\(defaultEndpoint)\"), "
                    + "not a full API path. Remove \"\(suffix)\" from your endpoint."
            )
        }

        if raw.hasSuffix("/") {
            return String(raw.dropLast())
        }
        return raw
    }

    // MARK: - Error Mapping

    private func mapHTTPError<T>(_ block: () async throws -> T) async throws -> T {
        do {
            return try await block()
        } catch let error as HTTPError {
            throw RequestError.remoteError(
                provider: id,
                message: error.errorDescription ?? error.localizedDescription
            )
        }
    }
}

// MARK: - OpenAI Model Normalization

extension OpenAIProvider {
    /// Maps an OpenAI model response to a normalized `ModelDescriptor`.
    /// Handles both ID-only payloads and richer metadata payloads.
    static func normalizeOpenAIModel(_ model: OpenAIModel) -> ModelDescriptor {
        let modelType = inferModelType(from: model)
        let (inputs, outputs) = inferModalities(from: model, modelType: modelType)

        return ModelDescriptor(
            id: model.id,
            displayName: model.id,
            capabilities: outputs.contains(.text) ? [.text] : [.text],
            modelType: modelType,
            supportedInputs: inputs,
            supportedOutputs: outputs,
            rawMetadataJSON: model.rawMetadataJSON
        )
    }

    /// Infer model type from ID patterns and optional metadata.
    private static func inferModelType(from model: OpenAIModel) -> ModelType {
        let lowered = model.id.lowercased()
        if lowered.contains("embedding") { return .embedding }
        if lowered.contains("dall-e") || lowered.contains("image") { return .image }
        if lowered.contains("tts") || lowered.contains("whisper") || lowered.contains("audio") { return .audio }
        if supportsReasoningEffort(modelID: model.id) { return .reasoning }
        if lowered.contains("gpt") || lowered.contains("chat") { return .chat }
        return .unknown
    }

    private static func reasoningEffort(
        for modelID: String,
        parameters: ModelParameters
    ) -> ModelReasoningEffort? {
        guard supportsReasoningEffort(modelID: modelID) else { return nil }
        return parameters.reasoningEffort
    }

    private static func supportsReasoningEffort(modelID: String) -> Bool {
        let lowered = modelID.lowercased()
        return lowered.hasPrefix("o1")
            || lowered.hasPrefix("o3")
            || lowered.hasPrefix("o4")
            || lowered.hasPrefix("gpt-5")
    }

    /// Infer input/output modalities from model type and ID patterns.
    private static func inferModalities(
        from model: OpenAIModel,
        modelType: ModelType
    ) -> (inputs: [Modality], outputs: [Modality]) {
        let lowered = model.id.lowercased()

        switch modelType {
        case .embedding:
            return ([.text], [.text])
        case .image:
            return ([.text], [.image])
        case .audio:
            if lowered.contains("tts") {
                return ([.text], [.audio])
            } else if lowered.contains("whisper") {
                return ([.audio], [.text])
            }
            return ([.audio, .text], [.audio, .text])
        case .chat, .reasoning:
            // Vision-capable models accept images
            if lowered.contains("vision") || lowered.contains("4o") || lowered.contains("4-turbo") {
                return ([.text, .image], [.text])
            }
            return ([.text], [.text])
        case .unknown:
            return ([.text], [.text])
        }
    }
}

// MARK: - OpenAI API Models

struct OpenAIModelsResponse: Decodable {
    let data: [OpenAIModel]
}

struct OpenAIModel: Decodable {
    let id: String
    let ownedBy: String?
    let created: Int?
    let rawMetadataJSON: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownedBy = "owned_by"
        case created
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownedBy = try container.decodeIfPresent(String.self, forKey: .ownedBy)
        created = try container.decodeIfPresent(Int.self, forKey: .created)

        let rawContainer = try decoder.container(keyedBy: AnyCodingKey.self)
        var rawMetadata: [String: JSONValue] = [:]
        for key in rawContainer.allKeys where key.stringValue != CodingKeys.id.rawValue {
            rawMetadata[key.stringValue] = try rawContainer.decode(JSONValue.self, forKey: key)
        }
        rawMetadataJSON = Self.encodeRawMetadata(rawMetadata)
    }

    /// Test-only initializer
    init(id: String, ownedBy: String? = nil, created: Int? = nil) {
        self.id = id
        self.ownedBy = ownedBy
        self.created = created
        var rawMetadata: [String: JSONValue] = [:]
        if let ownedBy {
            rawMetadata[CodingKeys.ownedBy.rawValue] = .string(ownedBy)
        }
        if let created {
            rawMetadata[CodingKeys.created.rawValue] = .integer(created)
        }
        rawMetadataJSON = Self.encodeRawMetadata(rawMetadata)
    }

    private static func encodeRawMetadata(_ rawMetadata: [String: JSONValue]) -> String? {
        guard !rawMetadata.isEmpty else { return nil }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(rawMetadata) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private enum JSONValue: Codable, Equatable {
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: any Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [JSONValue] = []
            while !unkeyed.isAtEnd {
                try values.append(unkeyed.decode(JSONValue.self))
            }
            self = .array(values)
            return
        }

        if let keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
            var dictionary: [String: JSONValue] = [:]
            for key in keyed.allKeys {
                dictionary[key.stringValue] = try keyed.decode(JSONValue.self, forKey: key)
            }
            self = .object(dictionary)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .integer(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .number(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .object(value):
            var container = encoder.container(keyedBy: AnyCodingKey.self)
            for (key, nestedValue) in value {
                guard let codingKey = AnyCodingKey(stringValue: key) else { continue }
                try container.encode(nestedValue, forKey: codingKey)
            }
        case let .array(value):
            var container = encoder.unkeyedContainer()
            for nestedValue in value {
                try container.encode(nestedValue)
            }
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIChatMessage]
    let stream: Bool
    let temperature: Double?
    let topP: Double?
    let topK: Int?
    let maxCompletionTokens: Int?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let reasoningEffort: ModelReasoningEffort?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case topP = "top_p"
        case topK = "top_k"
        case maxCompletionTokens = "max_completion_tokens"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case reasoningEffort = "reasoning_effort"
    }
}

struct OpenAIChatMessage: Encodable {
    let role: String
    let content: String
}

struct OpenAIChatChunk: Decodable {
    let choices: [OpenAIChatChoice]
}

struct OpenAIChatChoice: Decodable {
    let delta: OpenAIChatDelta
}

struct OpenAIChatDelta: Decodable {
    let content: String?
    let role: String?
}
