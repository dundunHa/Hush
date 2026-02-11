import Foundation
@testable import Hush
import Testing

@Suite("Conversation Sidebar Policy Tests")
struct ConversationSidebarViewPolicyTests {
    @Test("Sidebar context actions exclude stop")
    func contextActionsExcludeStop() {
        let actions = SidebarPolicy.threadContextActionIDs
        #expect(actions == ["delete"])
        #expect(!actions.contains("stop"))
    }

    @Test("Activity badge priority: running > queued > unread > idle")
    func activityBadgePriority() {
        #expect(
            SidebarPolicy.resolveActivityState(
                isRunning: true,
                queuedCount: 3,
                hasUnreadCompletion: true
            ) == .running
        )

        #expect(
            SidebarPolicy.resolveActivityState(
                isRunning: false,
                queuedCount: 2,
                hasUnreadCompletion: true
            ) == .queued
        )

        #expect(
            SidebarPolicy.resolveActivityState(
                isRunning: false,
                queuedCount: 0,
                hasUnreadCompletion: true
            ) == .unreadCompletion
        )

        #expect(
            SidebarPolicy.resolveActivityState(
                isRunning: false,
                queuedCount: 0,
                hasUnreadCompletion: false
            ) == .idle
        )
    }
}
