import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("Quick Bar transcript outer-edge symmetry helpers")
struct QuickBarTranscriptSymmetryTests {}

extension QuickBarTranscriptSymmetryTests {
    // MARK: - Smoke Test

    @Test("Smoke: assistant cell visibleTextFrame is obtainable at transcript readable width")
    func smokeAssistantCellVisibleTextFrameObtainable() {
        let runtime = makeRuntime()

        let cell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-smoke-assistant")
        )
        let hosted = hostCell(cell, width: transcriptReadableWidth)
        defer {
            hosted.window.contentView = nil
            hosted.window.orderOut(nil)
            withExtendedLifetime(hosted.window) {}
        }

        cell.configure(
            row: makeQBRow(content: "Hello, how can I help?", role: .assistant),
            runtime: runtime,
            availableWidth: hosted.container.bounds.width,
            container: nil
        )
        hosted.host.layoutSubtreeIfNeeded()

        let visibleFrame = cell.visibleTextFrameForTesting

        #expect(visibleFrame.width > 0, "visibleTextFrame should have positive width")
        #expect(visibleFrame.minX.isFinite, "visibleTextFrame.minX should be finite")
        #expect(visibleFrame.minX >= 0, "visibleTextFrame.minX should be non-negative")

        let assistantLeftGap = visibleFrame.minX
        #expect(assistantLeftGap >= 0, "assistant left gap should be non-negative")
    }

    // MARK: - Compact Plain-Text Outer-Edge Symmetry (RED until fix)

    @Test("Short text outer-edge gap symmetry should match between assistant and user (RED until fixed)")
    func compactShortTextOuterEdgeGapsAreSymmetric() {
        let runtime = makeRuntime()

        let assistantCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-short-assistant")
        )
        let userCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-short-user")
        )

        let hostedAssistant = hostCell(assistantCell, width: transcriptReadableWidth)
        defer {
            hostedAssistant.window.contentView = nil
            hostedAssistant.window.orderOut(nil)
            withExtendedLifetime(hostedAssistant.window) {}
        }
        let hostedUser = hostCell(userCell, width: transcriptReadableWidth)
        defer {
            hostedUser.window.contentView = nil
            hostedUser.window.orderOut(nil)
            withExtendedLifetime(hostedUser.window) {}
        }

        assistantCell.configure(
            row: makeQBRow(content: "Hello!", role: .assistant),
            runtime: runtime,
            availableWidth: hostedAssistant.container.bounds.width,
            container: nil
        )
        userCell.configure(
            row: makeQBRow(content: "你好世界!", role: .user),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )

        hostedAssistant.host.layoutSubtreeIfNeeded()
        hostedUser.host.layoutSubtreeIfNeeded()

        let assistantBodyLeftGap = assistantCell.bodyFrameForTesting.minX
        let userBodyRightGap = hostedUser.container.bounds.width - userCell.bodyFrameForTesting.maxX
        let assistantVisibleLeftGap = assistantCell.visibleTextFrameForTesting.minX
        let userVisibleRightGap = hostedUser.container.bounds.width - userCell.visibleTextFrameForTesting.maxX

        #expect(
            abs(userBodyRightGap - assistantBodyLeftGap) <= outerEdgeTolerance,
            """
            Body frame symmetry mismatch (short text):
            assistantBodyLeftGap=\(assistantBodyLeftGap), userBodyRightGap=\(userBodyRightGap),
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )
        #expect(
            abs(userVisibleRightGap - assistantVisibleLeftGap) <= outerEdgeTolerance,
            """
            Visible text symmetry mismatch (short text):
            assistantVisibleLeftGap=\(assistantVisibleLeftGap), userVisibleRightGap=\(userVisibleRightGap),
            delta=\(userVisibleRightGap - assistantVisibleLeftGap)
            """
        )
    }

    @Test("Long text outer-edge gap symmetry should match between assistant and user (RED until fixed)")
    func compactLongTextOuterEdgeGapsAreSymmetric() {
        let runtime = makeRuntime()

        let assistantCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-long-assistant")
        )
        let userCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-long-user")
        )

        let hostedAssistant = hostCell(assistantCell, width: transcriptReadableWidth)
        defer {
            hostedAssistant.window.contentView = nil
            hostedAssistant.window.orderOut(nil)
            withExtendedLifetime(hostedAssistant.window) {}
        }
        let hostedUser = hostCell(userCell, width: transcriptReadableWidth)
        defer {
            hostedUser.window.contentView = nil
            hostedUser.window.orderOut(nil)
            withExtendedLifetime(hostedUser.window) {}
        }

        assistantCell.configure(
            row: makeQBRow(content: "The quick brown fox jumps over!", role: .assistant),
            runtime: runtime,
            availableWidth: hostedAssistant.container.bounds.width,
            container: nil
        )
        userCell.configure(
            row: makeQBRow(content: "敏捷的棕色狐狸跳过了懒狗旁边的围栏!", role: .user),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )

        hostedAssistant.host.layoutSubtreeIfNeeded()
        hostedUser.host.layoutSubtreeIfNeeded()

        let assistantBodyLeftGap = assistantCell.bodyFrameForTesting.minX
        let userBodyRightGap = hostedUser.container.bounds.width - userCell.bodyFrameForTesting.maxX
        let assistantVisibleLeftGap = assistantCell.visibleTextFrameForTesting.minX
        let userVisibleRightGap = hostedUser.container.bounds.width - userCell.visibleTextFrameForTesting.maxX

        #expect(
            abs(userBodyRightGap - assistantBodyLeftGap) <= outerEdgeTolerance,
            """
            Body frame symmetry mismatch (long text):
            assistantBodyLeftGap=\(assistantBodyLeftGap), userBodyRightGap=\(userBodyRightGap),
            delta=\(userBodyRightGap - assistantBodyLeftGap)
            """
        )
        #expect(
            abs(userVisibleRightGap - assistantVisibleLeftGap) <= outerEdgeTolerance,
            """
            Visible text symmetry mismatch (long text):
            assistantVisibleLeftGap=\(assistantVisibleLeftGap), userVisibleRightGap=\(userVisibleRightGap),
            delta=\(userVisibleRightGap - assistantVisibleLeftGap)
            """
        )
    }

    // MARK: - Waiting-State Symmetry

    @Test("Waiting-state assistant body gap should match user trailing gap (may be RED)")
    func waitingStateAssistantAndUserOuterEdgeGapsAreSymmetric() {
        let runtime = makeRuntime()

        let assistantCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-waiting-assistant")
        )
        let hostedAssistant = hostCell(assistantCell, width: transcriptReadableWidth)
        defer {
            hostedAssistant.window.contentView = nil
            hostedAssistant.window.orderOut(nil)
            withExtendedLifetime(hostedAssistant.window) {}
        }

        assistantCell.configure(
            row: makeQBRow(content: "", role: .assistant, isStreaming: true),
            runtime: runtime,
            availableWidth: hostedAssistant.container.bounds.width,
            container: nil
        )
        hostedAssistant.host.layoutSubtreeIfNeeded()

        let userCell = QuickBarMessageCellView(
            identifier: NSUserInterfaceItemIdentifier("symmetry-waiting-user")
        )
        let hostedUser = hostCell(userCell, width: transcriptReadableWidth)
        defer {
            hostedUser.window.contentView = nil
            hostedUser.window.orderOut(nil)
            withExtendedLifetime(hostedUser.window) {}
        }

        userCell.configure(
            row: makeQBRow(content: "好的", role: .user),
            runtime: runtime,
            availableWidth: hostedUser.container.bounds.width,
            container: nil
        )
        hostedUser.host.layoutSubtreeIfNeeded()

        let assistantBodyLeftGap = assistantCell.bodyFrameForTesting.minX
        let userBodyRightGap = hostedUser.container.bounds.width - userCell.bodyFrameForTesting.maxX
        let assistantVisibleFrame = assistantCell.visibleTextFrameForTesting
        let userVisibleFrame = userCell.visibleTextFrameForTesting

        assertOuterEdgeSymmetry(
            context: "Waiting-state",
            measurement: OuterEdgeSymmetryMeasurement(
                assistantBodyLeftGap: assistantBodyLeftGap,
                userBodyRightGap: userBodyRightGap,
                assistantVisibleFrame: assistantVisibleFrame,
                userVisibleFrame: userVisibleFrame,
                containerWidth: hostedUser.container.bounds.width
            ),
            requireVisibleSymmetry: assistantVisibleFrame.width > 0 && userVisibleFrame.width > 0
        )
    }
}
