import Foundation

extension OpenAIProvider {
    func executeHTTPRequest(
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

    func mapHTTPError<T>(_ block: () async throws -> T) async throws -> T {
        do {
            return try await block()
        } catch let error as HTTPError {
            throw RequestError.remoteError(
                provider: id,
                message: error.errorDescription ?? error.localizedDescription
            )
        }
    }

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

        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

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
                guard let url = part.imageURL?.url else { continue }
                if let (imageData, mimeType) = parseDataURL(url) {
                    attachments.append(.image(ProviderImageAttachmentPayload(
                        data: imageData,
                        mimeType: mimeType,
                        sourcePrompt: prompt
                    )))
                } else {
                    attachments.append(.image(ProviderImageAttachmentPayload(
                        remoteURL: url,
                        sourcePrompt: prompt
                    )))
                }
            default:
                break
            }
        }
        return (texts.joined(separator: "\n"), attachments)
    }

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
                    data: imageData,
                    mimeType: mimeType,
                    sourcePrompt: prompt
                )))
            }
            if let fullMatchRange = Range(match.range, in: cleanedText) {
                cleanedText.removeSubrange(fullMatchRange)
            }
        }

        return (cleanedText.trimmingCharacters(in: .whitespacesAndNewlines), attachments)
    }

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
                .map { "\($0.key): \($0.value)" }
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

    static func sanitizedHeaders(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { result, entry in
            if entry.key.caseInsensitiveCompare("Authorization") == .orderedSame,
               let token = entry.value.split(separator: " ", maxSplits: 1).last
            {
                result[entry.key] = "Bearer \(mask(token: String(token)))"
            } else {
                result[entry.key] = entry.value
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
           let prettyData = try? JSONSerialization.data(
               withJSONObject: object,
               options: [.prettyPrinted, .sortedKeys]
           )
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
        return "\(String(text.prefix(limit)))... [truncated]"
    }
}
