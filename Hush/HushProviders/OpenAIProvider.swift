import Foundation
import os

let openAIProviderLogger = Logger(subsystem: "com.hush.app", category: "OpenAIProvider")

enum OpenAIProviderDebug {
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
        openAIProviderLogger.notice("[ImageDebug] \(message, privacy: .public)")
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
        openAIProviderLogger.notice("[CatalogRefresh] GET \(url)")
        openAIProviderLogger.notice("[CatalogRefresh] Headers: Authorization=Bearer \(maskedToken)")

        let (data, statusCode) = try await mapHTTPError { try await httpClient.sendJSON(request) }
        let bodyPreview = String(data: data.prefix(2048), encoding: .utf8) ?? "<non-utf8>"
        openAIProviderLogger.notice("[CatalogRefresh] Response status: \(statusCode)")
        openAIProviderLogger.notice("[CatalogRefresh] Response body (\(data.count) bytes): \(bodyPreview)")

        let response = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        openAIProviderLogger.notice("[CatalogRefresh] Decoded \(response.data.count) models")
        return response.data.map(Self.normalizeOpenAIModel)
    }

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
                messages: messages,
                modelID: modelID,
                token: token,
                context: context
            )
        }

        return try await sendChatBasedImageGeneration(
            messages: messages,
            modelID: modelID,
            parameters: parameters,
            token: token,
            context: context
        )
    }
}
