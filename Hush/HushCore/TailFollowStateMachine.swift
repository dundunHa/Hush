import Foundation

// MARK: - Input

public struct TailFollowInput: Equatable, Sendable {
    public let distanceFromBottom: CGFloat
    public let isStreaming: Bool
    public let timeSinceStreamingCompleted: TimeInterval
    public let messageRole: ChatRole?
    public let didPrependOlderMessages: Bool
    public let pendingSwitchScroll: Bool
    public let isProgrammaticScroll: Bool

    public init(
        distanceFromBottom: CGFloat,
        isStreaming: Bool,
        timeSinceStreamingCompleted: TimeInterval,
        messageRole: ChatRole?,
        didPrependOlderMessages: Bool,
        pendingSwitchScroll: Bool,
        isProgrammaticScroll: Bool
    ) {
        self.distanceFromBottom = distanceFromBottom
        self.isStreaming = isStreaming
        self.timeSinceStreamingCompleted = timeSinceStreamingCompleted
        self.messageRole = messageRole
        self.didPrependOlderMessages = didPrependOlderMessages
        self.pendingSwitchScroll = pendingSwitchScroll
        self.isProgrammaticScroll = isProgrammaticScroll
    }
}

// MARK: - State

public struct TailFollowState: Equatable, Sendable {
    public var isFollowingTail: Bool
    public var pendingSwitchScroll: Bool
    public var lastStreamingCompletedAt: Date?
    public var lastProgrammaticScrollAt: Date?

    public init(
        isFollowingTail: Bool = true,
        pendingSwitchScroll: Bool = false,
        lastStreamingCompletedAt: Date? = nil,
        lastProgrammaticScrollAt: Date? = nil
    ) {
        self.isFollowingTail = isFollowingTail
        self.pendingSwitchScroll = pendingSwitchScroll
        self.lastStreamingCompletedAt = lastStreamingCompletedAt
        self.lastProgrammaticScrollAt = lastProgrammaticScrollAt
    }
}

// MARK: - Config

public struct TailFollowConfig: Equatable, Sendable {
    public let pinnedDistanceThreshold: CGFloat
    public let streamingBreakawayThreshold: CGFloat
    public let postStreamingGraceInterval: TimeInterval
    public let programmaticScrollGrace: TimeInterval

    public init(
        pinnedDistanceThreshold: CGFloat = 80,
        streamingBreakawayThreshold: CGFloat = 260,
        postStreamingGraceInterval: TimeInterval = 0.6,
        programmaticScrollGrace: TimeInterval = 0.1
    ) {
        self.pinnedDistanceThreshold = pinnedDistanceThreshold
        self.streamingBreakawayThreshold = streamingBreakawayThreshold
        self.postStreamingGraceInterval = postStreamingGraceInterval
        self.programmaticScrollGrace = programmaticScrollGrace
    }
}

// MARK: - Events

public enum TailFollowEvent: Equatable, Sendable {
    case distanceChanged(CGFloat)
    case messageAdded(role: ChatRole, didPrependOlder: Bool)
    case streamingStarted
    case streamingCompleted
    case conversationSwitched
    case programmaticScrollInitiated
}

// MARK: - Actions

public enum TailFollowAction: Equatable, Sendable {
    case scrollToBottom(animated: Bool, reason: ScrollReason)
    case none
}

public enum ScrollReason: String, Equatable, Sendable {
    case switchLoad
    case newUser
    case newAssistant
    case streamingContent
    case streamingFinished
    case resizeShrink
}

// MARK: - Tail Follow

public enum TailFollow {
    public static func reduce(
        state: inout TailFollowState,
        event: TailFollowEvent,
        config: TailFollowConfig,
        now: Date
    ) -> TailFollowAction {
        switch event {
        case let .distanceChanged(distanceFromBottom):
            return handleDistanceChanged(distanceFromBottom, state: &state, config: config, now: now)
        case let .messageAdded(role, didPrependOlder):
            return handleMessageAdded(role: role, didPrependOlder: didPrependOlder, state: &state, now: now)
        case .streamingStarted:
            state.lastStreamingCompletedAt = .distantFuture
            return .none
        case .streamingCompleted:
            state.lastStreamingCompletedAt = now
            return .none
        case .conversationSwitched:
            state.isFollowingTail = true
            state.pendingSwitchScroll = true
            state.lastStreamingCompletedAt = nil
            state.lastProgrammaticScrollAt = nil
            return .none
        case .programmaticScrollInitiated:
            state.lastProgrammaticScrollAt = now
            return .none
        }
    }

    private static func handleDistanceChanged(
        _ distanceFromBottom: CGFloat,
        state: inout TailFollowState,
        config: TailFollowConfig,
        now: Date
    ) -> TailFollowAction {
        if distanceFromBottom <= config.pinnedDistanceThreshold {
            state.isFollowingTail = true
            return .none
        }

        if let lastProgrammaticScrollAt = state.lastProgrammaticScrollAt,
           now.timeIntervalSince(lastProgrammaticScrollAt) <= config.programmaticScrollGrace
        {
            return .none
        }

        let isStreaming = state.lastStreamingCompletedAt == .distantFuture
        let timeSinceCompleted = state.lastStreamingCompletedAt.map { now.timeIntervalSince($0) } ?? .infinity
        let inProtectionWindow = isStreaming || timeSinceCompleted <= config.postStreamingGraceInterval

        if !inProtectionWindow || distanceFromBottom > config.streamingBreakawayThreshold {
            state.isFollowingTail = false
        }
        return .none
    }

    private static func handleMessageAdded(
        role: ChatRole,
        didPrependOlder: Bool,
        state: inout TailFollowState,
        now: Date
    ) -> TailFollowAction {
        guard !didPrependOlder else { return .none }

        if state.pendingSwitchScroll {
            state.pendingSwitchScroll = false
            state.lastProgrammaticScrollAt = now
            return .scrollToBottom(animated: false, reason: .switchLoad)
        }

        if role == .user {
            state.isFollowingTail = true
            state.lastProgrammaticScrollAt = now
            return .scrollToBottom(animated: true, reason: .newUser)
        }

        if role == .assistant, state.isFollowingTail {
            state.lastProgrammaticScrollAt = now
            return .scrollToBottom(animated: true, reason: .newAssistant)
        }

        return .none
    }
}
