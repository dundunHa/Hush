import Foundation
@testable import Hush
import Testing

@Suite(.serialized)
struct FileMessageAssetStoreTests {
    @Test("materialize writes image data and deduplicates by sha256")
    func materializeWritesAndDeduplicates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileMessageAssetStore(baseURL: directory)
        let payload = ProviderImageAttachmentPayload(
            data: fileMessageAssetStoreOnePixelPNGData,
            mimeType: "image/png",
            pixelWidth: 1,
            pixelHeight: 1,
            sourcePrompt: "Draw a dot"
        )

        let first = try await store.materialize(
            attachments: [.image(payload)],
            conversationId: "conv-1",
            messageId: UUID()
        )
        let second = try await store.materialize(
            attachments: [.image(payload)],
            conversationId: "conv-1",
            messageId: UUID()
        )

        let firstAttachment = try #require(first.first)
        let secondAttachment = try #require(second.first)
        #expect(firstAttachment.localRelativePath == secondAttachment.localRelativePath)
        #expect(firstAttachment.sha256 == secondAttachment.sha256)
        #expect(firstAttachment.mimeType == "image/png")
        #expect(firstAttachment.pixelWidth == 1)
        #expect(firstAttachment.pixelHeight == 1)

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(firstAttachment.localRelativePath).path
        ))
    }

    @Test("materialize downloads remote image when only URL is provided")
    func materializeDownloadsRemoteImage() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FileMessageAssetStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)

        FileMessageAssetStoreURLProtocol.responseHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"]
                )
            )
            return (response, fileMessageAssetStoreOnePixelPNGData)
        }
        defer { FileMessageAssetStoreURLProtocol.responseHandler = nil }

        let store = FileMessageAssetStore(baseURL: directory, session: session)
        let result = try await store.materialize(
            attachments: [
                .image(
                    ProviderImageAttachmentPayload(
                        remoteURL: "https://cdn.example.com/generated.png",
                        sourcePrompt: "Draw a remote image"
                    )
                )
            ],
            conversationId: "conv-remote",
            messageId: UUID()
        )

        let attachment = try #require(result.first)
        #expect(attachment.mimeType == "image/png")
        #expect(attachment.sourcePrompt == "Draw a remote image")
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(attachment.localRelativePath).path
        ))
    }

    @Test("materialize throws when provider attachment omits both data and URL")
    func materializeThrowsWhenPayloadMissing() async {
        let directory = try? makeTemporaryDirectory()
        defer {
            if let directory {
                try? FileManager.default.removeItem(at: directory)
            }
        }

        let store = FileMessageAssetStore(baseURL: directory ?? FileManager.default.temporaryDirectory)
        await #expect(throws: MessageAssetStoreError.self) {
            _ = try await store.materialize(
                attachments: [
                    .image(
                        ProviderImageAttachmentPayload(
                            sourcePrompt: "Missing payload"
                        )
                    )
                ],
                conversationId: "conv-err",
                messageId: UUID()
            )
        }
    }

    @Test("deleteAllAssets removes persisted files")
    func deleteAllAssetsRemovesPersistedFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileMessageAssetStore(baseURL: directory)
        let payload = ProviderImageAttachmentPayload(
            data: fileMessageAssetStoreOnePixelPNGData,
            mimeType: "image/png",
            sourcePrompt: "Draw then delete"
        )

        _ = try await store.materialize(
            attachments: [.image(payload)],
            conversationId: "conv-delete",
            messageId: UUID()
        )

        #expect(FileManager.default.fileExists(atPath: directory.path))

        try await store.deleteAllAssets()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private let fileMessageAssetStoreOnePixelPNGData =
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jxM8AAAAASUVORK5CYII=") ?? Data()

private final class FileMessageAssetStoreURLProtocol: URLProtocol {
    static var responseHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.responseHandler else {
            fatalError("responseHandler not configured")
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
