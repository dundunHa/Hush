import Foundation
@testable import Hush
import SwiftUI
import Testing

@Suite("Chat Scroll Perf Harness")
@MainActor
struct ChatScrollPerfHarnessTests {
    @Test("Visible recompute count drops after windowing integration")
    func scrollWindowingVisibleRecomputeCount() {
        let container = AppContainer.forTesting()

        let messages = (0 ..< 300).map { idx in
            ChatMessage(
                id: UUID(),
                role: .assistant,
                content: "Message \(idx)"
            )
        }

        let input = ChatWindowingInput(
            messageCount: messages.count,
            tailCount: 16,
            bufferSize: 9,
            anchorIndex: 150,
            previousAnchorIndex: nil,
            previousMessageCount: nil,
            previousWindowRange: nil,
            isPinned: false,
            isStreaming: false
        )

        let output = ChatWindowing.computeWindow(input)

        #expect(output.windowRange.count <= 150)
    }
}
