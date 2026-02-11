import Foundation
@testable import Hush

enum SidebarPolicy {
    static func resolveActivityState(
        isRunning: Bool,
        queuedCount: Int,
        hasUnreadCompletion: Bool
    ) -> SidebarActivityState {
        if isRunning {
            return .running
        }
        if queuedCount > 0 {
            return .queued
        }
        if hasUnreadCompletion {
            return .unreadCompletion
        }
        return .idle
    }

    static let threadContextActionIDs: [String] = ["delete"]
}
