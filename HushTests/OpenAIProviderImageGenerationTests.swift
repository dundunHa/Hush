import Foundation
@testable import Hush
import Testing

extension OpenAIProviderTests {
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
}
