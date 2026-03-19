import Foundation
import os

private let logger = Logger(subsystem: "com.hush.app", category: "OpenAIProvider")

private enum OpenAIProviderDebug {
    static var isEnabled: Bool {
        #if DEBUG
            guard let raw = ProcessInfo.processInfo.environment["HUSH_PROVIDER_DEBUG"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            else {
                return false
            }
            return raw == "1" || raw == "true" || raw == "yes"
        #else
            return false
        #endif
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        logger.notice("[ImageDebug] \(message, privacy: .public)")
        #if DEBUG
            print("[ImageDebug] \(message)")
        #endif
    }
}

public struct OpenAIProvider: LLMProvider, Sendable {
    public let id: String
    let httpClient: any HTTPClient

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

    public func send(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        context: ProviderInvocationContext
    ) async throws -> ProviderResponse {
        guard let token = context.bearerToken, !token.isEmpty else {
            throw RequestError.credentialResolution(
                providerID: id,
                providerName: nil,
                message: "Bearer token is required for OpenAI provider"
            )
        }

        if Self.supportsOpenAIImageGenerationEndpoint(modelID: modelID) {
            return try await sendDedicatedImageGeneration(
                messages: messages, modelID: modelID, token: token, context: context
            )
        }
        return try await sendChatBasedImageGeneration(
            messages: messages, modelID: modelID, parameters: parameters,
            token: token, context: context
        )
    }

    // MARK: - Dedicated Image Generation (/v1/images/generations)

