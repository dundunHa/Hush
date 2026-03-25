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

    @Test("Quick bar visible cells keep a centered readable column inside a wide table")
    func quickBarVisibleCellsKeepCenteredReadableColumnInsideWideTable() throws {
        let container = makeContainer()
        let table = makeTable(width: 1400, height: 420)
        let assistant = ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "Hi! How can I help you today?"
        )
        let user = ChatMessage(
            id: UUID(),
            role: .user,
            content: "say hi"
        )

        table.apply(
            messages: [assistant, user],
            activeConversationID: "conv-quickbar",
            isActiveConversationSending: false,
            switchGeneration: 1,
            theme: container.settings.theme,
            surfaceStyle: .quickBar,
            runtime: container.messageRenderRuntime,
            container: container
        )
        table.layoutSubtreeIfNeeded()
        table.prepareCellForTesting(row: 0)
        table.prepareCellForTesting(row: 1)

        let assistantCell = try #require(table.visibleCellForTesting(row: 0))
        let userCell = try #require(table.visibleCellForTesting(row: 1))
        let assistantContentFrame = assistantCell.convert(
            assistantCell.contentContainerFrameForTesting,
            to: table
        )
        let userContentFrame = userCell.convert(
            userCell.contentContainerFrameForTesting,
            to: table
        )

        #expect(abs(assistantContentFrame.width - 640) <= 0.5)
        #expect(abs(assistantContentFrame.midX - table.bounds.midX) <= 0.5)
        #expect(abs(userContentFrame.width - 640) <= 0.5)
        #expect(abs(userContentFrame.midX - table.bounds.midX) <= 0.5)
    }
}
