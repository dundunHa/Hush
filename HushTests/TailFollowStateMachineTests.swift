import Foundation
@testable import Hush
import Testing

struct TailFollowStateMachineTests {
    let config = TailFollowConfig(
        pinnedDistanceThreshold: 80,
        streamingBreakawayThreshold: 260,
        postStreamingGraceInterval: 0.6,
        programmaticScrollGrace: 0.1
    )

    private let baseNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func reduce(
        _ state: inout TailFollowState,
        _ event: TailFollowEvent,
        secondsFromBase: TimeInterval = 0
    ) -> TailFollowAction {
        TailFollow.reduce(
            state: &state,
            event: event,
            config: config,
            now: baseNow.addingTimeInterval(secondsFromBase)
        )
    }

    @Test("Distance < 80pt sets following tail (79)")
    func distanceBelowThresholdSetsFollowing() {
        var state = TailFollowState(isFollowingTail: false)
        let action = reduce(&state, .distanceChanged(79))

        #expect(action == .none)
        #expect(state.isFollowingTail)
    }

    @Test("Distance == 80pt sets following tail")
    func distanceEqualThresholdSetsFollowing() {
        var state = TailFollowState(isFollowingTail: false)
        let action = reduce(&state, .distanceChanged(80))

        #expect(action == .none)
        #expect(state.isFollowingTail)
    }

    @Test("Distance > 80pt without streaming protection sets not following")
    func distanceOverThresholdSetsNotFollowing() {
        var state = TailFollowState(isFollowingTail: true)
        let action = reduce(&state, .distanceChanged(81))

        #expect(action == .none)
        #expect(!state.isFollowingTail)
    }

    @Test("Distance <= 260pt during streaming stays following")
    func streamingProtectionWithinBreakaway() {
        var state = TailFollowState(isFollowingTail: true, lastStreamingCompletedAt: .distantFuture)
        let action = reduce(&state, .distanceChanged(260))

        #expect(action == .none)
        #expect(state.isFollowingTail)
    }

    @Test("Distance > 260pt during streaming breaks away")
    func streamingBreakawayBeyondThreshold() {
        var state = TailFollowState(isFollowingTail: true, lastStreamingCompletedAt: .distantFuture)
        let action = reduce(&state, .distanceChanged(261))

        #expect(action == .none)
        #expect(!state.isFollowingTail)
    }

    @Test("Post-streaming grace period protects within 0.599s")
    func postStreamingGracePeriodWithin599ms() {
        var state = TailFollowState(
            isFollowingTail: true,
            lastStreamingCompletedAt: baseNow.addingTimeInterval(-0.599)
        )
        let action = reduce(&state, .distanceChanged(81))

        #expect(action == .none)
        #expect(state.isFollowingTail)
    }

    @Test("Post-streaming boundary at 0.6s")
    func postStreamingGracePeriodAt600ms() {
        var state = TailFollowState(
            isFollowingTail: true,
            lastStreamingCompletedAt: baseNow.addingTimeInterval(-0.6)
        )
        let action = reduce(&state, .distanceChanged(81))

        #expect(action == .none)
        #expect(!state.isFollowingTail)
    }

    @Test("Post-streaming grace expires after 0.601s")
    func postStreamingGraceExpires() {
        var state = TailFollowState(
            isFollowingTail: true,
            lastStreamingCompletedAt: baseNow.addingTimeInterval(-0.601)
        )
        let action = reduce(&state, .distanceChanged(81))

        #expect(action == .none)
        #expect(!state.isFollowingTail)
    }

    @Test("Programmatic scroll boundary at 0.1s")
    func programmaticScrollGraceWindow() {
        var state = TailFollowState(
            isFollowingTail: true,
            lastProgrammaticScrollAt: baseNow
        )
        let action = reduce(&state, .distanceChanged(500), secondsFromBase: 0.1)

        #expect(action == .none)
        #expect(!state.isFollowingTail)
    }

    @Test("Programmatic scroll grace no longer applies after 0.101s")
    func programmaticScrollGraceExpiresAfterBoundary() {
        var state = TailFollowState(
            isFollowingTail: true,
            lastProgrammaticScrollAt: baseNow
        )
        let action = reduce(&state, .distanceChanged(500), secondsFromBase: 0.101)

        #expect(action == .none)
        #expect(!state.isFollowingTail)
    }

    @Test("Prepend older messages - no scroll")
    func prependOlderNoScroll() {
        var state = TailFollowState(isFollowingTail: false)
        let action = reduce(&state, .messageAdded(role: .assistant, didPrependOlder: true))

        #expect(action == .none)
        #expect(!state.isFollowingTail)
    }

    @Test("Pending switch scroll triggers switchLoad")
    func pendingSwitchScroll() {
        var state = TailFollowState(isFollowingTail: false, pendingSwitchScroll: true)
        let action = reduce(&state, .messageAdded(role: .assistant, didPrependOlder: false))

        #expect(action == .scrollToBottom(animated: false, reason: .switchLoad))
        #expect(!state.pendingSwitchScroll)
        #expect(state.lastProgrammaticScrollAt == baseNow)
    }