    private func sendDedicatedImageGeneration(
        messages: [ChatMessage],
        modelID: String,
        token: String,
        context: ProviderInvocationContext
    ) async throws -> ProviderResponse {
        guard let prompt = messages.last(where: { $0.role == .user })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty
        else {
            throw ProviderRequestDebugFailure(
                providerID: id,
                message: "Image generation requires a non-empty user prompt",
                debugInfo: MessageDebugInfo(
                    providerID: id, modelID: modelID,
                    requestKind: "image_generation", endpoint: context.endpoint,
                    providerError: "Image generation requires a non-empty user prompt"
                )
            )
        }

        let baseURL = try Self.normalizedEndpoint(context.endpoint, providerID: id)
        let url = "\(baseURL)/images/generations"
        let isGPTImage = modelID.lowercased().hasPrefix("gpt-image")
        let body = isGPTImage
            ? OpenAIImageGenerationRequest.forGPTImage(model: modelID, prompt: prompt)
            : OpenAIImageGenerationRequest.forDallE(model: modelID, prompt: prompt)

        let bodyData = try JSONEncoder().encode(body)
        let httpTimeout = RuntimeConstants.imageGenerationTimeoutSeconds
        var request = HTTPRequest(method: "POST", url: url, body: bodyData, timeoutInterval: httpTimeout)
        request.setBearerAuth(token)
        request.headers["Content-Type"] = "application/json"

        var debugInfo = MessageDebugInfo(
            providerID: id, modelID: modelID, requestKind: "image_generation",
            endpoint: baseURL, requestURL: url, httpMethod: request.method,
            requestHeaders: Self.sanitizedHeaders(request.headers),
            requestBodyJSON: Self.prettyPrintedJSON(from: bodyData),
            traceEvents: [
                Self.traceEvent(
                    category: .request,
                    title: "HTTP request prepared",
                    summary: "Prepared image generation request",
                    sections: Self.requestSections(
                        method: request.method,
                        url: url,
                        headers: Self.sanitizedHeaders(request.headers),
                        body: Self.prettyPrintedJSON(from: bodyData)
                    )
                )
            ]
        )
        logger.info("[Image] Dedicated image request: model=\(modelID), endpoint=\(url), timeout=\(httpTimeout)s")
        OpenAIProviderDebug.log("Request: \(debugInfo.prettyJSONString() ?? "{}")")

        let requestStart = ContinuousClock.now
        let (data, statusCode) = try await executeHTTPRequest(request, debugInfo: &debugInfo)
        let elapsed = ContinuousClock.now - requestStart
        logger.info("[Image] Dedicated image response: status=\(statusCode), bytes=\(data.count), elapsed=\(elapsed)")

        debugInfo.responseStatusCode = statusCode
        debugInfo.responseBodyPreview = Self.preview(data: data)
        debugInfo = debugInfo.appendingTraceEvent(
            Self.traceEvent(
                category: .response,
                title: "HTTP response received",
                summary: "Image generation returned HTTP \(statusCode)",
                sections: Self.responseSections(
                    statusCode: statusCode,
                    bodyPreview: debugInfo.responseBodyPreview
                )
            )
        )
        OpenAIProviderDebug.log("Response: \(debugInfo.prettyJSONString() ?? "{}")")

        let response: OpenAIImageGenerationResponse
        do {
            response = try JSONDecoder().decode(OpenAIImageGenerationResponse.self, from: data)
        } catch {
            debugInfo.providerError = "Failed to decode image generation response: \(error.localizedDescription)"
            throw ProviderRequestDebugFailure(
                providerID: id,
                message: "Image generation response could not be decoded",
                debugInfo: debugInfo
            )
        }
        guard let first = response.data.first else {
            debugInfo.providerError = "Image generation response was empty"
            throw ProviderRequestDebugFailure(
                providerID: id, message: "Image generation response was empty",
                debugInfo: debugInfo
            )
        }

        let metadataJSON = try? String(data: JSONEncoder().encode(first), encoding: .utf8)
        if let b64JSON = first.b64JSON,
           let imageData = Data(base64Encoded: b64JSON), !imageData.isEmpty
        {
            return ProviderResponse(
                text: "Generated image.",
                attachments: [.image(ProviderImageAttachmentPayload(
                    data: imageData, mimeType: "image/png",
                    sourcePrompt: prompt, providerMetadataJSON: metadataJSON
                ))],
                debugInfo: debugInfo
            )
        }
        if let remoteURL = first.url, !remoteURL.isEmpty {
            return ProviderResponse(
                text: "Generated image.",
                attachments: [.image(ProviderImageAttachmentPayload(
                    remoteURL: remoteURL,
                    sourcePrompt: prompt, providerMetadataJSON: metadataJSON
                ))],
                debugInfo: debugInfo
            )
        }
        debugInfo.providerError = "Image generation response did not include image data"
        throw ProviderRequestDebugFailure(
            providerID: id,
            message: "Image generation response did not include image data",
            debugInfo: debugInfo
        )
    }

    // MARK: - Chat-Based Image Generation (/v1/chat/completions, non-streaming)

