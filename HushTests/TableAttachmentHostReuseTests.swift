import AppKit
@testable import Hush
import Testing

@MainActor
@Suite("Table Attachment Host (Tables Render As Text)")
struct TableAttachmentHostReuseTests {
    private func makeTextView(width: CGFloat) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )

        return textView
    }

    private func apply(content: String, width: CGFloat, to textView: NSTextView, host: TableAttachmentHost) {
        let renderer = MessageContentRenderer()
        let output = renderer.render(
            MessageRenderInput(
                content: content,
                availableWidth: width,
                isStreaming: false
            )
        )

        textView.frame.size.width = width
        textView.textStorage?.setAttributedString(output.attributedString)
        textView.textContainer?.containerSize = NSSize(
            width: width,
            height: CGFloat.greatestFiniteMagnitude
        )
        if let textContainer = textView.textContainer {
            textView.layoutManager?.ensureLayout(for: textContainer)
        }

        host.reconcile(in: textView)
    }

    private func tableViews(in textView: NSTextView) -> [TableScrollContainer] {
        textView.subviews.compactMap { $0 as? TableScrollContainer }
    }

    @Test("Reconcile does not create table subviews when tables render as monospace text")
    func reconcileNoOpsWhenTablesRenderAsText() {
        let host = TableAttachmentHost()
        let textView = makeTextView(width: 600)

        apply(content: RenderingFixtures.Tables.simple, width: 600, to: textView, host: host)
        #expect(tableViews(in: textView).isEmpty)
        #expect(host.managedViewsByKey.isEmpty)

        apply(content: RenderingFixtures.Tables.simple, width: 600, to: textView, host: host)
        #expect(tableViews(in: textView).isEmpty)
        #expect(host.managedViewsByKey.isEmpty)
    }
}
