import Foundation

// MARK: - Chat Windowing Input

public struct ChatWindowingInput: Equatable, Sendable {
    public let messageCount: Int
    public let tailCount: Int
    public let bufferSize: Int
    public let anchorIndex: Int?
    public let previousAnchorIndex: Int?
    public let previousMessageCount: Int?
    public let previousWindowRange: Range<Int>?
    public let isPinned: Bool
    public let isStreaming: Bool

    public init(
        messageCount: Int,
        tailCount: Int,
        bufferSize: Int,
        anchorIndex: Int?,
        previousAnchorIndex: Int? = nil,
        previousMessageCount: Int? = nil,
        previousWindowRange: Range<Int>? = nil,
        isPinned: Bool,
        isStreaming: Bool
    ) {
        self.messageCount = messageCount
        self.tailCount = tailCount
        self.bufferSize = bufferSize
        self.anchorIndex = anchorIndex
        self.previousAnchorIndex = previousAnchorIndex
        self.previousMessageCount = previousMessageCount
        self.previousWindowRange = previousWindowRange
        self.isPinned = isPinned
        self.isStreaming = isStreaming
    }
}

// MARK: - Chat Windowing Output

public struct ChatWindowingOutput: Equatable, Sendable {
    public let windowRange: Range<Int>

    public init(windowRange: Range<Int>) {
        self.windowRange = windowRange
    }
}

// MARK: - Chat Windowing

public enum ChatWindowing {
    public static func computeWindow(_ input: ChatWindowingInput) -> ChatWindowingOutput {
        let normalizedMessageCount = max(0, input.messageCount)
        guard normalizedMessageCount > 0 else {
            return ChatWindowingOutput(windowRange: 0 ..< 0)
        }

        let normalizedTail = max(1, input.tailCount)
        let normalizedBuffer = max(0, input.bufferSize)
        let targetWindowSize = min(
            normalizedMessageCount,
            max(normalizedTail, normalizedTail + (normalizedBuffer * 2))
        )

        if normalizedMessageCount <= targetWindowSize {
            return ChatWindowingOutput(windowRange: 0 ..< normalizedMessageCount)
        }

        if input.isPinned {
            return ChatWindowingOutput(
                windowRange: trailingWindow(
                    messageCount: normalizedMessageCount,
                    windowSize: targetWindowSize
                )
            )
        }

        let normalizedAnchor = clampIndex(
            input.anchorIndex,
            messageCount: normalizedMessageCount,
            fallback: normalizedMessageCount - 1
        )

        var range = windowAroundAnchor(
            anchorIndex: normalizedAnchor,
            messageCount: normalizedMessageCount,
            windowSize: targetWindowSize,
            bufferSize: normalizedBuffer
        )

        if let previousRange = normalizedRange(input.previousWindowRange, messageCount: normalizedMessageCount) {
            let stabilizedPrevious = stabilizedPreviousRange(
                previousRange: previousRange,
                input: input,
                messageCount: normalizedMessageCount,
                windowSize: targetWindowSize
            )

            let lowerTrigger = stabilizedPrevious.lowerBound + normalizedBuffer
            let upperTrigger = stabilizedPrevious.upperBound - normalizedBuffer - 1
            if normalizedAnchor >= lowerTrigger, normalizedAnchor <= upperTrigger {
                range = stabilizedPrevious
            }
        }

        if input.isStreaming, range.upperBound < normalizedMessageCount {
            let shiftedLowerBound = range.lowerBound + (normalizedMessageCount - range.upperBound)
            let shiftedUpperBound = shiftedLowerBound + targetWindowSize
            range = normalizedRange(
                shiftedLowerBound ..< shiftedUpperBound,
                messageCount: normalizedMessageCount
            ) ?? trailingWindow(messageCount: normalizedMessageCount, windowSize: targetWindowSize)
        }

        return ChatWindowingOutput(windowRange: range)
    }

    // MARK: - Private

    private static func clampIndex(_ index: Int?, messageCount: Int, fallback: Int) -> Int {
        guard messageCount > 0 else { return 0 }
        guard let index else { return min(max(0, fallback), messageCount - 1) }
        return min(max(0, index), messageCount - 1)
    }

    private static func windowAroundAnchor(
        anchorIndex: Int,
        messageCount: Int,
        windowSize: Int,
        bufferSize: Int
    ) -> Range<Int> {
        let preferredLowerBound = anchorIndex - bufferSize
        let clampedLowerBound = min(max(0, preferredLowerBound), max(0, messageCount - windowSize))
        return clampedLowerBound ..< (clampedLowerBound + windowSize)
    }

    private static func trailingWindow(
        messageCount: Int,
        windowSize: Int
    ) -> Range<Int> {
        let lowerBound = max(0, messageCount - windowSize)
        return lowerBound ..< messageCount
    }

    private static func normalizedRange(
        _ range: Range<Int>?,
        messageCount: Int
    ) -> Range<Int>? {
        guard let range else { return nil }
        guard messageCount > 0 else { return 0 ..< 0 }

        let lowerBound = min(max(0, range.lowerBound), messageCount)
        let upperBound = min(max(lowerBound, range.upperBound), messageCount)
        guard upperBound > lowerBound else { return nil }
        return lowerBound ..< upperBound
    }

    private static func stabilizedPreviousRange(
        previousRange: Range<Int>,
        input: ChatWindowingInput,
        messageCount: Int,
        windowSize: Int
    ) -> Range<Int> {
        let likelyPrependedOlderMessages = {
            guard let previousMessageCount = input.previousMessageCount,
                  let previousAnchorIndex = input.previousAnchorIndex,
                  let currentAnchorIndex = input.anchorIndex
            else {
                return false
            }

            let countGrew = messageCount > previousMessageCount
            let anchorJumpedForward = currentAnchorIndex > previousAnchorIndex
            return countGrew && anchorJumpedForward
        }()

        guard likelyPrependedOlderMessages,
              let previousAnchorIndex = input.previousAnchorIndex,
              let currentAnchorIndex = input.anchorIndex
        else {
            return previousRange
        }

        let delta = currentAnchorIndex - previousAnchorIndex
        let shifted = (previousRange.lowerBound + delta) ..< (previousRange.upperBound + delta)
        return normalizedRange(shifted, messageCount: messageCount)
            ?? trailingWindow(messageCount: messageCount, windowSize: windowSize)
    }
}