    private func sendChatBasedImageGeneration(
        messages: [ChatMessage],
        modelID: String,
        parameters: ModelParameters,
        token: String,
        context: ProviderInvocationContext
    ) async throws -> ProviderResponse {
        let baseURL = try Self.normalizedEndpoint(context.endpoint, providerID: id)
        let url = "\(baseURL)/chat/completions"
        let useDefaults = parameters.useModelDefaults
        let body = OpenAIChatRequest(
            model: modelID,
            messages: messages.map { OpenAIChatMessage(role: $0.role.rawValue, content: $0.content) },
            stream: false,
            temperature: useDefaults ? nil : parameters.temperature,
            topP: useDefaults ? nil : parameters.topP,
            topK: useDefaults ? nil : parameters.topK,
            maxCompletionTokens: useDefaults || parameters.maxTokens == 0 ? nil : parameters.maxTokens,
            presencePenalty: useDefaults ? nil : parameters.presencePenalty,
            frequencyPenalty: useDefaults ? nil : parameters.frequencyPenalty,
            reasoningEffort: nil
        )

        let bodyData = try JSONEncoder().encode(body)
        let httpTimeout = RuntimeConstants.imageGenerationTimeoutSeconds
        var request = HTTPRequest(method: "POST", url: url, body: bodyData, timeoutInterval: httpTimeout)
        request.setBearerAuth(token)
        request.headers["Content-Type"] = "application/json"

        let prompt = messages.last(where: { $0.role == .user })?.content ?? ""
        var debugInfo = MessageDebugInfo(
            providerID: id, modelID: modelID, requestKind: "chat_image_generation",
            endpoint: baseURL, requestURL: url, httpMethod: request.method,
            requestHeaders: Self.sanitizedHeaders(request.headers),
            requestBodyJSON: Self.prettyPrintedJSON(from: bodyData),
            traceEvents: [
                Self.traceEvent(
                    category: .request,
                    title: "HTTP request prepared",
                    summary: "Prepared chat-completions image request",
                    sections: Self.requestSections(
                        method: request.method,
                        url: url,
                        headers: Self.sanitizedHeaders(request.headers),
                        body: Self.prettyPrintedJSON(from: bodyData)
                    )
                )
            ]
        )
        logger.info("[Image] Chat image request: model=\(modelID), endpoint=\(url), timeout=\(httpTimeout)s")
        OpenAIProviderDebug.log("Chat image request: \(debugInfo.prettyJSONString() ?? "{}")")

        let requestStart = ContinuousClock.now
        let (data, statusCode) = try await executeHTTPRequest(request, debugInfo: &debugInfo)
        let elapsed = ContinuousClock.now - requestStart
        logger.info("[Image] Chat image response: status=\(statusCode), bytes=\(data.count), elapsed=\(elapsed)")

        debugInfo.responseStatusCode = statusCode
        debugInfo.responseBodyPreview = Self.preview(data: data)
        debugInfo = debugInfo.appendingTraceEvent(
            Self.traceEvent(
                category: .response,
                title: "HTTP response received",
                summary: "Chat image generation returned HTTP \(statusCode)",
                sections: Self.responseSections(
                    statusCode: statusCode,
                    bodyPreview: debugInfo.responseBodyPreview
                )
            )
        )
        OpenAIProviderDebug.log("Chat image response: \(debugInfo.prettyJSONString() ?? "{}")")

        let chatResponse: OpenAIChatCompletionResponse
        do {
            chatResponse = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            debugInfo.providerError = "Failed to decode chat image response: \(error.localizedDescription)"
            throw ProviderRequestDebugFailure(
                providerID: id,
                message: "Chat image generation response could not be decoded",
                debugInfo: debugInfo
            )
        }
        guard let choice = chatResponse.choices.first else {
            debugInfo.providerError = "Chat image response had no choices"
            throw ProviderRequestDebugFailure(
                providerID: id, message: "Chat image response had no choices",
                debugInfo: debugInfo
            )
        }

        let (text, attachments) = Self.extractMultimodalContent(choice.message.content, prompt: prompt)
        logger.info("[Image] Extracted multimodal content: text=\(text.prefix(100)), attachments=\(attachments.count)")

        if attachments.isEmpty {
            debugInfo.providerError = "Chat response did not contain image data"
            throw ProviderRequestDebugFailure(
                providerID: id,
                message: "Chat response did not contain image data",
                debugInfo: debugInfo
            )
        }

        return ProviderResponse(
            text: text.isEmpty ? "Generated image." : text,
            attachments: attachments,
            debugInfo: debugInfo
        )
    }

    // MARK: - Shared HTTP Execution

