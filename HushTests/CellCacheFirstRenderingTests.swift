import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
struct CellCacheFirstRenderingTests {
    private func makeRow(
        content: String,
        isStreaming: Bool,
        id: UUID = UUID(),
        generation: UInt64 = 1,
        attachments: [MessageAttachment] = [],
        debugInfoJSON: String? = nil
    ) -> MessageTableView.RowModel {
        let message = ChatMessage(
            id: id,
            role: .assistant,
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

    @Test("Cache hit sets rich text immediately and does not create RenderController")
    func cacheHitUsesRichImmediately() {
        let renderCache = RenderCache(capacity: 10)
        let renderer = MessageContentRenderer(
            renderCache: renderCache,
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let contentWidth = max(1, availableWidth - HushSpacing.xl * 2)
        let content = "Hello **world**"
        let style = RenderStyle.fromTheme()

        let key = RenderCache.makeKey(content: content, width: contentWidth, style: style)
        let attributed = NSAttributedString(
            string: "Hello world",
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        renderCache.set(key, output: MessageRenderOutput(
            attributedString: attributed,
            plainText: "Hello world",
            diagnostics: []
        ))

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test"))
        cell.configure(
            row: makeRow(content: content, isStreaming: false),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(!cell.hasRenderControllerForTesting)
        let applied = cell.attributedStringForTesting
        let color = applied.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == NSColor.systemRed)
    }

    @Test("Cache-hit rich apply invalidates row height when intrinsic height changes")
    func cacheHitRichApplyInvalidatesRowHeightWhenHeightChanges() async throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let table = MessageTableView()
        let container = AppContainer.forTesting(settings: .testDefault)
        let messageID = try #require(UUID(uuidString: "ABABABAB-7777-7777-7777-777777777777"))
        let seed = ChatMessage(id: messageID, role: .assistant, content: "seed")

        table.apply(
            messages: [seed],
            activeConversationID: "conv-height",
            isActiveConversationSending: true,
            switchGeneration: 1,
            theme: container.settings.theme,
            runtime: runtime,
            container: container
        )
        table.prepareCellForTesting(row: 0)
        table.updateStreamingCell(
            messageID: messageID,
            content: Array(repeating: "line", count: 18).joined(separator: "\n")
        )

        let finalContent = "final **done**"
        let prewarmInput = MessageRenderInput(
            content: finalContent,
            availableWidth: HushSpacing.chatContentMaxWidth,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        )
        await runtime.prewarm(inputs: [prewarmInput])

        table.apply(
            messages: [ChatMessage(id: messageID, role: .assistant, content: finalContent)],
            activeConversationID: "conv-height",
            isActiveConversationSending: false,
            switchGeneration: 1,
            theme: container.settings.theme,
            runtime: runtime,
            container: container
        )
        table.prepareCellForTesting(row: 0)

        let cell = try #require(table.visibleCellForTesting(row: 0))
        #expect(cell.richOutputHeightInvalidationCountForTesting >= 1)
    }

    @Test("Non-streaming render completion writes row height cache")
    func nonStreamingRenderCachesHeight() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let input = MessageRenderInput(
            content: "height cache **content**",
            availableWidth: 560,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        )

        _ = renderer.render(input)
        let cachedHeight = runtime.cachedRowHeight(for: input)

        #expect(cachedHeight != nil)
        #expect((cachedHeight ?? 0) > 0)
    }

    @Test("Cache-first configure sets cached intrinsic height on cache hit")
    func cacheHitSetsCachedIntrinsicHeight() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let availableWidth: CGFloat = 600
        let contentWidth = max(1, availableWidth - HushSpacing.xl * 2)
        let content = "row height **cache-hit**"
        let input = MessageRenderInput(
            content: content,
            availableWidth: contentWidth,
            style: RenderStyle.fromTheme(),
            isStreaming: false
        )
        _ = renderer.render(input)

        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-height-hit"))
        cell.configure(
            row: makeRow(content: content, isStreaming: false),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(cell.cachedIntrinsicHeightForTesting != nil)
    }

    @Test("Cache miss uses plain fallback then updates to rich rendering")
    func cacheMissFallsBackThenUpdates() async {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let content = "Hello **world**"
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test"))
        cell.configure(
            row: makeRow(content: content, isStreaming: false),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(cell.hasRenderControllerForTesting)
        #expect(cell.attributedStringForTesting.string == content)
        #expect(cell.cachedIntrinsicHeightForTesting == nil)

        let deadline = ContinuousClock.now + .seconds(2)
        while cell.attributedStringForTesting.string == content, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(!cell.attributedStringForTesting.string.contains("**"))
    }

    @Test("Render cache eviction removes corresponding row height cache")
    func evictionRemovesRowHeightCacheEntry() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 1),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let style = RenderStyle.fromTheme()
        let inputA = MessageRenderInput(
            content: "A **cached**",
            availableWidth: 500,
            style: style,
            isStreaming: false
        )
        let inputB = MessageRenderInput(
            content: "B **cached**",
            availableWidth: 500,
            style: style,
            isStreaming: false
        )

        _ = renderer.render(inputA)
        #expect(runtime.cachedRowHeight(for: inputA) != nil)

        _ = renderer.render(inputB)
        #expect(runtime.cachedRowHeight(for: inputA) == nil)
        #expect(runtime.cachedRowHeight(for: inputB) != nil)
    }

    @Test("Cancel render work releases RenderController")
    func cancelRenderWorkReleasesController() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let availableWidth: CGFloat = 600
        let content = "Hello **cancel**"
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-cancel"))
        cell.configure(
            row: makeRow(content: content, isStreaming: false),
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(cell.hasRenderControllerForTesting)
        cell.cancelRenderWork()
        #expect(!cell.hasRenderControllerForTesting)
    }

    @Test("Non-streaming output apply guard requires content match")
    func nonStreamingOutputApplyGuardRequiresExactContentMatch() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let cell = MessageTableCellView(identifier: NSUserInterfaceItemIdentifier("test-output-guard-final"))
        let availableWidth: CGFloat = 600
        let messageID = try #require(UUID(uuidString: "C2C2C2C2-7777-7777-7777-777777777777"))
        let finalRow = makeRow(content: "final **done**", isStreaming: false, id: messageID)

        cell.configure(
            row: finalRow,
            runtime: runtime,
            availableWidth: availableWidth,
            container: nil
        )

        #expect(cell.shouldApplyOutputForTesting(
            plainText: "final",
            observedRow: finalRow
        ) == false)
        #expect(cell.shouldApplyOutputForTesting(
            plainText: "final **done**",
            observedRow: finalRow
        ))
    }

    @Test("Width change invalidates height cache entry")
    func widthChangeInvalidatesHeightCache() {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )
        let style = RenderStyle.fromTheme()
        let content = "width-dependent **content**"

        let inputAt500 = MessageRenderInput(
            content: content,
            availableWidth: 500,
            style: style,
            isStreaming: false
        )
        _ = renderer.render(inputAt500)
        #expect(runtime.cachedRowHeight(for: inputAt500) != nil)

        let inputAt600 = MessageRenderInput(
            content: content,
            availableWidth: 600,
            style: style,
            isStreaming: false
        )
        #expect(runtime.cachedRowHeight(for: inputAt600) == nil)
    }

    @Test("Attachment preview loads inline image when asset resolves locally")
    func attachmentPreviewLoadsResolvedImage() throws {
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("inline-preview.png")
        try previewOnePixelPNGData.write(to: imageURL, options: [.atomic])

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
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
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
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let imageURL = directory.appendingPathComponent("resized-preview.png")
        try previewOnePixelPNGData.write(to: imageURL, options: [.atomic])

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

        let initialAvailableWidth = min(containerView.bounds.width, HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2)
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
        let renderer = MessageContentRenderer(
            renderCache: RenderCache(capacity: 10),
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
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
}

private let previewOnePixelPNGData =
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

    func deleteAllAssets() async throws {}

    func url(forRelativePath relativePath: String) -> URL? {
        urlsByRelativePath[relativePath]
    }
}
