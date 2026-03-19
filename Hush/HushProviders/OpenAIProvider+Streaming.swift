import Foundation
import os

private let streamingLogger = Logger(subsystem: "com.hush.app", category: "OpenAIProvider")

extension OpenAIProvider {
    private struct PreparedStreamingRequest {
        let request: HTTPRequest
        let debugInfo: MessageDebugInfo
    }

    private struct StreamingExecutionInput {
        let messages: [ChatMessage]
        let modelID: String
        let parameters: ModelParameters
        let requestID: RequestID
        let context: ProviderInvocationContext
    }

    // MARK: - Streaming Chat Generation

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

    private func runStreamingRequest(
        _ input: StreamingExecutionInput,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async {
        let providerID = id
        var preparedRequest: PreparedStreamingRequest?

        do {
            preparedRequest = try makeStreamingRequest(
                messages: input.messages,
                modelID: input.modelID,
                parameters: input.parameters,
                context: input.context,
                providerID: providerID
            )

            continuation.yield(.started(requestID: input.requestID))
            if let preparedRequest {
                continuation.yield(.debug(requestID: input.requestID, info: preparedRequest.debugInfo))
            }

            guard let preparedRequest else {
                throw RequestError.remoteError(
                    provider: providerID,
                    message: "Streaming request could not be prepared"
                )
            }

            let streamResponse = try await httpClient.streamSSE(preparedRequest.request)
            let streamOpenInfo = MessageDebugInfo(
                responseStatusCode: streamResponse.statusCode
            ).appendingTraceEvent(
                Self.traceEvent(
                    category: .response,
                    title: "SSE stream opened",
                    summary: "Streaming response accepted with HTTP \(streamResponse.statusCode)",
                    sections: Self.responseSections(
                        statusCode: streamResponse.statusCode,
                        bodyPreview: "Streaming response body is delivered incrementally via SSE."
                    )
                )
            )
            continuation.yield(.debug(requestID: input.requestID, info: streamOpenInfo))
            streamingLogger.info("[Chat] SSE stream started, waiting for events...")

            try await processSSEStream(
                streamResponse.events,
                requestID: input.requestID,
                continuation: continuation
            )
        } catch is CancellationError {
            continuation.finish()
        } catch let error as RequestError {
            finishWithFailure(error, requestID: input.requestID, continuation: continuation)
        } catch let error as HTTPError {
            if let debugInfo = streamingFailureDebugInfo(
                from: error,
                preparedRequest: preparedRequest
            ) {
                continuation.yield(.debug(requestID: input.requestID, info: debugInfo))
            }

            let mapped = RequestError.remoteError(
                provider: providerID,
                message: error.errorDescription ?? error.localizedDescription
            )
            finishWithFailure(mapped, requestID: input.requestID, continuation: continuation)
        } catch {
            if let preparedRequest {
                let failureInfo = MessageDebugInfo(
                    providerError: error.localizedDescription
                ).appendingTraceEvent(
                    Self.traceEvent(
                        category: .error,
                        title: "Streaming request failed",
                        summary: error.localizedDescription
                    )
                )
                continuation.yield(.debug(
                    requestID: input.requestID,
                    info: preparedRequest.debugInfo.merged(with: failureInfo)
                ))
            }

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
    ) throws -> PreparedStreamingRequest {
        guard let token = context.bearerToken, !token.isEmpty else {
            throw RequestError.credentialResolution(
                providerID: providerID,
                providerName: nil,
                message: "Bearer token is required for OpenAI provider"
            )
        }

        let baseURL = try Self.normalizedEndpoint(context.endpoint, providerID: providerID)
        let url = "\(baseURL)/chat/completions"
        streamingLogger.info("[Chat] Sending request to: \(url)")

        let useDefaults = parameters.useModelDefaults
        let body = OpenAIChatRequest(
            model: modelID,
            messages: messages.map { OpenAIChatMessage(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            temperature: useDefaults ? nil : parameters.temperature,
            topP: useDefaults ? nil : parameters.topP,
            topK: useDefaults ? nil : parameters.topK,
            maxCompletionTokens: useDefaults || parameters.maxTokens == 0 ? nil : parameters.maxTokens,
            presencePenalty: useDefaults ? nil : parameters.presencePenalty,
            frequencyPenalty: useDefaults ? nil : parameters.frequencyPenalty,
            reasoningEffort: Self.reasoningEffort(for: modelID, parameters: parameters)
        )

        let bodyData = try JSONEncoder().encode(body)
        var request = HTTPRequest(method: "POST", url: url, body: bodyData)
        request.setBearerAuth(token)
        request.headers["Content-Type"] = "application/json"
        request.headers["Accept"] = "text/event-stream"

        let sanitizedHeaders = Self.sanitizedHeaders(request.headers)
        let requestBodyJSON = Self.prettyPrintedJSON(from: bodyData)
        let debugInfo = MessageDebugInfo(
            providerID: id,
            modelID: modelID,
            requestKind: "chat_completion",
            endpoint: baseURL,
            requestURL: url,
            httpMethod: request.method,
            requestHeaders: sanitizedHeaders,
            requestBodyJSON: requestBodyJSON,
            traceEvents: [
                Self.traceEvent(
                    category: .request,
                    title: "HTTP request prepared",
                    summary: "Prepared streaming chat-completions request",
                    sections: Self.requestSections(
                        method: request.method,
                        url: url,
                        headers: sanitizedHeaders,
                        body: requestBodyJSON
                    )
                )
            ]
        )

        return PreparedStreamingRequest(request: request, debugInfo: debugInfo)
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
                streamingLogger.info("[Chat] Stream completed after \(eventCount) events")
                return
            }
        }

        streamingLogger.info("[Chat] SSE stream ended naturally after \(eventCount) events")
        continuation.yield(.completed(requestID: requestID))
        continuation.finish()
    }

    private func processSSEEventData(
        _ data: String,
        requestID: RequestID,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) -> Bool {
        let dataLines = data.split(separator: "\n", omittingEmptySubsequences: true)

        for dataLine in dataLines {
            let lineStr = String(dataLine)

            if lineStr == "[DONE]" {
                streamingLogger.info("[Chat] Received [DONE], completing stream")
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
                let rawPreview = String(lineStr.prefix(300))
                streamingLogger.warning(
                    "[Chat] Failed to decode chunk: \(error.localizedDescription), raw: \(rawPreview)"
                )
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

    private func streamingFailureDebugInfo(
        from error: HTTPError,
        preparedRequest: PreparedStreamingRequest?
    ) -> MessageDebugInfo? {
        let responseStatusCode: Int?
        let responseBodyPreview: String?

        switch error {
        case let .nonSuccessStatus(code, body, _):
            responseStatusCode = code
            responseBodyPreview = Self.preview(body)
        case .invalidURL, .transportError:
            responseStatusCode = nil
            responseBodyPreview = nil
        }

        let failureInfo = MessageDebugInfo(
            responseStatusCode: responseStatusCode,
            responseBodyPreview: responseBodyPreview,
            providerError: error.errorDescription ?? error.localizedDescription
        ).appendingTraceEvent(
            Self.traceEvent(
                category: .error,
                title: "Streaming request failed",
                summary: error.errorDescription ?? error.localizedDescription,
                sections: Self.responseSections(
                    statusCode: responseStatusCode,
                    bodyPreview: responseBodyPreview
                )
            )
        )

        guard let preparedRequest else {
            return failureInfo
        }
        return preparedRequest.debugInfo.merged(with: failureInfo)
    }
}