    private func executeHTTPRequest(
        _ request: HTTPRequest,
        debugInfo: inout MessageDebugInfo
    ) async throws -> (Data, Int) {
        do {
            return try await httpClient.sendJSON(request)
        } catch let error as HTTPError {
            debugInfo.providerError = error.errorDescription ?? error.localizedDescription
            if case let .nonSuccessStatus(code, body, _) = error {
                debugInfo.responseStatusCode = code
                debugInfo.responseBodyPreview = Self.preview(body)
            }
            OpenAIProviderDebug.log("Failure: \(debugInfo.prettyJSONString() ?? "{}")")
            throw ProviderRequestDebugFailure(
                providerID: id,
                message: error.errorDescription ?? error.localizedDescription,
                debugInfo: debugInfo
            )
        } catch {
            debugInfo.providerError = error.localizedDescription
            OpenAIProviderDebug.log("Failure: \(debugInfo.prettyJSONString() ?? "{}")")
            throw ProviderRequestDebugFailure(
                providerID: id,
                message: error.localizedDescription,
                debugInfo: debugInfo
            )
        }
    }

    // MARK: - Multimodal Content Extraction

    static func extractMultimodalContent(
        _ content: ChatMessageContent,
        prompt: String
    ) -> (String, [ProviderResponseAttachment]) {
        switch content {
        case let .text(text):
            let (cleanedText, attachments) = extractInlineDataURLImages(from: text, prompt: prompt)
            return (cleanedText, attachments)
        case let .parts(parts):
            return extractFromContentParts(parts, prompt: prompt)
        }
    }

    private static func extractFromContentParts(
        _ parts: [ChatContentPart],
        prompt: String
    ) -> (String, [ProviderResponseAttachment]) {
        var texts: [String] = []
        var attachments: [ProviderResponseAttachment] = []
        for part in parts {
            switch part.type {
            case "text":
                if let text = part.text, !text.isEmpty {
                    texts.append(text)
                }
            case "image_url":
                if let url = part.imageURL?.url {
                    if let (imageData, mimeType) = parseDataURL(url) {
                        attachments.append(.image(ProviderImageAttachmentPayload(
                            data: imageData, mimeType: mimeType, sourcePrompt: prompt
                        )))
                    } else {
                        attachments.append(.image(ProviderImageAttachmentPayload(
                            remoteURL: url, sourcePrompt: prompt
                        )))
                    }
                }
            default:
                break
            }
        }
        return (texts.joined(separator: "\n"), attachments)
    }