    @Test("User message always scrolls and resumes tail-follow")
    func userMessageAlwaysScrolls() {
        var state = TailFollowState(isFollowingTail: false)
        let action = reduce(&state, .messageAdded(role: .user, didPrependOlder: false))

        #expect(action == .scrollToBottom(animated: true, reason: .newUser))
        #expect(state.isFollowingTail)
        #expect(state.lastProgrammaticScrollAt == baseNow)
    }

    @Test("User message overrides scrolled up state")
    func userMessageOverridesScrolledUp() {
        var state = TailFollowState(isFollowingTail: false, pendingSwitchScroll: false)
        let action = reduce(&state, .messageAdded(role: .user, didPrependOlder: false), secondsFromBase: 12)

        #expect(action == .scrollToBottom(animated: true, reason: .newUser))
        #expect(state.isFollowingTail)
        #expect(state.lastProgrammaticScrollAt == baseNow.addingTimeInterval(12))
    }

    @Test("Assistant message scrolls when following tail")
    func assistantMessageWhenFollowing() {
        var state = TailFollowState(isFollowingTail: true)
        let action = reduce(&state, .messageAdded(role: .assistant, didPrependOlder: false))

        #expect(action == .scrollToBottom(animated: true, reason: .newAssistant))
        #expect(state.lastProgrammaticScrollAt == baseNow)
    }

    @Test("Assistant message suppressed when scrolled up")
    func assistantMessageSuppressedWhenScrolledUp() {
        var state = TailFollowState(isFollowingTail: false)
        let action = reduce(&state, .messageAdded(role: .assistant, didPrependOlder: false))

        #expect(action == .none)
        #expect(state.lastProgrammaticScrollAt == nil)
    }

    @Test("System message no scroll when scrolled up")
    func systemMessageNoScrollWhenScrolledUp() {
        var state = TailFollowState(isFollowingTail: false)
        let action = reduce(&state, .messageAdded(role: .system, didPrependOlder: false))

        #expect(action == .none)
    }

    @Test("Streaming started sets distant future marker")
    func streamingStartedMarker() {
        var state = TailFollowState()
        let action = reduce(&state, .streamingStarted)

        #expect(action == .none)
        #expect(state.lastStreamingCompletedAt == .distantFuture)
    }

    @Test("Streaming completed sets timestamp")
    func streamingCompletedTimestamp() {
        var state = TailFollowState(lastStreamingCompletedAt: .distantFuture)
        let action = reduce(&state, .streamingCompleted, secondsFromBase: 7)

        #expect(action == .none)
        #expect(state.lastStreamingCompletedAt == baseNow.addingTimeInterval(7))
    }

    @Test("Conversation switch resets to following")
    func conversationSwitchResets() {
        var state = TailFollowState(isFollowingTail: false)
        let action = reduce(&state, .conversationSwitched)

        #expect(action == .none)
        #expect(state.isFollowingTail)
    }

    @Test("Conversation switch clears streaming state")
    func conversationSwitchClearsStreaming() {
        var state = TailFollowState(lastStreamingCompletedAt: .distantFuture)
        _ = reduce(&state, .conversationSwitched)

        #expect(state.lastStreamingCompletedAt == nil)
    }

    @Test("Conversation switch sets pending switch scroll")
    func conversationSwitchSetsPending() {
        var state = TailFollowState(pendingSwitchScroll: false)
        _ = reduce(&state, .conversationSwitched)

        #expect(state.pendingSwitchScroll)
        #expect(state.lastProgrammaticScrollAt == nil)
    }

    @Test("Multiple distance changes during streaming")
    func multipleDistanceChangesDuringStreaming() {
        var state = TailFollowState(isFollowingTail: true, lastStreamingCompletedAt: .distantFuture)

        _ = reduce(&state, .distanceChanged(81))
        #expect(state.isFollowingTail)

        _ = reduce(&state, .distanceChanged(259))
        #expect(state.isFollowingTail)

        _ = reduce(&state, .distanceChanged(261))
        #expect(!state.isFollowingTail)
    }

    @Test("Transition from following to not following to following")
    func followingTransitionCycle() {
        var state = TailFollowState(isFollowingTail: true)

        _ = reduce(&state, .distanceChanged(81))
        #expect(!state.isFollowingTail)

        _ = reduce(&state, .distanceChanged(80))
        #expect(state.isFollowingTail)
    }

    @Test("Programmatic scroll marker cleared after grace")
    func programmaticScrollMarkerCleared() {
        var state = TailFollowState(isFollowingTail: true)

        _ = reduce(&state, .programmaticScrollInitiated)
        _ = reduce(&state, .distanceChanged(500), secondsFromBase: 0.05)
        #expect(state.isFollowingTail)

        _ = reduce(&state, .distanceChanged(500), secondsFromBase: 0.101)
        #expect(!state.isFollowingTail)
    }
}
