@testable import Hush
import Testing

struct ConversationWindowingTests {
    // MARK: - Streaming Auto-Scroll With Windowing

    @Test("Streaming always includes last message regardless of anchor position")
    func streamingAlwaysIncludesLastMessage() {
        let input = ChatWindowingInput(
            messageCount: 60,
            tailCount: RuntimeConstants.conversationMessagePageSize,
            bufferSize: 2,
            anchorIndex: 5,
            isPinned: false,
            isStreaming: true
        )

        let output = ChatWindowing.computeWindow(input)
        #expect(output.windowRange.upperBound == 60)
        #expect(output.windowRange.contains(59))
    }

    @Test("Streaming shifts window to tail even with stable previous window at top")
    func streamingShiftsWindowToTail() {
        let input = ChatWindowingInput(
            messageCount: 50,
            tailCount: RuntimeConstants.conversationMessagePageSize,
            bufferSize: 2,
            anchorIndex: 3,
            previousAnchorIndex: 3,
            previousMessageCount: 50,
            previousWindowRange: 0 ..< 13,
            isPinned: false,
            isStreaming: true
        )

        let output = ChatWindowing.computeWindow(input)
        #expect(output.windowRange.upperBound == 50)
        #expect(output.windowRange.contains(49), "Last message must be in window during streaming")
    }

    @Test("Streaming with pinned=true includes tail")
    func streamingPinnedIncludesTail() {
        let input = ChatWindowingInput(
            messageCount: 100,
            tailCount: RuntimeConstants.conversationMessagePageSize,
            bufferSize: 2,
            anchorIndex: 95,
            isPinned: true,
            isStreaming: true
        )

        let output = ChatWindowing.computeWindow(input)
        #expect(output.windowRange.upperBound == 100)
        #expect(output.windowRange.contains(99))
    }

    @Test("Streaming with growing message count keeps last message visible")
    func streamingGrowingCountKeepsLastVisible() {
        var lastOutput: ChatWindowingOutput?
        for count in 30 ... 35 {
            let input = ChatWindowingInput(
                messageCount: count,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: count - 1,
                previousAnchorIndex: lastOutput.map { _ in count - 2 },
                previousMessageCount: lastOutput.map { _ in count - 1 },
                previousWindowRange: lastOutput?.windowRange,
                isPinned: false,
                isStreaming: true
            )

            let output = ChatWindowing.computeWindow(input)
            #expect(output.windowRange.contains(count - 1), "Message \(count - 1) must be visible during streaming")
            #expect(output.windowRange.upperBound == count)
            lastOutput = output
        }
    }

    // MARK: - Rapid Consecutive Switch (A→B→C)

    @Test("Consecutive switches produce independent windows without stale range bleed")
    func consecutiveSwitchesProduceIndependentWindows() {
        let convAWindow = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 40,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: nil,
                isPinned: true,
                isStreaming: false
            )
        )

        let convBWindow = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 20,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: nil,
                isPinned: true,
                isStreaming: false
            )
        )

        let convCWindow = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 10,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: nil,
                isPinned: true,
                isStreaming: false
            )
        )

        #expect(convAWindow.windowRange.upperBound == 40)
        #expect(convBWindow.windowRange.upperBound == 20)
        #expect(convCWindow.windowRange.upperBound == 10)

        #expect(convCWindow.windowRange != convAWindow.windowRange)
        #expect(convCWindow.windowRange != convBWindow.windowRange)
    }

    @Test("Switch from large to small conversation resets window correctly")
    func switchLargeToSmallResetsWindow() {
        let largeOutput = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 200,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: 190,
                isPinned: true,
                isStreaming: false
            )
        )

        #expect(largeOutput.windowRange.upperBound == 200)

        let smallOutput = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 5,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: nil,
                previousAnchorIndex: nil,
                previousMessageCount: nil,
                previousWindowRange: nil,
                isPinned: true,
                isStreaming: false
            )
        )

        #expect(smallOutput.windowRange == 0 ..< 5)
    }

    @Test("Switch resets: no previousWindowRange means fresh computation")
    func switchResetsFreshComputation() {
        let output = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 50,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: nil,
                previousAnchorIndex: nil,
                previousMessageCount: nil,
                previousWindowRange: nil,
                isPinned: true,
                isStreaming: false
            )
        )

        #expect(output.windowRange.upperBound == 50)
        #expect(output.windowRange.contains(49))
    }

    // MARK: - Windowing Stability Under Scroll

    @Test("Anchor at buffer boundary triggers window shift")
    func anchorAtBufferBoundaryTriggersShift() {
        let firstWindow = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 60,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: 25,
                isPinned: false,
                isStreaming: false
            )
        )

        let anchorOutsideBuffer = firstWindow.windowRange.lowerBound + 1
        let shiftedWindow = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 60,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: anchorOutsideBuffer,
                previousAnchorIndex: 25,
                previousMessageCount: 60,
                previousWindowRange: firstWindow.windowRange,
                isPinned: false,
                isStreaming: false
            )
        )

        #expect(shiftedWindow.windowRange.contains(anchorOutsideBuffer))
    }

    @Test("Empty conversation produces empty window range")
    func emptyConversationEmptyWindow() {
        let output = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 0,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: nil,
                isPinned: true,
                isStreaming: false
            )
        )

        #expect(output.windowRange == 0 ..< 0)
    }

    // MARK: - Older-Load Window Stability

    @Test("Older-load prepend shifts window by delta to maintain anchor position")
    func olderLoadPrependShiftsWindowByDelta() {
        let beforeLoad = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 30,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: 15,
                isPinned: false,
                isStreaming: false
            )
        )

        let prependCount = 9
        let afterLoad = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 30 + prependCount,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: 15 + prependCount,
                previousAnchorIndex: 15,
                previousMessageCount: 30,
                previousWindowRange: beforeLoad.windowRange,
                isPinned: false,
                isStreaming: false
            )
        )

        let expectedShiftedLower = beforeLoad.windowRange.lowerBound + prependCount
        let expectedShiftedUpper = beforeLoad.windowRange.upperBound + prependCount
        #expect(afterLoad.windowRange == expectedShiftedLower ..< expectedShiftedUpper)
    }

    @Test("Multiple older-load cycles maintain window consistency")
    func multipleOlderLoadCyclesMaintainConsistency() {
        var messageCount = 20
        var anchorIndex = 10
        var previousOutput: ChatWindowingOutput?
        var previousAnchor: Int?
        var previousCount: Int?

        for _ in 0 ..< 3 {
            let input = ChatWindowingInput(
                messageCount: messageCount,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: anchorIndex,
                previousAnchorIndex: previousAnchor,
                previousMessageCount: previousCount,
                previousWindowRange: previousOutput?.windowRange,
                isPinned: false,
                isStreaming: false
            )

            let output = ChatWindowing.computeWindow(input)
            #expect(output.windowRange.contains(anchorIndex), "Anchor must remain visible after older-load")
            #expect(!output.windowRange.isEmpty)

            previousAnchor = anchorIndex
            previousCount = messageCount
            previousOutput = output

            let prepended = 9
            messageCount += prepended
            anchorIndex += prepended
        }
    }
}
