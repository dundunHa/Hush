// QuickBarTranscriptSymmetrySupport.swift
//
// Outer-edge symmetry measurement infrastructure for Quick Bar transcript.
//
// Why outer-edge instead of cell-internal?
// Cell-internal comparisons (e.g. bodyFrame vs contentContainer) only capture
// the padding within a single cell. They miss transcript-level padding and the
// readable-area centering logic used by the Quick Bar transcript.

import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
extension QuickBarTranscriptSymmetryTests {
    struct HostedQuickBarCell {
        let cell: QuickBarMessageCellView
        let hosted: (window: NSWindow, host: NSView, container: NSView)
    }

    struct OuterEdgeSymmetryMeasurement {
        let assistantBodyLeftGap: CGFloat
        let userBodyRightGap: CGFloat
        let assistantVisibleFrame: CGRect
        let userVisibleFrame: CGRect
        let containerWidth: CGFloat
    }

    var outerEdgeTolerance: CGFloat {
        1.0
    }

    var transcriptReadableWidth: CGFloat {
        QuickBarPanelReleaseMetrics.width
            - (HushSpacing.sm + 2) * 2
            - HushSpacing.xs * 2
    }

    func makeRuntime() -> MessageRenderRuntime {
        MessageRenderRuntime(
            renderer: MessageContentRenderer(
                renderCache: RenderCache(capacity: 10),
                mathCache: MathRenderCache(capacity: 10)
            ),
            scheduler: ConversationRenderScheduler()
        )
    }

    func hostCell(
        _ cell: NSView,
        width: CGFloat = 680,
        height: CGFloat = 320
    ) -> (window: NSWindow, host: NSView, container: NSView) {
        let host = NSView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.display()

        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(containerView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: host.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        containerView.addSubview(cell)
        cell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cell.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            cell.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            cell.topAnchor.constraint(equalTo: containerView.topAnchor),
            cell.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        host.layoutSubtreeIfNeeded()

        return (window, host, containerView)
    }

    func makeContainer() -> AppContainer {
        AppContainer.forTesting(
            messageRenderRuntime: MessageRenderRuntime(),
            enableStartupPrewarm: false
        )
    }

    func makeTable(width: CGFloat, height: CGFloat = 420) -> MessageTableView {
        let table = MessageTableView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        table.layoutSubtreeIfNeeded()
        return table
    }

    func makeQBRow(
        content: String,
        role: ChatRole = .assistant,
        isStreaming: Bool = false
    ) -> MessageTableView.RowModel {
        let message = ChatMessage(
            id: UUID(),
            role: role,
            content: content
        )
        return MessageTableView.RowModel(
            message: message,
            isStreaming: isStreaming,
            renderHint: MessageRenderHint(
                conversationID: "conv-symmetry",
                messageID: message.id,
                rankFromLatest: 0,
                isVisible: true,
                switchGeneration: 1
            )
        )
    }

    func makeConfiguredQuickBarCell(
        identifier: String,
        content: String,
        role: ChatRole,
        runtime: MessageRenderRuntime,
        isStreaming: Bool = false
    ) -> HostedQuickBarCell {
        let cell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier(identifier)
        )
        let hosted = hostCell(cell, width: transcriptReadableWidth)
        cell.configure(
            row: makeQBRow(content: content, role: role, isStreaming: isStreaming),
            runtime: runtime,
            availableWidth: hosted.container.bounds.width,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()
        return HostedQuickBarCell(cell: cell, hosted: hosted)
    }

    func assertOuterEdgeSymmetry(
        context: String,
        measurement: OuterEdgeSymmetryMeasurement,
        requireVisibleSymmetry: Bool
    ) {
        let assistantVisibleLeftGap = measurement.assistantVisibleFrame.minX
        let userVisibleRightGap = measurement.containerWidth - measurement.userVisibleFrame.maxX

        #expect(
            abs(measurement.userBodyRightGap - measurement.assistantBodyLeftGap) <= outerEdgeTolerance,
            """
            \(context) body symmetry mismatch:
            assistantBodyLeftGap=\(measurement.assistantBodyLeftGap), userBodyRightGap=\(measurement.userBodyRightGap),
            delta=\(measurement.userBodyRightGap - measurement.assistantBodyLeftGap)
            """
        )

        guard requireVisibleSymmetry else { return }

        #expect(
            abs(userVisibleRightGap - assistantVisibleLeftGap) <= outerEdgeTolerance,
            """
            \(context) visible-text symmetry mismatch:
            assistantVisibleLeftGap=\(assistantVisibleLeftGap), userVisibleRightGap=\(userVisibleRightGap),
            delta=\(userVisibleRightGap - assistantVisibleLeftGap)
            """
        )
    }
}
