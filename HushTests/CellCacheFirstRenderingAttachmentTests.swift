import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
struct CellCacheFirstRenderingAttachmentTests {
    private func makeRow(
        content: String,
        isStreaming: Bool,
        role: ChatRole = .assistant,
        id: UUID = UUID(),
        generation: UInt64 = 1,
        attachments: [MessageAttachment] = [],
        debugInfoJSON: String? = nil
    ) -> MessageTableView.RowModel {
        let message = ChatMessage(
            id: id,
            role: role,
            content: content,
            attachments: attachments,
            debugInfoJSON: debugInfoJSON
        )
        return MessageTableView.RowModel(
            message: message,
            isStreaming: isStreaming,
            renderHint: MessageRenderHint(
                conversationID: "conv-1",
                messageID: message.id,
                rankFromLatest: 0,
                isVisible: true,
                switchGeneration: generation
            )
        )
    }

    private func makeAttachment(path: String) -> MessageAttachment {
        MessageAttachment(
            id: UUID(),
            kind: .image,
            localRelativePath: path,
            mimeType: "image/png",
            pixelWidth: 1,
            pixelHeight: 1,
            sha256: "preview-sha-\(path)",
            sourcePrompt: "Draw preview"
        )
    }

    @Test("Attachment preview loads inline image when asset resolves locally")
    func attachmentPreviewLoadsResolvedImage() throws {
        let runtime = MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
            scheduler: ConversationRenderScheduler()
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("inline-preview.png")
        try cellCacheFirstRenderingOnePixelPNGData.write(to: imageURL, options: [.atomic])

        let container = AppContainer.forTesting(
            settings: .testDefault,
            messageAssetStore: PreviewMessageAssetStoreStub(urlsByRelativePath: [
                "inline-preview.png": imageURL
            ])
        )

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("preview-loaded"))
        cell.configure(
            row: makeRow(
                content: "Generated image.",
                isStreaming: false,
                attachments: [makeAttachment(path: "inline-preview.png")]
            ),
            runtime: runtime,
            availableWidth: 600,
            container: container
        )

        #expect(cell.attachmentPreviewVisibleForTesting)
        #expect(cell.attachmentPreviewHasImageForTesting)
        #expect(!cell.attachmentPreviewShowsPlaceholderForTesting)
    }

    @Test("Attachment preview shows placeholder when local image is missing")
    func attachmentPreviewShowsPlaceholderWhenImageMissing() {
        let runtime = MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
            scheduler: ConversationRenderScheduler()
        )

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("preview-missing"))
        cell.configure(
            row: makeRow(
                content: "Generated image.",
                isStreaming: false,
                attachments: [makeAttachment(path: "missing.png")]
            ),
            runtime: runtime,
            availableWidth: 600,
            container: nil
        )

        #expect(cell.attachmentPreviewVisibleForTesting)
        #expect(!cell.attachmentPreviewHasImageForTesting)
        #expect(cell.attachmentPreviewShowsPlaceholderForTesting)
    }

    @Test("Attachment preview recomputes height when width changes")
    func attachmentPreviewRecomputesHeightWhenWidthChanges() throws {
        let runtime = MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
            scheduler: ConversationRenderScheduler()
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("resized-preview.png")
        try cellCacheFirstRenderingOnePixelPNGData.write(to: imageURL, options: [.atomic])

        let container = AppContainer.forTesting(
            settings: .testDefault,
            messageAssetStore: PreviewMessageAssetStoreStub(urlsByRelativePath: [
                "resized-preview.png": imageURL
            ])
        )

        let host = NSView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 840, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.display()
        defer {
            window.contentView = nil
            window.orderOut(nil)
            withExtendedLifetime(window) {}
        }

        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(containerView)
        let containerWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: 840)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            containerView.topAnchor.constraint(equalTo: host.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            containerWidthConstraint
        ])

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("preview-resize"))
        containerView.addSubview(cell)
        NSLayoutConstraint.activate([
            cell.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            cell.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            cell.topAnchor.constraint(equalTo: containerView.topAnchor),
            cell.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        let initialAvailableWidth = min(
            containerView.bounds.width,
            HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2
        )
        cell.configure(
            row: makeRow(
                content: "Generated image.",
                isStreaming: false,
                attachments: [makeAttachment(path: "resized-preview.png")]
            ),
            runtime: runtime,
            availableWidth: initialAvailableWidth,
            container: container
        )
        host.layoutSubtreeIfNeeded()
        let initialHeight = cell.attachmentPreviewRenderedHeightForTesting

        containerWidthConstraint.constant = 360
        host.layoutSubtreeIfNeeded()

        #expect(cell.attachmentPreviewRenderedHeightForTesting < initialHeight)
    }

    @Test("Error message with debug info shows debug action button")
    func errorMessageWithDebugInfoShowsDebugButton() {
        let runtime = MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
            scheduler: ConversationRenderScheduler()
        )

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("debug-button"))
        cell.configure(
            row: makeRow(
                content: "Error: HTTP 500",
                isStreaming: false,
                debugInfoJSON: #"{"requestURL":"https://example.invalid"}"#
            ),
            runtime: runtime,
            availableWidth: 600,
            container: nil
        )

        #expect(cell.debugButtonVisibleForTesting)
    }

    @Test("User message with debug info shows trace button")
    func userMessageWithDebugInfoShowsTraceButton() {
        let runtime = MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
            scheduler: ConversationRenderScheduler()
        )

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("user-debug-button"))
        cell.configure(
            row: makeRow(
                content: "Why did this request fail?",
                isStreaming: false,
                role: .user,
                debugInfoJSON: #"{"requestURL":"https://example.invalid/v1/chat/completions"}"#
            ),
            runtime: runtime,
            availableWidth: 600,
            container: nil
        )

        #expect(cell.debugButtonVisibleForTesting)
    }
}

private let cellCacheFirstRenderingOnePixelPNGData =
    Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jxM8AAAAASUVORK5CYII=") ?? Data()

private final class PreviewMessageAssetStoreStub: MessageAssetStore, @unchecked Sendable {
    private let urlsByRelativePath: [String: URL]

    init(urlsByRelativePath: [String: URL]) {
        self.urlsByRelativePath = urlsByRelativePath
    }

    func materialize(
        attachments _: [ProviderResponseAttachment],
        conversationId _: String,
        messageId _: UUID
    ) async throws -> [MessageAttachment] {
        await Task.yield()
        return []
    }

    func deleteAllAssets() throws {}

    func url(forRelativePath relativePath: String) -> URL? {
        urlsByRelativePath[relativePath]
    }
}
