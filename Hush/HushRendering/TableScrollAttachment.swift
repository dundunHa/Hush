import AppKit

// MARK: - TableScrollAttachment

/// A text attachment that renders a Markdown table as a horizontally scrollable surface.
///
/// Uses TextKit 1 `NSTextAttachmentCell` for layout sizing. The actual scroll view
/// is managed by the hosting `NSTextView` (within `MessageTableCellView`), which
/// embeds the view after layout.
///
/// Architecture note: the host `NSTextView` uses TextKit 1 (`NSLayoutManager`).
/// View-based attachments are implemented via a sizing-only `NSTextAttachmentCell`
/// subclass, with the live `NSScrollView` added as a subview by the host after layout.
final class TableScrollAttachment: NSTextAttachment {
    // MARK: - Properties

    /// The styled table content (monospace attributed string, possibly with math attachments).
    let tableContent: NSAttributedString

    /// Measured height of the table content when rendered without wrapping.
    let contentHeight: CGFloat

    /// Stable signature used by the host view to decide whether a table subview
    /// can be reused across redraws.
    let reuseSignature: UInt64

    // MARK: - Init

    init(
        tableContent: NSAttributedString,
        availableWidth: CGFloat,
        measuredHeight: CGFloat? = nil
    ) {
        self.tableContent = tableContent
        contentHeight = measuredHeight ?? Self.measureHeight(tableContent)
        reuseSignature = Self.makeReuseSignature(
            tableContent: tableContent,
            contentHeight: contentHeight
        )
        super.init(data: nil, ofType: nil)
        attachmentCell = TableScrollSizingCell(
            width: availableWidth,
            height: contentHeight
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    // MARK: - View Factory

    /// Create a new horizontal scroll view displaying the table content.
    func makeScrollView() -> TableScrollContainer {
        let innerTextView = NSTextView()
        innerTextView.isEditable = false
        innerTextView.isSelectable = true
        innerTextView.drawsBackground = false
        innerTextView.isRichText = true
        innerTextView.textContainerInset = NSSize(width: 0, height: 2)

        // Disable wrapping — wide tables stay on one line per row
        innerTextView.isHorizontallyResizable = true
        innerTextView.isVerticallyResizable = false
        innerTextView.textContainer?.widthTracksTextView = false
        innerTextView.textContainer?.heightTracksTextView = false
        innerTextView.textContainer?.lineFragmentPadding = 0
        innerTextView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        innerTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        innerTextView.textStorage?.setAttributedString(tableContent)
        if let textContainer = innerTextView.textContainer,
           let layoutManager = innerTextView.layoutManager
        {
            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let width = max(1, ceil(usedRect.width))
            let height = max(contentHeight, ceil(usedRect.height) + 4)
            innerTextView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }

        let scrollView = TableScrollContainer()
        scrollView.documentView = innerTextView
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.autoresizingMask = []

        // Prevent vertical scrolling from fighting the transcript scroll
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .allowed

        return scrollView
    }

    // MARK: - Private

    private static let fnvOffsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let fnvPrime: UInt64 = 0x0000_0100_0000_01B3

    private static func makeReuseSignature(
        tableContent: NSAttributedString,
        contentHeight: CGFloat
    ) -> UInt64 {
        var hash = fnvOffsetBasis

        for byte in tableContent.string.utf8 {
            hash ^= UInt64(byte)
            hash &*= fnvPrime
        }

        // Separator to avoid ambiguous concatenation before adding height bits.
        hash ^= 0xFF
        hash &*= fnvPrime

        let heightBits = Double(contentHeight).bitPattern
        for shift in stride(from: 0, to: 64, by: 8) {
            let byte = UInt8((heightBits >> UInt64(shift)) & 0xFF)
            hash ^= UInt64(byte)
            hash &*= fnvPrime
        }

        return hash
    }

    private static func measureHeight(_ content: NSAttributedString) -> CGFloat {
        let tv = NSTextView()
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textStorage?.setAttributedString(content)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)

        let usedRect = tv.layoutManager!.usedRect(for: tv.textContainer!)
        return ceil(usedRect.height) + 4 // 2pt padding top + bottom
    }
}

// MARK: - TableScrollSizingCell

/// Minimal `NSTextAttachmentCell` that provides correct dimensions for layout.
///
/// This cell does not draw or embed views; the hosting `NSTextView`
/// manages scroll view embedding after layout completes.
private final class TableScrollSizingCell: NSTextAttachmentCell {
    // MARK: - Properties

    private let width: CGFloat
    private let height: CGFloat

    // MARK: - Init

    init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
        super.init(textCell: "")
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        width = 0
        height = 0
        super.init(coder: coder)
    }

    // MARK: - Cell Metrics

    override nonisolated func cellSize() -> NSSize {
        NSSize(width: width, height: height)
    }

    override nonisolated func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: 0)
    }

    // MARK: - Drawing (No-op)

    override func draw(withFrame _: NSRect, in _: NSView?) {
        // Intentionally empty — scroll view embedding handled by host NSTextView
    }

    override func draw(
        withFrame _: NSRect,
        in _: NSView?,
        characterIndex _: Int,
        layoutManager _: NSLayoutManager
    ) {
        // Intentionally empty — scroll view embedding handled by host NSTextView
    }
}

// MARK: - TableScrollContainer

/// Identifiable `NSScrollView` subclass for table attachment scroll views.
/// Used to distinguish table views from other subviews during cleanup.
final class TableScrollContainer: NSScrollView {}
