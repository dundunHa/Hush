import CryptoKit
import Foundation
import UniformTypeIdentifiers

public enum MessageAssetStoreError: Error, Sendable, Equatable {
    case unsupportedAttachment
    case missingImageData
    case invalidRemoteURL(String)
    case downloadFailed(String)
    case unsupportedImageFormat
}

extension MessageAssetStoreError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedAttachment:
            return "Unsupported provider attachment"
        case .missingImageData:
            return "Image generation response did not include image data"
        case let .invalidRemoteURL(url):
            return "Invalid remote image URL: \(url)"
        case let .downloadFailed(message):
            return "Failed to download generated image: \(message)"
        case .unsupportedImageFormat:
            return "Generated image format is unsupported"
        }
    }
}

public final class FileMessageAssetStore: MessageAssetStore, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let fileManager: FileManager

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        fileManager: FileManager = .default
    ) {
        self.baseURL = baseURL
        self.session = session
        self.fileManager = fileManager
    }

    public func materialize(
        attachments: [ProviderResponseAttachment],
        conversationId _: String,
        messageId _: UUID
    ) async throws -> [MessageAttachment] {
        var persisted: [MessageAttachment] = []
        persisted.reserveCapacity(attachments.count)

        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)

        for attachment in attachments {
            switch attachment {
            case let .image(image):
                let resolved = try await resolveImagePayload(image)
                let fileURL = baseURL.appendingPathComponent("\(resolved.sha256).\(resolved.fileExtension)")
                if !fileManager.fileExists(atPath: fileURL.path) {
                    try resolved.data.write(to: fileURL, options: [.atomic])
                }

                let relativePath = fileURL.lastPathComponent
                persisted.append(
                    MessageAttachment(
                        kind: .image,
                        localRelativePath: relativePath,
                        mimeType: resolved.mimeType,
                        pixelWidth: image.pixelWidth,
                        pixelHeight: image.pixelHeight,
                        sha256: resolved.sha256,
                        sourcePrompt: image.sourcePrompt,
                        providerMetadataJSON: image.providerMetadataJSON
                    )
                )
            }
        }

        return persisted
    }

    public func deleteAllAssets() async throws {
        guard fileManager.fileExists(atPath: baseURL.path) else { return }
        try fileManager.removeItem(at: baseURL)
    }

    public func url(forRelativePath relativePath: String) -> URL? {
        guard !relativePath.isEmpty else { return nil }
        return baseURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    private func resolveImagePayload(_ image: ProviderImageAttachmentPayload) async throws -> ResolvedImagePayload {
        if let data = image.data, !data.isEmpty {
            return try makeResolvedImagePayload(data: data, preferredMimeType: image.mimeType)
        }

        guard let remoteURL = image.remoteURL, !remoteURL.isEmpty else {
            throw MessageAssetStoreError.missingImageData
        }
        guard let url = URL(string: remoteURL) else {
            throw MessageAssetStoreError.invalidRemoteURL(remoteURL)
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
                throw MessageAssetStoreError.downloadFailed("non-success response")
            }
            let mimeType = httpResponse.mimeType ?? image.mimeType
            return try makeResolvedImagePayload(data: data, preferredMimeType: mimeType)
        } catch let error as MessageAssetStoreError {
            throw error
        } catch {
            throw MessageAssetStoreError.downloadFailed(error.localizedDescription)
        }
    }

    private func makeResolvedImagePayload(data: Data, preferredMimeType: String?) throws -> ResolvedImagePayload {
        let mimeType = detectMimeType(data: data, preferredMimeType: preferredMimeType)
        let fileExtension = fileExtension(for: mimeType)
        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ResolvedImagePayload(
            data: data,
            mimeType: mimeType,
            fileExtension: fileExtension,
            sha256: sha256
        )
    }

    private func detectMimeType(data: Data, preferredMimeType: String?) -> String {
        if let preferredMimeType, !preferredMimeType.isEmpty {
            return preferredMimeType
        }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]),
           data.count > 12,
           data[8 ... 11].elementsEqual([0x57, 0x45, 0x42, 0x50])
        {
            return "image/webp"
        }
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return "image/gif" }
        return "image/png"
    }

    private func fileExtension(for mimeType: String) -> String {
        if let utType = UTType(mimeType: mimeType), let preferred = utType.preferredFilenameExtension {
            return preferred
        }
        switch mimeType {
        case "image/jpeg":
            return "jpg"
        case "image/webp":
            return "webp"
        case "image/gif":
            return "gif"
        default:
            return "png"
        }
    }
}

private struct ResolvedImagePayload {
    let data: Data
    let mimeType: String
    let fileExtension: String
    let sha256: String
}
