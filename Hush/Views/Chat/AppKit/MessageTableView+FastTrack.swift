import AppKit

@MainActor
extension MessageTableView {
    func updateStreamingCell(messageID: UUID, content: String) {
        guard let rowIndex = rows.firstIndex(where: { $0.message.id == messageID }) else { return }
        guard rowIndex >= 0, rowIndex < rows.count else { return }
        let existingRow = rows[rowIndex]
        guard existingRow.message.content != content else { return }

        let updatedMessage = ChatMessage(
            id: existingRow.message.id,
            role: existingRow.message.role,
            content: content,
            createdAt: existingRow.message.createdAt
        )
        rows[rowIndex] = RowModel(
            message: updatedMessage,
            isStreaming: existingRow.isStreaming,
            renderHint: existingRow.renderHint
        )

        guard tableView.numberOfColumns > 0 else { return }
        guard let cell = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? MessageTableCellView else {
            return
        }

        cell.updateStreamingText(content)
        let now = Date.now
        if now.timeIntervalSince(lastStreamingHeightMeasureAt) >= RenderConstants.streamingScrollCoalesceInterval {
            lastStreamingHeightMeasureAt = now

            let nextHeight = cell.bodyIntrinsicHeight
            if abs(nextHeight - lastStreamingHeight) > .ulpOfOne {
                requestRowHeightInvalidation(rowIndex: rowIndex)
                lastStreamingHeight = nextHeight
                #if DEBUG
                    heightInvalidationCountForTesting += 1
                #endif
            }
        }

        if !userHasScrolledUp {
            requestCoalescedScrollToBottom()
            #if DEBUG
                scrollToBottomCountForTesting += 1
            #endif
        }
    }

    func cancelVisibleRenderWorkForEviction() {
        guard tableView.numberOfColumns > 0 else { return }
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }

        for row in visible.location ..< (visible.location + visible.length) {
            guard row >= 0, row < tableView.numberOfRows else { continue }
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? MessageTableCellView else {
                continue
            }
            cell.cancelRenderWork()
        }
    }
}
