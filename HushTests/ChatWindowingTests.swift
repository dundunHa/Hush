@testable import Hush
import Testing

struct ChatWindowingTests {
    @Test("messages < windowSize 时返回全量范围")
    func renderAllWhenMessagesBelowWindowSize() {
        let input = ChatWindowingInput(
            messageCount: 5,
            tailCount: RuntimeConstants.conversationMessagePageSize,
            bufferSize: 2,
            anchorIndex: 2,
            isPinned: false,
            isStreaming: false
        )

        let output = ChatWindowing.computeWindow(input)
        #expect(output.windowRange == 0 ..< 5)
    }

    @Test("pinned=true 时窗口稳定跟随尾部并包含 tail N")
    func pinnedWindowContainsTail() {
        let input = ChatWindowingInput(
            messageCount: 20,
            tailCount: RuntimeConstants.conversationMessagePageSize,
            bufferSize: 2,
            anchorIndex: 6,
            isPinned: true,
            isStreaming: false
        )

        let output = ChatWindowing.computeWindow(input)
        let tailStart = 20 - RuntimeConstants.conversationMessagePageSize
        #expect(output.windowRange.lowerBound <= tailStart)
        #expect(output.windowRange.upperBound == 20)
        #expect(output.windowRange.contains(19))
    }

    @Test("pinned=false 时 anchor 在缓冲区内移动不触发窗口抖动")
    func unpinnedAnchorMovementWithinBufferKeepsWindowStable() {
        let first = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 40,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: 10,
                isPinned: false,
                isStreaming: false
            )
        )

        let second = ChatWindowing.computeWindow(
            ChatWindowingInput(
                messageCount: 40,
                tailCount: RuntimeConstants.conversationMessagePageSize,
                bufferSize: 2,
                anchorIndex: 11,
                previousAnchorIndex: 10,
                previousMessageCount: 40,
                previousWindowRange: first.windowRange,
                isPinned: false,
                isStreaming: false
            )
        )

        #expect(first.windowRange == 8 ..< 21)
        #expect(second.windowRange == first.windowRange)
    }

    @Test("streaming=true 时末尾消息总在窗口内")
    func streamingAlwaysIncludesLastMessage() {
        let input = ChatWindowingInput(
            messageCount: 30,
            tailCount: RuntimeConstants.conversationMessagePageSize,
            bufferSize: 2,
            anchorIndex: 1,
            previousAnchorIndex: 1,
            previousMessageCount: 30,
            previousWindowRange: 0 ..< 13,
            isPinned: false,
            isStreaming: true
        )

        let output = ChatWindowing.computeWindow(input)
        #expect(output.windowRange.upperBound == 30)
        #expect(output.windowRange.contains(29))
    }

    @Test("prepend older messages 时窗口按 anchor 偏移保持稳定")
    func prependOlderMessagesKeepsWindowStableByAnchorDelta() {
        let input = ChatWindowingInput(
            messageCount: 59,
            tailCount: RuntimeConstants.conversationMessagePageSize,
            bufferSize: 2,
            anchorIndex: 33,
            previousAnchorIndex: 24,
            previousMessageCount: 50,
            previousWindowRange: 20 ..< 33,
            isPinned: false,
            isStreaming: false
        )

        let output = ChatWindowing.computeWindow(input)
        #expect(output.windowRange == 29 ..< 42)
    }
}
