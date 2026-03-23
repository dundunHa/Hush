import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
struct MessageTableViewSurfaceStyleTests {
    private func makeContainer() -> AppContainer {
        AppContainer.forTesting(
            messageRenderRuntime: MessageRenderRuntime(),
            enableStartupPrewarm: false
        )
    }

    private func makeMessage() -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "Preview the updated quick bar transcript styling."
        )
    }

    private func makeTable(width: CGFloat = 640, height: CGFloat = 320) -> MessageTableView {
        let table = MessageTableView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        table.layoutSubtreeIfNeeded()
        return table
    }

    @Test("Main chat keeps the default conversation surface style")
    func mainConversationKeepsDefaultSurfaceStyle() {
        let container = makeContainer()
        let table = makeTable()
        let message = makeMessage()

        table.apply(
            messages: [message],
            activeConversationID: "conv-main",
            isActiveConversationSending: false,
            switchGeneration: 1,
            theme: container.settings.theme,
            runtime: container.messageRenderRuntime,
            container: container
        )

        #expect(table.surfaceStyleForTesting == .main)
    }

    @Test("Changing to quick bar surface style forces a full reload")
    func switchingSurfaceStyleForcesReload() {
        let container = makeContainer()
        let table = makeTable()
        let message = makeMessage()

        table.apply(
            messages: [message],
            activeConversationID: "conv-main",
            isActiveConversationSending: false,
            switchGeneration: 1,
            theme: container.settings.theme,
            runtime: container.messageRenderRuntime,
            container: container
        )

        table.apply(
            messages: [message],
            activeConversationID: "conv-main",
            isActiveConversationSending: false,
            switchGeneration: 1,
            theme: container.settings.theme,
            surfaceStyle: .quickBar,
            runtime: container.messageRenderRuntime,
            container: container
        )

        #expect(table.surfaceStyleForTesting == .quickBar)
        #expect(table.lastUpdateModeForTesting == .fullReload)
    }
}