    /// Extracts images from markdown-style inline data URLs: `![alt](data:image/...;base64,...)`
    private static func extractInlineDataURLImages(
        from text: String,
        prompt: String
    ) -> (String, [ProviderResponseAttachment]) {
        var attachments: [ProviderResponseAttachment] = []
        var cleanedText = text

        let dataURLPattern = #"!\[[^\]]*\]\((data:image/[^;]+;base64,[A-Za-z0-9+/=]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: dataURLPattern) else {
            return (text, [])
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let dataURLRange = Range(match.range(at: 1), in: text) else { continue }
            let dataURL = String(text[dataURLRange])
            if let (imageData, mimeType) = parseDataURL(dataURL) {
                attachments.append(.image(ProviderImageAttachmentPayload(
                    data: imageData, mimeType: mimeType, sourcePrompt: prompt
                )))
            }
            if let fullMatchRange = Range(match.range, in: cleanedText) {
                cleanedText.removeSubrange(fullMatchRange)
            }
        }

        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleanedText, attachments)
    }

    /// Parses `data:image/png;base64,iVBOR...` into raw Data + MIME type.
    static func parseDataURL(_ url: String) -> (Data, String)? {
        guard url.hasPrefix("data:") else { return nil }
        guard let semicolonIdx = url.firstIndex(of: ";"),
              url[semicolonIdx...].hasPrefix(";base64,")
        else { return nil }
        let mimeType = String(url[url.index(url.startIndex, offsetBy: 5) ..< semicolonIdx])
        let base64Start = url.index(semicolonIdx, offsetBy: 8)
        let base64String = String(url[base64Start...])
        guard let data = Data(base64Encoded: base64String), !data.isEmpty else { return nil }
        return (data, mimeType)
    }

    static func traceEvent(
        category: MessageTraceEventCategory,
        title: String,
        summary: String? = nil,
        sections: [MessageTraceSection] = []
    ) -> MessageTraceEvent {
        MessageTraceEvent(
            category: category,
            title: title,
            summary: summary,
            sections: sections
        )
    }

    static func requestSections(
        method: String,
        url: String,
        headers: [String: String]?,
        body: String?
    ) -> [MessageTraceSection] {
        var sections: [MessageTraceSection] = [
            MessageTraceSection(title: "Method", content: method),
            MessageTraceSection(title: "URL", content: url)
        ]
        if let headers, !headers.isEmpty {
            let headerText = headers
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { entry in
                    "\(entry.key): \(entry.value)"
                }
                .joined(separator: "\n")
            sections.append(MessageTraceSection(title: "Headers", content: headerText))
        }
        if let body, !body.isEmpty {
            sections.append(MessageTraceSection(title: "Body", content: body))
        }
        return sections
    }

    static func responseSections(
        statusCode: Int?,
        bodyPreview: String?
    ) -> [MessageTraceSection] {
        var sections: [MessageTraceSection] = []
        if let statusCode {
            sections.append(MessageTraceSection(title: "Status", content: String(statusCode)))
        }
        if let bodyPreview, !bodyPreview.isEmpty {
            sections.append(MessageTraceSection(title: "Body Preview", content: bodyPreview))
        }
        return sections
    }

    // MARK: - Endpoint Validation

    private static let invalidPathSuffixes = [
        "/chat/completions",
        "/images/generations",
        "/models",
        "/embeddings",
        "/completions"
    ]

    static func normalizedEndpoint(_ raw: String, providerID: String) throws -> String {
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

    static func sanitizedHeaders(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { result, entry in
            let key = entry.key
            let value = entry.value
            if key.caseInsensitiveCompare("Authorization") == .orderedSame,
               let token = value.split(separator: " ", maxSplits: 1).last
            {
                result[key] = "Bearer \(mask(token: String(token)))"
            } else {
                result[key] = value
            }
        }
    }

    static func mask(token: String) -> String {
        guard token.count > 10 else { return "\(token.prefix(3))***" }
        return String(token.prefix(6)) + "***" + String(token.suffix(4))
    }

    static func prettyPrintedJSON(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(object),
           let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        {
            return preview(data: prettyData)
        }
        return preview(data: data)
    }

    static func preview(data: Data, limit: Int = 4096) -> String? {
        preview(String(data: data.prefix(limit), encoding: .utf8))
    }

    static func preview(_ text: String?, limit: Int = 4096) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if text.count <= limit {
            return text
        }
        let trimmed = String(text.prefix(limit))
        return "\(trimmed)... [truncated]"
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
            capabilities: legacyCapabilities(inputs: inputs, outputs: outputs),
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
        if supportsOpenAIImageGenerationEndpoint(modelID: model.id) { return .image }
        if lowered.contains("image") { return .image }
        if lowered.contains("tts") || lowered.contains("whisper") || lowered.contains("audio") { return .audio }
        if supportsReasoningEffort(modelID: model.id) { return .reasoning }
        if lowered.contains("gpt") || lowered.contains("chat") { return .chat }
        return .unknown
    }

    private static func legacyCapabilities(
        inputs: [Modality],
        outputs: [Modality]
    ) -> [ModelCapability] {
        var capabilities: [ModelCapability] = []
        if inputs.contains(.text) || outputs.contains(.text) {
            capabilities.append(.text)
        }
        if inputs.contains(.image) || outputs.contains(.image) {
            capabilities.append(.image)
        }
        return capabilities.isEmpty ? [.text] : capabilities
    }

    static func supportsOpenAIImageGenerationEndpoint(modelID: String) -> Bool {
        let lowered = modelID.lowercased()
        return lowered.hasPrefix("gpt-image")
            || lowered.hasPrefix("dall-e")
            || lowered.hasPrefix("imagen-")
    }

    static func reasoningEffort(
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
