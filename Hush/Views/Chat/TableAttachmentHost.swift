import AppKit

struct TableAttachmentReuseKey: Hashable {
    /// Ordinal keeps duplicated tables distinct within the same message.
    /// Width is intentionally excluded so resize-driven redraws can still reuse
    /// the same subview instance and preserve horizontal scroll state.
    let ordinal: Int
    let signature: UInt64
}

struct TableAttachmentDescriptor {
    let key: TableAttachmentReuseKey
    let frame: NSRect
    let attachment: TableScrollAttachment
}

// MARK: - DescriptorFingerprint

private struct DescriptorFingerprint: Equatable {
    let keys: [TableAttachmentReuseKey]
    let frameHashes: [Int]

    init(_ descriptors: [TableAttachmentDescriptor]) {
        keys = descriptors.map(\.key)
        frameHashes = descriptors.map { desc in
            var hasher = Hasher()
            hasher.combine(Int(desc.frame.origin.x * 10))
            hasher.combine(Int(desc.frame.origin.y * 10))
            hasher.combine(Int(desc.frame.width * 10))
            hasher.combine(Int(desc.frame.height * 10))
            return hasher.finalize()
        }
    }
}

final class TableAttachmentHost {
    private(set) var managedViewsByKey: [TableAttachmentReuseKey: TableScrollContainer] = [:]

    /// Cached descriptor fingerprint to skip reconcile when attachment set is unchanged.
    private var lastDescriptorFingerprint: DescriptorFingerprint?

    var isEmpty: Bool {
        managedViewsByKey.isEmpty
    }

    func reconcile(in textView: NSTextView) {
        PerfTrace.measure(PerfTrace.Event.attachmentsReconcile) {
            reconcileImpl(in: textView)
        }
    }

    private func reconcileImpl(in textView: NSTextView) {
        let descriptors = scanDescriptors(in: textView)
        let currentFingerprint = DescriptorFingerprint(descriptors)

        if let last = lastDescriptorFingerprint, last == currentFingerprint {
            PerfTrace.count(PerfTrace.Event.attachmentsReconcile, fields: ["skipped": "true"])
            return
        }
        lastDescriptorFingerprint = currentFingerprint

        let nextKeys = Set(descriptors.map(\.key))

        let staleKeys = managedViewsByKey.keys.filter { !nextKeys.contains($0) }
        for key in staleKeys {
            managedViewsByKey[key]?.removeFromSuperview()
            managedViewsByKey.removeValue(forKey: key)
        }

        for descriptor in descriptors {
            let scrollView: TableScrollContainer
            if let existing = managedViewsByKey[descriptor.key] {
                scrollView = existing
            } else {
                scrollView = descriptor.attachment.makeScrollView()
                managedViewsByKey[descriptor.key] = scrollView
                textView.addSubview(scrollView)
            }

            if scrollView.superview !== textView {
                scrollView.removeFromSuperview()
                textView.addSubview(scrollView)
            }

            let preservedX = scrollView.contentView.bounds.origin.x
            scrollView.frame = descriptor.frame
            restoreHorizontalOffset(preservedX, in: scrollView)
        }
    }

    private func scanDescriptors(in textView: NSTextView) -> [TableAttachmentDescriptor] {
        guard let textStorage = textView.textStorage,
              let layoutManager = textView.layoutManager
        else { return [] }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        guard fullRange.length > 0 else { return [] }

        let containerOrigin = textView.textContainerOrigin
        var descriptors: [TableAttachmentDescriptor] = []
        var ordinal = 0

        textStorage.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            guard let tableAttachment = value as? TableScrollAttachment else { return }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            guard glyphRange.location != NSNotFound else { return }

            let lineFragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphRange.location,
                effectiveRange: nil
            )

            let frame = NSRect(
                x: lineFragmentRect.origin.x + containerOrigin.x,
                y: lineFragmentRect.origin.y + containerOrigin.y,
                width: max(1, lineFragmentRect.width),
                height: tableAttachment.contentHeight
            )

            let key = TableAttachmentReuseKey(
                ordinal: ordinal,
                signature: tableAttachment.reuseSignature
            )
            descriptors.append(
                TableAttachmentDescriptor(
                    key: key,
                    frame: frame,
                    attachment: tableAttachment
                )
            )
            ordinal += 1
        }

        return descriptors
    }

    private func restoreHorizontalOffset(_ previousX: CGFloat, in scrollView: TableScrollContainer) {
        guard let documentView = scrollView.documentView else { return }

        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()

        let maxOffset = max(0, documentView.frame.width - scrollView.contentSize.width)
        let clampedX = min(max(0, previousX), maxOffset)

        if abs(scrollView.contentView.bounds.origin.x - clampedX) > 0.5 {
            scrollView.contentView.scroll(to: NSPoint(x: clampedX, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
