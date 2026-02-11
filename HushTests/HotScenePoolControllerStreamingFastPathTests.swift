import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("HotScenePoolController Streaming Fast-Path")
struct HotScenePoolControllerStreamingFastPathTests {
    @Test("Streaming delta-only update pushes content without applyConversationState")
    func streamingDeltaOnlyUpdateSkipsApply() throws {
        let conversationID = "conv-stream-fastpath"
        let user1ID = try #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let assistant1ID = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let user2ID = try #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let assistant2ID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))

        let initialMessages: [ChatMessage] = [
            ChatMessage(id: user1ID, role: .user, content: "Q1", createdAt: Date(timeIntervalSince1970: 1_700_000_000)),
            ChatMessage(id: assistant1ID, role: .assistant, content: "A1", createdAt: Date(timeIntervalSince1970: 1_700_000_001)),
            ChatMessage(id: user2ID, role: .user, content: "Q2", createdAt: Date(timeIntervalSince1970: 1_700_000_002)),
            ChatMessage(id: assistant2ID, role: .assistant, content: "partial", createdAt: Date(timeIntervalSince1970: 1_700_000_003))
        ]

        let container = AppContainer.forTesting(
            settings: .testDefault,
            activeConversationId: conversationID,
            messages: initialMessages
        )
        container.setRunningConversationIDsForTesting([conversationID])

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        _ = controller.view

        controller.update(container: container)

        let scene = try #require(pool.sceneFor(conversationID: conversationID))
        let baselineApplyCount = scene.applyCountForTesting
        #expect(baselineApplyCount >= 1)
        #expect(scene.streamingPushCountForTesting == 0)

        // Only the last assistant message content changes while isSending remains true.
        container.messages = [
            initialMessages[0],
            initialMessages[1],
            initialMessages[2],
            ChatMessage(
                id: assistant2ID,
                role: .assistant,
                content: "partial + token",
                createdAt: initialMessages[3].createdAt
            )
        ]

        controller.update(container: container)

        #expect(scene.applyCountForTesting == baselineApplyCount)
        #expect(scene.streamingPushCountForTesting == 1)
        #expect(scene.lastStreamingPushMessageIDForTesting == assistant2ID)
        #expect(scene.lastStreamingPushContentForTesting == "partial + token")
    }
}
