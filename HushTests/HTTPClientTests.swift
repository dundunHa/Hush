import Foundation
@testable import Hush
import Testing

@Suite("HTTPClient Data Type Tests")
struct HTTPClientTests {
    @Test("HTTPRequest stores method, url, headers, and body")
    func requestConstruction() {
        let body = Data("hello".utf8)
        let request = HTTPRequest(
            method: "POST",
            url: "https://example.com/api",
            headers: ["X-Custom": "value"],
            body: body
        )

        #expect(request.method == "POST")
        #expect(request.url == "https://example.com/api")
        #expect(request.headers == ["X-Custom": "value"])
        #expect(request.body == body)
    }

    @Test("HTTPRequest defaults to empty headers and nil body")
    func requestDefaults() {
        let request = HTTPRequest(method: "GET", url: "https://example.com")

        #expect(request.headers.isEmpty)
        #expect(request.body == nil)
    }

    @Test("setBearerAuth sets Authorization header")
    func setBearerAuth() {
        var request = HTTPRequest(method: "GET", url: "https://example.com")
        request.setBearerAuth("tok_abc123")

        #expect(request.headers["Authorization"] == "Bearer tok_abc123")
    }

    @Test("setBearerAuth overwrites existing Authorization header")
    func setBearerAuthOverwrite() {
        var request = HTTPRequest(
            method: "GET",
            url: "https://example.com",
            headers: ["Authorization": "Bearer old"]
        )
        request.setBearerAuth("new_token")

        #expect(request.headers["Authorization"] == "Bearer new_token")
    }

    @Test("setBearerAuth preserves other headers")
    func setBearerAuthPreservesHeaders() {
        var request = HTTPRequest(
            method: "GET",
            url: "https://example.com",
            headers: ["Accept": "application/json"]
        )
        request.setBearerAuth("token")

        #expect(request.headers["Accept"] == "application/json")
        #expect(request.headers["Authorization"] == "Bearer token")
    }

    @Test("HTTPError.nonSuccessStatus carries statusCode, body, and url")
    func nonSuccessStatusFields() {
        let error = HTTPError.nonSuccessStatus(statusCode: 401, body: "Unauthorized", url: "https://api.example.com/v1")

        if case let .nonSuccessStatus(code, body, url) = error {
            #expect(code == 401)
            #expect(body == "Unauthorized")
            #expect(url == "https://api.example.com/v1")
        } else {
            Issue.record("Expected nonSuccessStatus")
        }
    }

    @Test("HTTPError.nonSuccessStatus with nil body")
    func nonSuccessStatusNilBody() {
        let error = HTTPError.nonSuccessStatus(statusCode: 500, body: nil, url: "https://api.example.com")

        if case let .nonSuccessStatus(_, body, _) = error {
            #expect(body == nil)
        } else {
            Issue.record("Expected nonSuccessStatus")
        }
    }

    @Test("HTTPError cases are equatable")
    func httpErrorEquatable() {
        let error1 = HTTPError.nonSuccessStatus(statusCode: 404, body: "Not Found", url: "https://x.com")
        let error2 = HTTPError.nonSuccessStatus(statusCode: 404, body: "Not Found", url: "https://x.com")
        let invalidURL = HTTPError.invalidURL("bad")
        let transport = HTTPError.transportError("timeout")

        #expect(error1 == error2)
        #expect(error1 != invalidURL)
        #expect(invalidURL != transport)
    }
}

// MARK: - URLProtocol Stub

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseHandler: ((URLRequest) -> (Data, HTTPURLResponse, Error?))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = StubURLProtocol.responseHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let (data, response, error) = handler(request)
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - URLSessionHTTPClient Behavior Tests

@Suite("URLSessionHTTPClient Behavior Tests", .serialized)
struct URLSessionHTTPClientBehaviorTests {
    private func makeClient() -> URLSessionHTTPClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return URLSessionHTTPClient(session: session)
    }

    @Test("Bearer auth header is sent on request")
    func bearerAuthHeaderSentOnRequest() async throws {
        var capturedRequest: URLRequest?
        StubURLProtocol.responseHandler = { request in
            capturedRequest = request
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("{\"ok\":true}".utf8), response, nil)
        }
        defer { StubURLProtocol.responseHandler = nil }

        var request = HTTPRequest(method: "GET", url: "https://example.com/api")
        request.setBearerAuth("tok_test_123")

        let client = makeClient()
        _ = try await client.sendJSON(request)

        #expect(capturedRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer tok_test_123")
    }

    @Test("Successful JSON response returns data and status code")
    func successfulJSONResponse() async throws {
        let jsonBody = Data("{\"id\":1,\"name\":\"test\"}".utf8)
        StubURLProtocol.responseHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (jsonBody, response, nil)
        }
        defer { StubURLProtocol.responseHandler = nil }

        let client = makeClient()
        let request = HTTPRequest(method: "GET", url: "https://example.com/api")
        let (data, statusCode) = try await client.sendJSON(request)

        #expect(data == jsonBody)
        #expect(statusCode == 200)
    }

    @Test("Non-2xx status throws HTTPError.nonSuccessStatus")
    func nonSuccessStatusThrowsHTTPError() async throws {
        let url = "https://example.com/api/protected"
        StubURLProtocol.responseHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data("Unauthorized".utf8), response, nil)
        }
        defer { StubURLProtocol.responseHandler = nil }

        let client = makeClient()
        let request = HTTPRequest(method: "GET", url: url)

        await #expect(throws: HTTPError.nonSuccessStatus(statusCode: 401, body: "Unauthorized", url: url)) {
            _ = try await client.sendJSON(request)
        }
    }

    @Test("Invalid URL throws HTTPError.invalidURL")
    func invalidURLThrowsHTTPError() async throws {
        let badURL = ""

        let client = makeClient()
        let request = HTTPRequest(method: "GET", url: badURL)

        await #expect(throws: HTTPError.invalidURL(badURL)) {
            _ = try await client.sendJSON(request)
        }
    }
}
