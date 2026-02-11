import Foundation

public enum HTTPError: Error, Sendable, Equatable {
    case nonSuccessStatus(statusCode: Int, body: String?, url: String)
    case invalidURL(String)
    case transportError(String)
}

extension HTTPError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .nonSuccessStatus(code, body, url):
            let bodySnippet = body.map { " — \($0.prefix(200))" } ?? ""
            return "HTTP \(code) from \(url)\(bodySnippet)"
        case let .invalidURL(url):
            return "Invalid URL: \(url)"
        case let .transportError(message):
            return "Transport error: \(message)"
        }
    }
}

public struct HTTPRequest: Sendable {
    public let method: String
    public let url: String
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: String, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }

    public mutating func setBearerAuth(_ token: String) {
        headers["Authorization"] = "Bearer \(token)"
    }
}

public protocol HTTPClient: Sendable {
    func sendJSON(_ request: HTTPRequest) async throws -> (Data, Int)
    func streamSSE(_ request: HTTPRequest) async throws -> AsyncThrowingStream<SSEEvent, Error>
}

public final class URLSessionHTTPClient: HTTPClient, Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func sendJSON(_ request: HTTPRequest) async throws -> (Data, Int) {
        guard let url = URL(string: request.url) else {
            throw HTTPError.invalidURL(request.url)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil, request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPError.transportError("Non-HTTP response")
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8)
                throw HTTPError.nonSuccessStatus(
                    statusCode: httpResponse.statusCode,
                    body: body,
                    url: request.url
                )
            }
            return (data, httpResponse.statusCode)
        } catch let error as HTTPError {
            throw error
        } catch {
            throw HTTPError.transportError(error.localizedDescription)
        }
    }

    public func streamSSE(_ request: HTTPRequest) async throws -> AsyncThrowingStream<SSEEvent, Error> {
        guard let url = URL(string: request.url) else {
            throw HTTPError.invalidURL(request.url)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPError.transportError("Non-HTTP response")
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            var bodyChunks: [UInt8] = []
            for try await byte in bytes {
                bodyChunks.append(byte)
                if bodyChunks.count > 4096 { break }
            }
            let body = String(bytes: bodyChunks, encoding: .utf8)
            throw HTTPError.nonSuccessStatus(
                statusCode: httpResponse.statusCode,
                body: body,
                url: request.url
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var parser = SSEParser()
                do {
                    for try await line in bytes.lines {
                        for event in parser.feedLine(line) {
                            continuation.yield(event)
                        }
                    }
                    for event in parser.feedLine("") {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
