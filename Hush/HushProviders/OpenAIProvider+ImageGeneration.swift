import Foundation
import os

extension OpenAIProvider {
    private struct ImageRequestDebugContext {
        let modelID: String
        let requestKind: String
        let baseURL: String
        let url: String
        let request: HTTPRequest
        let bodyData: Data
        let summary: String
    }

    func sendDedicatedImageGeneration(
        messages: [ChatMessage],
        modelID: String,
        token: String,
        context: ProviderInvocationContext
    ) async throws -> ProviderResponse {
        guard let prompt = messages.last(where: { $0.role == .user })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !prompt.isEmpty
        else {
            throw ProviderRequestDebugFailure(
                providerID: id,
                message: "Image generation requires a non-empty user prompt",
                debugInfo: MessageDebugInfo(
                    providerID: id,
                    modelID: modelID,
                    requestKind: "image_generation",
                    endpoint: context.endpoint,
                    providerError: "Image generation requires a non-empty user prompt"
                )
            )
        }

        let baseURL = try Self.normalizedEndpoint(context.endpoint, providerID: id)
        let url = "\(baseURL)/images/generations"
        let body = imageGenerationRequestBody(modelID: modelID, prompt: prompt)
        let bodyData = try JSONEncoder().encode(body)
        let httpTimeout = RuntimeConstants.imageGenerationTimeoutSeconds
        var request = HTTPRequest(method: "POST", url: url, body: bodyData, timeoutInterval: httpTimeout)
        request.setBearerAuth(token)
        request.headers["Content-Type"] = "application/json"

        var debugInfo = imageGenerationDebugInfo(
            .init(
                modelID: modelID,
                requestKind: "image_generation",
                baseURL: baseURL,
                url: url,
                request: request,
                bodyData: bodyData,
                summary: "Prepared image generation request"
            )
        )
        openAIProviderLogger.info("[Image] Dedicated image request: model=\(modelID), endpoint=\(url), timeout=\(httpTimeout)s")
        OpenAIProviderDebug.log("Request: \(debugInfo.prettyJSONString() ?? "{}")")

        let requestStart = ContinuousClock.now
        let (data, statusCode) = try await executeHTTPRequest(request, debugInfo: &debugInfo)
        let elapsed = ContinuousClock.now - requestStart
        openAIProviderLogger.info("[Image] Dedicated image response: status=\(statusCode), bytes=\(data.count), elapsed=\(elapsed)")

        applyHTTPResponse(statusCode: statusCode, data: data, to: &debugInfo, summary: "Image generation returned HTTP \(statusCode)")
        OpenAIProviderDebug.log("Response: \(debugInfo.prettyJSONString() ?? "{}")")

        let response = try decodeImageGenerationResponse(data: data, debugInfo: &debugInfo)
        return try buildImageGenerationResponse(
            first: response,
            prompt: prompt,
            debugInfo: debugInfo
        )
    }

