import Foundation
@testable import Hush
import Testing

@Suite("MessageTableView Scroll")
struct MessageTableViewScrollTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("User message forces scroll to bottom")
    func userMessageForcesScroll() {
        var state = TailFollowState(isFollowingTail: false)
        let config = TailFollowConfig()

        let action = TailFollow.reduce(
            state: &state,
            event: .messageAdded(role: .user, didPrependOlder: false),
            config: config,
            now: now
        )

        #expect(action == .scrollToBottom(animated: true, reason: .newUser))
        #expect(state.isFollowingTail)
    }

    @Test("Assistant message suppressed when scrolled up")
    func assistantMessageSuppressed() {
        var state = TailFollowState(isFollowingTail: false)
        let config = TailFollowConfig()

        let action = TailFollow.reduce(
            state: &state,
            event: .messageAdded(role: .assistant, didPrependOlder: false),
            config: config,
            now: now
        )

        #expect(action == .none)
    }
}
