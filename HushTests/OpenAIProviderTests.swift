import Foundation
@testable import Hush
import Testing

// swiftlint:disable file_length

private final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    nonisolated(unsafe) var sendJSONHandler: ((HTTPRequest) async throws -> (Data, Int))?
    nonisolated(unsafe) var streamSSEHandler: ((HTTPRequest) async throws -> AsyncThrowingStream<SSEEvent, Error>)?

    func sendJSON(_ request: HTTPRequest) async throws -> (Data, Int) {
        guard let handler = sendJSONHandler else {
            fatalError("sendJSONHandler not configured")
        }
        return try await handler(request)
    }

    func streamSSE(_ request: HTTPRequest) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        guard let handler = streamSSEHandler else {
            fatalError("streamSSEHandler not configured")
        }
        return try await handler(request)
    }
}

private actor RequestBodyCapture {
    private var bodyData: Data?

    func store(_ bodyData: Data) {
        self.bodyData = bodyData
    }

    func snapshot() -> Data? {
        bodyData
    }
}

private let onePixelPNGBase64 =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jxM8AAAAASUVORK5CYII="

struct OpenAIProviderTests {
    private let endpoint = "https://api.openai.com/v1"

    @Test("availableModels returns parsed model descriptors")
    func availableModelsSuccess() async throws {
        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"},{"id":"gpt-3.5-turbo"}]}"#
        client.sendJSONHandler = { _ in
            (Data(json.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let models = try await provider.availableModels(context: context)

        #expect(models.count == 2)
        #expect(models[0].id == "gpt-4")
        #expect(models[1].id == "gpt-3.5-turbo")
    }

    @Test("availableModels throws when bearer token is missing")
    func availableModelsMissingToken() async {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: nil)

        await #expect(throws: RequestError.self) {
            _ = try await provider.availableModels(context: context)
        }
    }

    @Test("sendStreaming yields started, delta, and completed events")
    func streamingChatSuccess() async throws {
        let client = FakeHTTPClient()
        client.streamSSEHandler = { request in
            #expect(request.url == "https://api.openai.com/v1/chat/completions")
            #expect(request.method == "POST")
            return AsyncThrowingStream { continuation in
                let chunk = #"{"choices":[{"delta":{"content":"Hello"}}]}"#
                continuation.yield(SSEEvent(data: chunk))
                continuation.yield(SSEEvent(data: "[DONE]"))
                continuation.finish()
            }
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 3)
        #expect(events[0] == .started(requestID: requestID))
        #expect(events[1] == .delta(requestID: requestID, text: "Hello"))
        #expect(events[2] == .completed(requestID: requestID))
    }

    @Test("sendStreaming yields failed event on non-2xx HTTP response")
    func streamingChatHTTPError() async throws {
        let client = FakeHTTPClient()
        client.streamSSEHandler = { request in
            throw HTTPError.nonSuccessStatus(statusCode: 429, body: "rate limited", url: request.url)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let hasFailed = events.contains(where: {
            if case .failed = $0 { return true }
            return false
        })
        #expect(hasFailed)
    }

    @Test("Non-content deltas (role-only, tool metadata) are silently skipped")
    func nonContentDeltasIgnored() async throws {
        let client = FakeHTTPClient()
        client.streamSSEHandler = { _ in
            AsyncThrowingStream { continuation in
                let roleOnly = #"{"choices":[{"delta":{"role":"assistant"}}]}"#
                let nullContent = #"{"choices":[{"delta":{"content":null}}]}"#
                let emptyContent = #"{"choices":[{"delta":{"content":""}}]}"#
                let realContent = #"{"choices":[{"delta":{"content":"Real"}}]}"#

                continuation.yield(SSEEvent(data: roleOnly))
                continuation.yield(SSEEvent(data: nullContent))
                continuation.yield(SSEEvent(data: emptyContent))
                continuation.yield(SSEEvent(data: realContent))
                continuation.yield(SSEEvent(data: "[DONE]"))
                continuation.finish()
            }
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        #expect(events.count == 3)
        #expect(events[0] == .started(requestID: requestID))
        #expect(events[1] == .delta(requestID: requestID, text: "Real"))
        #expect(events[2] == .completed(requestID: requestID))
    }

    // MARK: - send (non-streaming)

    @Test("send gpt-image model uses output_format and no n parameter")
    func sendGPTImageModelUsesCorrectFormat() async throws {
        let client = FakeHTTPClient()
        client.sendJSONHandler = { request in
            #expect(request.url == "https://api.openai.com/v1/images/generations")
            #expect(request.method == "POST")
            #expect(request.headers["Authorization"] == "Bearer sk-test")

            let bodyData = try #require(request.body)
            let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(json["model"] as? String == "gpt-image-1")
            #expect(json["prompt"] as? String == "Draw a cat")
            #expect(json["size"] as? String == "1024x1024")
            #expect(json["output_format"] as? String == "png")
            #expect(json["quality"] as? String == "auto")
            #expect(json["n"] == nil)
            #expect(json["response_format"] == nil)

            let response = #"{"data":[{"b64_json":"\#(onePixelPNGBase64)","revised_prompt":"Draw a fluffy cat"}]}"#
            return (Data(response.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")

        let response = try await provider.send(
            messages: [ChatMessage(role: .user, content: "Draw a cat")],
            modelID: "gpt-image-1",
            parameters: .standard,
            context: context
        )

        #expect(response.text == "Generated image.")
        #expect(response.attachments.count == 1)

        guard case let .image(payload) = try #require(response.attachments.first) else {
            Issue.record("Expected image attachment")
            return
        }

        #expect(payload.data == Data(base64Encoded: onePixelPNGBase64))
        #expect(payload.remoteURL == nil)
        #expect(payload.mimeType == "image/png")
        #expect(payload.sourcePrompt == "Draw a cat")
        #expect(payload.providerMetadataJSON?.contains("Draw a fluffy cat") == true)
    }

    @Test("send dall-e model uses response_format and n parameter with size")
    func sendDallEModelUsesCorrectFormat() async throws {
        let client = FakeHTTPClient()
        client.sendJSONHandler = { request in
            let bodyData = try #require(request.body)
            let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(json["model"] as? String == "dall-e-3")
            #expect(json["n"] as? Int == 1)
            #expect(json["size"] as? String == "1024x1024")
            #expect(json["response_format"] as? String == "b64_json")
            #expect(json["output_format"] == nil)
            #expect(json["quality"] == nil)

            let response = #"{"data":[{"b64_json":"\#(onePixelPNGBase64)","revised_prompt":"A sunset"}]}"#
            return (Data(response.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")

        let response = try await provider.send(
            messages: [ChatMessage(role: .user, content: "Draw a sunset")],
            modelID: "dall-e-3",
            parameters: .standard,
            context: context
        )

        #expect(response.attachments.count == 1)
    }

    @Test("send falls back to remote URL when b64_json is absent")
    func sendImageGenerationFallsBackToRemoteURL() async throws {
        let client = FakeHTTPClient()
        client.sendJSONHandler = { request in
            #expect(request.url == "https://api.openai.com/v1/images/generations")
            let response = #"{"data":[{"url":"https://cdn.example.com/generated.png","revised_prompt":"Draw a happy dog"}]}"#
            return (Data(response.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")

        let response = try await provider.send(
            messages: [ChatMessage(role: .user, content: "Draw a dog")],
            modelID: "gpt-image-1",
            parameters: .standard,
            context: context
        )

        #expect(response.attachments.count == 1)

        guard case let .image(payload) = try #require(response.attachments.first) else {
            Issue.record("Expected image attachment")
            return
        }

        #expect(payload.data == nil)
        #expect(payload.remoteURL == "https://cdn.example.com/generated.png")
        #expect(payload.sourcePrompt == "Draw a dog")
        #expect(payload.providerMetadataJSON?.contains("Draw a happy dog") == true)
    }

    @Test("send throws when image response omits both b64_json and url")
    func sendImageGenerationThrowsWhenPayloadMissing() async {
        let client = FakeHTTPClient()
        client.sendJSONHandler = { _ in
            let response = #"{"data":[{"revised_prompt":"Still missing image payload"}]}"#
            return (Data(response.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")

        await #expect(throws: ProviderRequestDebugFailure.self) {
            _ = try await provider.send(
                messages: [ChatMessage(role: .user, content: "Draw a bird")],
                modelID: "gpt-image-1",
                parameters: .standard,
                context: context
            )
        }
    }

    @Test("send surfaces structured debug context when image generation request fails")
    func sendImageGenerationFailureIncludesDebugContext() async {
        let client = FakeHTTPClient()
        client.sendJSONHandler = { request in
            throw HTTPError.nonSuccessStatus(
                statusCode: 500,
                body: #"{"error":{"message":"server error","code":"internal_error"}}"#,
                url: request.url
            )
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")

        do {
            _ = try await provider.send(
                messages: [ChatMessage(role: .user, content: "Draw a bird")],
                modelID: "dall-e-3",
                parameters: .standard,
                context: context
            )
            Issue.record("Expected ProviderRequestDebugFailure")
        } catch let error as ProviderRequestDebugFailure {
            let message = error.message
            #expect(message.contains("/images/generations"))
            #expect(message.contains("HTTP 500"))
            #expect(error.debugInfo.modelID == "dall-e-3")
            #expect(error.debugInfo.requestURL == "https://api.openai.com/v1/images/generations")
            #expect(error.debugInfo.responseStatusCode == 500)
            #expect(error.debugInfo.responseBodyPreview?.contains("internal_error") == true)
            #expect(error.debugInfo.requestBodyJSON?.contains("\"model\" : \"dall-e-3\"") == true)
        } catch {
            Issue.record("Expected ProviderRequestDebugFailure, got \(error.localizedDescription)")
        }
    }

    // MARK: - Chat-Based Image Generation

    @Test("send routes chat-based image model to /chat/completions and parses multimodal parts")
    func chatBasedImageModelParsesMultimodalParts() async throws {
        let client = FakeHTTPClient()
        client.sendJSONHandler = { request in
            #expect(request.url == "https://api.openai.com/v1/chat/completions")
            #expect(request.method == "POST")

            let bodyData = try #require(request.body)
            let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(json["model"] as? String == "gemini-2.0-flash-preview-image-generation")
            #expect(json["stream"] as? Bool == false)

            let response = #"""
            {"choices":[{"message":{"role":"assistant","content":[
                {"type":"text","text":"Here is the image"},
                {"type":"image_url","image_url":{"url":"data:image/png;base64,\#(onePixelPNGBase64)"}}
            ]}}]}
            """#
            return (Data(response.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")

        let response = try await provider.send(
            messages: [ChatMessage(role: .user, content: "Draw a mountain")],
            modelID: "gemini-2.0-flash-preview-image-generation",
            parameters: .standard,
            context: context
        )

        #expect(response.text == "Here is the image")
        #expect(response.attachments.count == 1)
        guard case let .image(payload) = try #require(response.attachments.first) else {
            Issue.record("Expected image attachment")
            return
        }
        #expect(payload.data == Data(base64Encoded: onePixelPNGBase64))
        #expect(payload.mimeType == "image/png")
        #expect(payload.sourcePrompt == "Draw a mountain")
    }

    @Test("send routes chat-based image model with inline data URL in text content")
    func chatBasedImageModelParsesInlineDataURL() async throws {
        let client = FakeHTTPClient()
        client.sendJSONHandler = { _ in
            let response = #"""
            {"choices":[{"message":{"role":"assistant","content":"Generated:\n![img](data:image/png;base64,\#(onePixelPNGBase64))"}}]}
            """#
            return (Data(response.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")

        let response = try await provider.send(
            messages: [ChatMessage(role: .user, content: "Draw a sunset")],
            modelID: "gemini-2.5-flash-image",
            parameters: .standard,
            context: context
        )

        #expect(response.attachments.count == 1)
        guard case let .image(payload) = try #require(response.attachments.first) else {
            Issue.record("Expected image attachment")
            return
        }
        #expect(payload.data == Data(base64Encoded: onePixelPNGBase64))
        #expect(payload.mimeType == "image/png")
    }

    @Test("send chat-based image model with remote URL in content parts")
    func chatBasedImageModelHandlesRemoteURL() async throws {
        let client = FakeHTTPClient()
        client.sendJSONHandler = { _ in
            let response = #"""
            {"choices":[{"message":{"role":"assistant","content":[
                {"type":"text","text":"Here you go"},
                {"type":"image_url","image_url":{"url":"https://cdn.example.com/image.png"}}
            ]}}]}
            """#
            return (Data(response.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")

        let response = try await provider.send(
            messages: [ChatMessage(role: .user, content: "Draw a cat")],
            modelID: "gemini-2.5-flash-image",
            parameters: .standard,
            context: context
        )

        #expect(response.attachments.count == 1)
        guard case let .image(payload) = try #require(response.attachments.first) else {
            Issue.record("Expected image attachment")
            return
        }
        #expect(payload.remoteURL == "https://cdn.example.com/image.png")
        #expect(payload.data == nil)
    }

    // MARK: - sendStreaming token validation

    @Test("sendStreaming with nil token yields failed event")
    func streamingNilTokenFails() async throws {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: nil)
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let hasFailed = events.contains(where: {
            if case .failed = $0 { return true }
            return false
        })
        #expect(hasFailed)
    }

    @Test("sendStreaming with empty string token yields failed event")
    func streamingEmptyTokenFails() async throws {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "")
        let requestID = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4",
            parameters: .standard,
            requestID: requestID,
            context: context
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        let hasFailed = events.contains(where: {
            if case .failed = $0 { return true }
            return false
        })
        #expect(hasFailed)
    }

    @Test("availableModels throws when bearer token is empty string")
    func availableModelsEmptyToken() async {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "")

        await #expect(throws: RequestError.self) {
            _ = try await provider.availableModels(context: context)
        }
    }

    // MARK: - Endpoint normalization

    @Test("endpoint with /chat/completions suffix causes error")
    func endpointWithChatCompletionsSuffix() async throws {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let badEndpoint = "https://api.openai.com/v1/chat/completions"
        let context = ProviderInvocationContext(endpoint: badEndpoint, bearerToken: "sk-test")

        await #expect(throws: RequestError.self) {
            _ = try await provider.availableModels(context: context)
        }
    }

    @Test("endpoint with /models suffix causes error")
    func endpointWithModelsSuffix() async throws {
        let client = FakeHTTPClient()
        let provider = OpenAIProvider(httpClient: client)
        let badEndpoint = "https://api.openai.com/v1/models"
        let context = ProviderInvocationContext(endpoint: badEndpoint, bearerToken: "sk-test")

        await #expect(throws: RequestError.self) {
            _ = try await provider.availableModels(context: context)
        }
    }

    @Test("endpoint with trailing slash is normalized")
    func endpointTrailingSlashNormalized() async throws {
        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"}]}"#
        client.sendJSONHandler = { request in
            #expect(request.url == "https://api.openai.com/v1/models")
            return (Data(json.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(
            endpoint: "https://api.openai.com/v1/",
            bearerToken: "sk-test"
        )

        let models = try await provider.availableModels(context: context)
        #expect(models.count == 1)
    }

    @Test("empty endpoint falls back to default")
    func emptyEndpointUsesDefault() async throws {
        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"}]}"#
        client.sendJSONHandler = { request in
            #expect(request.url.starts(with: "https://api.openai.com/v1"))
            return (Data(json.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: "", bearerToken: "sk-test")

        let models = try await provider.availableModels(context: context)
        #expect(models.count == 1)
    }

    // MARK: - Normalized Metadata Mapping

    @Test("GPT model is classified as chat type")
    func gptModelTypeIsChat() {
        let model = OpenAIModel(id: "gpt-4o")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .chat)
    }

    @Test("Embedding model is classified as embedding type")
    func embeddingModelType() {
        let model = OpenAIModel(id: "text-embedding-3-small")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .embedding)
    }

    @Test("DALL-E model is classified as image type")
    func dalleModelType() {
        let model = OpenAIModel(id: "dall-e-3")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .image)
        #expect(descriptor.capabilities.contains(.image))
        #expect(descriptor.supportedOutputs.contains(.image))
    }

    @Test("Gemini image models classified as image type but NOT routed to /images/generations")
    func geminiImageModelClassification() {
        let flash = OpenAIModel(id: "gemini-2.5-flash-image")
        let flashDescriptor = OpenAIProvider.normalizeOpenAIModel(flash)
        #expect(flashDescriptor.modelType == .image)
        #expect(flashDescriptor.supportedOutputs.contains(.image))
        #expect(!OpenAIProvider.supportsOpenAIImageGenerationEndpoint(modelID: flash.id))

        let preview = OpenAIModel(id: "gemini-2.0-flash-preview-image-generation")
        let previewDescriptor = OpenAIProvider.normalizeOpenAIModel(preview)
        #expect(previewDescriptor.modelType == .image)
        #expect(previewDescriptor.supportedOutputs.contains(.image))
        #expect(!OpenAIProvider.supportsOpenAIImageGenerationEndpoint(modelID: preview.id))
    }

    @Test("Whisper model is classified as audio type")
    func whisperModelType() {
        let model = OpenAIModel(id: "whisper-1")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .audio)
    }

    @Test("o1 model is classified as reasoning type")
    func o1ModelType() {
        let model = OpenAIModel(id: "o1-preview")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .reasoning)
    }

    @Test("Unknown model ID yields unknown type with text defaults")
    func unknownModelDefaults() {
        let model = OpenAIModel(id: "some-custom-model")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.modelType == .unknown)
        #expect(descriptor.supportedInputs == [.text])
        #expect(descriptor.supportedOutputs == [.text])
    }

    @Test("Vision-capable model includes image input modality")
    func visionModelInputModality() {
        let model = OpenAIModel(id: "gpt-4o-mini")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.supportedInputs.contains(.image))
    }

    @Test("ID-only payload produces valid normalized model entry")
    func idOnlyPayloadYieldsValidEntry() {
        let model = OpenAIModel(id: "gpt-4")
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.id == "gpt-4")
        #expect(descriptor.displayName == "gpt-4")
        #expect(!descriptor.capabilities.isEmpty)
        #expect(!descriptor.supportedInputs.isEmpty)
        #expect(!descriptor.supportedOutputs.isEmpty)
    }

    @Test("Richer payload preserves owned_by in raw metadata")
    func richerPayloadPreservesRawMetadata() {
        let model = OpenAIModel(id: "gpt-4", ownedBy: "openai", created: 1_687_882_411)
        let descriptor = OpenAIProvider.normalizeOpenAIModel(model)
        #expect(descriptor.rawMetadataJSON != nil)
        #expect(descriptor.rawMetadataJSON?.contains("openai") == true)
    }

    @Test("availableModels returns normalized metadata from richer payload")
    func availableModelsReturnsNormalizedMetadata() async throws {
        let client = FakeHTTPClient()
        let json = #"""
        {
          "data": [
            {
              "id": "gpt-4",
              "owned_by": "openai",
              "created": 1687882411,
              "modalities": ["text", "image"],
              "limits": { "max_output_tokens": 4096 },
              "deprecated": false
            }
          ]
        }
        """#
        client.sendJSONHandler = { _ in
            (Data(json.utf8), 200)
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        let models = try await provider.availableModels(context: context)

        #expect(models.count == 1)
        #expect(models[0].modelType == .chat)
        #expect(models[0].rawMetadataJSON != nil)
        #expect(models[0].rawMetadataJSON?.contains("\"modalities\"") == true)
        #expect(models[0].rawMetadataJSON?.contains("\"limits\"") == true)
        #expect(models[0].rawMetadataJSON?.contains("\"deprecated\"") == true)
    }
}

struct OpenAIProviderRequestEncodingTests {
    private let endpoint = "https://api.openai.com/v1"

    @Test("sendStreaming encodes max_completion_tokens for manual parameters")
    func streamingUsesMaxCompletionTokensField() async throws {
        let client = FakeHTTPClient()
        let capture = RequestBodyCapture()
        client.streamSSEHandler = { request in
            let bodyData = try #require(request.body)
            await capture.store(bodyData)
            return AsyncThrowingStream { continuation in
                continuation.yield(SSEEvent(data: "[DONE]"))
                continuation.finish()
            }
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        var parameters = ModelParameters.standard
        parameters.maxTokens = 1536

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4o-mini",
            parameters: parameters,
            requestID: RequestID(),
            context: context
        )

        for try await _ in stream {}

        let bodyData = try #require(await capture.snapshot())
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["max_completion_tokens"] as? Int == 1536)
        #expect(json["max_tokens"] == nil)
    }

    @Test("reasoning_effort stays independent when model defaults are enabled")
    func reasoningEffortIndependentFromModelDefaults() async throws {
        let client = FakeHTTPClient()
        let capture = RequestBodyCapture()
        client.streamSSEHandler = { request in
            let bodyData = try #require(request.body)
            await capture.store(bodyData)
            return AsyncThrowingStream { continuation in
                continuation.yield(SSEEvent(data: "[DONE]"))
                continuation.finish()
            }
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        var parameters = ModelParameters.standard
        parameters.useModelDefaults = true
        parameters.reasoningEffort = .high

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "o3-mini",
            parameters: parameters,
            requestID: RequestID(),
            context: context
        )

        for try await _ in stream {}

        let bodyData = try #require(await capture.snapshot())
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["reasoning_effort"] as? String == "high")
        #expect(json["temperature"] == nil)
        #expect(json["top_p"] == nil)
        #expect(json["max_completion_tokens"] == nil)
    }

    @Test("reasoning_effort is omitted for models without reasoning controls")
    func reasoningEffortOmittedForNonReasoningModels() async throws {
        let client = FakeHTTPClient()
        let capture = RequestBodyCapture()
        client.streamSSEHandler = { request in
            let bodyData = try #require(request.body)
            await capture.store(bodyData)
            return AsyncThrowingStream { continuation in
                continuation.yield(SSEEvent(data: "[DONE]"))
                continuation.finish()
            }
        }

        let provider = OpenAIProvider(httpClient: client)
        let context = ProviderInvocationContext(endpoint: endpoint, bearerToken: "sk-test")
        var parameters = ModelParameters.standard
        parameters.reasoningEffort = .high

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "Hi")],
            modelID: "gpt-4o-mini",
            parameters: parameters,
            requestID: RequestID(),
            context: context
        )

        for try await _ in stream {}

        let bodyData = try #require(await capture.snapshot())
        let json = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(json["reasoning_effort"] == nil)
    }
}

// MARK: - Catalog Refresh Service Tests

struct CatalogRefreshServiceTests {
    @Test("Successful refresh persists models and returns success")
    func successfulRefreshPersists() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"},{"id":"gpt-3.5-turbo"}]}"#
        client.sendJSONHandler = { _ in (Data(json.utf8), 200) }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let result = await service.refresh(
            providerID: "openai",
            context: ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")
        )

        #expect(result == .success(modelCount: 2))

        let models = try catalogRepo.models(forProviderID: "openai")
        #expect(models.count == 2)

        let status = try catalogRepo.refreshStatus(forProviderID: "openai")
        #expect(status.lastSuccessAt != nil)
        #expect(status.lastError == nil)
    }

    @Test("Failed refresh records error and preserves existing catalog")
    func failedRefreshRecordsError() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        // First, populate with a successful refresh
        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"}]}"#
        client.sendJSONHandler = { _ in (Data(json.utf8), 200) }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        _ = await service.refresh(
            providerID: "openai",
            context: ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")
        )

        // Now simulate a failure
        client.sendJSONHandler = { _ in throw HTTPError.nonSuccessStatus(statusCode: 500, body: "internal error", url: "test") }
        let failResult = await service.refresh(
            providerID: "openai",
            context: ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")
        )

        if case .failure = failResult {} else {
            Issue.record("Expected failure result")
        }

        // Previous models still available
        let models = try catalogRepo.models(forProviderID: "openai")
        #expect(models.count == 1)

        let status = try catalogRepo.refreshStatus(forProviderID: "openai")
        #expect(status.lastError != nil)
    }

    @Test("Refresh for unregistered provider returns failure")
    func unregisteredProviderFails() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        let registry = ProviderRegistry()

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let result = await service.refresh(
            providerID: "nonexistent",
            context: ProviderInvocationContext(endpoint: "", bearerToken: nil)
        )

        if case .failure = result {} else {
            Issue.record("Expected failure result")
        }
    }

    @Test("Concurrent refreshes for the same provider are coalesced")
    func concurrentRefreshesAreCoalesced() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()
        let provider = SlowCountingProvider(id: "mock")
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let context = ProviderInvocationContext(endpoint: "", bearerToken: nil)

        async let first: CatalogRefreshResult = service.refresh(providerID: "mock", context: context)
        async let second: CatalogRefreshResult = service.refresh(providerID: "mock", context: context)
        let (firstResult, secondResult) = await(first, second)

        #expect(firstResult == .success(modelCount: 1))
        #expect(secondResult == .success(modelCount: 1))
        #expect(await provider.availableModelsCallCount == 1)
    }

    @Test("resolveModels returns cached models without network call")
    func resolveModelsReturnsCachedModels() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        let client = FakeHTTPClient()
        var networkCallCount = 0
        let json = #"{"data":[{"id":"gpt-4"}]}"#
        client.sendJSONHandler = { _ in
            networkCallCount += 1
            return (Data(json.utf8), 200)
        }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        // Pre-populate cache
        try catalogRepo.upsertCatalog(providerID: "openai", models: [
            ModelDescriptor(id: "cached-model", displayName: "Cached Model", capabilities: [.text])
        ])

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let context = ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")

        let (models, fromCache) = await service.resolveModels(providerID: "openai", context: context)

        #expect(fromCache == true)
        #expect(models.count == 1)
        #expect(models[0].id == "cached-model")
        #expect(networkCallCount == 0)
    }

    @Test("resolveModels fetches live when cache is empty")
    func resolveModelsFetchesLiveWhenCacheEmpty() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        let client = FakeHTTPClient()
        let json = #"{"data":[{"id":"gpt-4"},{"id":"gpt-3.5-turbo"}]}"#
        client.sendJSONHandler = { _ in (Data(json.utf8), 200) }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let context = ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")

        let (models, fromCache) = await service.resolveModels(providerID: "openai", context: context)

        #expect(fromCache == false)
        #expect(models.count == 2)
    }

    @Test("resolveModels returns empty on fetch failure with empty cache")
    func resolveModelsReturnsEmptyOnFailure() async throws {
        let db = try DatabaseManager.inMemory()
        let catalogRepo = GRDBProviderCatalogRepository(dbManager: db)
        var registry = ProviderRegistry()

        let client = FakeHTTPClient()
        client.sendJSONHandler = { _ in throw HTTPError.nonSuccessStatus(statusCode: 500, body: "error", url: "test") }
        let provider = OpenAIProvider(id: "openai", httpClient: client)
        registry.register(provider)

        let service = CatalogRefreshService(catalogRepository: catalogRepo, registry: registry)
        let context = ProviderInvocationContext(endpoint: "https://api.openai.com/v1", bearerToken: "sk-test")

        let (models, fromCache) = await service.resolveModels(providerID: "openai", context: context)

        #expect(fromCache == false)
        #expect(models.isEmpty)
    }
}

private actor SlowCountingProvider: LLMProvider {
    nonisolated let id: String
    private(set) var availableModelsCallCount = 0

    init(id: String) {
        self.id = id
    }

    nonisolated func availableModels(context _: ProviderInvocationContext) async throws -> [ModelDescriptor] {
        await incrementCallCount()
        try await Task.sleep(for: .milliseconds(120))
        return [ModelDescriptor(id: "mock-text-1", displayName: "Mock Text 1", capabilities: [.text])]
    }

    private func incrementCallCount() {
        availableModelsCallCount += 1
    }

    nonisolated func send(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        context _: ProviderInvocationContext
    ) async throws -> ProviderResponse { // swiftlint:disable:this async_without_await
        ProviderResponse(text: "unused")
    }

    nonisolated func sendStreaming(
        messages _: [ChatMessage],
        modelID _: String,
        parameters _: ModelParameters,
        requestID: RequestID,
        context _: ProviderInvocationContext
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.started(requestID: requestID))
            continuation.yield(.completed(requestID: requestID))
            continuation.finish()
        }
    }
}

// swiftlint:enable file_length