    func sendChatBasedImageGeneration(
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
        var debugInfo = imageGenerationDebugInfo(
            .init(
                modelID: modelID,
                requestKind: "chat_image_generation",
                baseURL: baseURL,
                url: url,
                request: request,
                bodyData: bodyData,
                summary: "Prepared chat-completions image request"
            )
        )
        openAIProviderLogger.info("[Image] Chat image request: model=\(modelID), endpoint=\(url), timeout=\(httpTimeout)s")
        OpenAIProviderDebug.log("Chat image request: \(debugInfo.prettyJSONString() ?? "{}")")

        let requestStart = ContinuousClock.now
        let (data, statusCode) = try await executeHTTPRequest(request, debugInfo: &debugInfo)
        let elapsed = ContinuousClock.now - requestStart
        openAIProviderLogger.info("[Image] Chat image response: status=\(statusCode), bytes=\(data.count), elapsed=\(elapsed)")

        applyHTTPResponse(statusCode: statusCode, data: data, to: &debugInfo, summary: "Chat image generation returned HTTP \(statusCode)")
        OpenAIProviderDebug.log("Chat image response: \(debugInfo.prettyJSONString() ?? "{}")")

        let chatResponse = try decodeChatImageResponse(data: data, debugInfo: &debugInfo)
        guard let choice = chatResponse.choices.first else {
            debugInfo.providerError = "Chat image response had no choices"
            throw ProviderRequestDebugFailure(
                providerID: id,
                message: "Chat image response had no choices",
                debugInfo: debugInfo
            )
        }

        let (text, attachments) = Self.extractMultimodalContent(choice.message.content, prompt: prompt)
        openAIProviderLogger.info("[Image] Extracted multimodal content: text=\(text.prefix(100)), attachments=\(attachments.count)")

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

    private func imageGenerationRequestBody(modelID: String, prompt: String) -> OpenAIImageGenerationRequest {
        let isGPTImage = modelID.lowercased().hasPrefix("gpt-image")
        return isGPTImage
            ? OpenAIImageGenerationRequest.forGPTImage(model: modelID, prompt: prompt)
            : OpenAIImageGenerationRequest.forDallE(model: modelID, prompt: prompt)
    }

    private func imageGenerationDebugInfo(_ context: ImageRequestDebugContext) -> MessageDebugInfo {
        MessageDebugInfo(
            providerID: id,
            modelID: context.modelID,
            requestKind: context.requestKind,
            endpoint: context.baseURL,
            requestURL: context.url,
            httpMethod: context.request.method,
            requestHeaders: Self.sanitizedHeaders(context.request.headers),
            requestBodyJSON: Self.prettyPrintedJSON(from: context.bodyData),
            traceEvents: [
                Self.traceEvent(
                    category: .request,
                    title: "HTTP request prepared",
                    summary: context.summary,
                    sections: Self.requestSections(
                        method: context.request.method,
                        url: context.url,
                        headers: Self.sanitizedHeaders(context.request.headers),
                        body: Self.prettyPrintedJSON(from: context.bodyData)
                    )
                )
            ]
        )
    }

    private func applyHTTPResponse(
        statusCode: Int,
        data: Data,
        to debugInfo: inout MessageDebugInfo,
        summary: String
    ) {
        debugInfo.responseStatusCode = statusCode
        debugInfo.responseBodyPreview = Self.preview(data: data)
        debugInfo = debugInfo.appendingTraceEvent(
            Self.traceEvent(
                category: .response,
                title: "HTTP response received",
                summary: summary,
                sections: Self.responseSections(
                    statusCode: statusCode,
                    bodyPreview: debugInfo.responseBodyPreview
                )
            )
        )
    }

    private func decodeImageGenerationResponse(
        data: Data,
        debugInfo: inout MessageDebugInfo
    ) throws -> OpenAIImageGenerationData {
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
                providerID: id,
                message: "Image generation response was empty",
                debugInfo: debugInfo
            )
        }
        return first
    }

    private func buildImageGenerationResponse(
        first: OpenAIImageGenerationData,
        prompt: String,
        debugInfo: MessageDebugInfo
    ) throws -> ProviderResponse {
        let metadataJSON = try? String(data: JSONEncoder().encode(first), encoding: .utf8)

        if let b64JSON = first.b64JSON,
           let imageData = Data(base64Encoded: b64JSON),
           !imageData.isEmpty
        {
            return ProviderResponse(
                text: "Generated image.",
                attachments: [.image(ProviderImageAttachmentPayload(
                    data: imageData,
                    mimeType: "image/png",
                    sourcePrompt: prompt,
                    providerMetadataJSON: metadataJSON
                ))],
                debugInfo: debugInfo
            )
        }

        if let remoteURL = first.url, !remoteURL.isEmpty {
            return ProviderResponse(
                text: "Generated image.",
                attachments: [.image(ProviderImageAttachmentPayload(
                    remoteURL: remoteURL,
                    sourcePrompt: prompt,
                    providerMetadataJSON: metadataJSON
                ))],
                debugInfo: debugInfo
            )
        }

        var failedDebugInfo = debugInfo
        failedDebugInfo.providerError = "Image generation response did not include image data"
        throw ProviderRequestDebugFailure(
            providerID: id,
            message: "Image generation response did not include image data",
            debugInfo: failedDebugInfo
        )
    }

    private func decodeChatImageResponse(
        data: Data,
        debugInfo: inout MessageDebugInfo
    ) throws -> OpenAIChatCompletionResponse {
        do {
            return try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: data)
        } catch {
            debugInfo.providerError = "Failed to decode chat image response: \(error.localizedDescription)"
            throw ProviderRequestDebugFailure(
                providerID: id,
                message: "Chat image generation response could not be decoded",
                debugInfo: debugInfo
            )
        }
    }
}
