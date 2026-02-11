import AppKit
import Foundation
@testable import Hush
import Testing

@MainActor
@Suite("MessageTableView Apply Strategy")
struct MessageTableViewApplyStrategyTests {
    private func makeMessage(
        id: UUID,
        role: ChatRole = .assistant,
        content: String
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            role: role,
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test("Append update uses incremental insert mode")
    func appendUsesIncrementalInsert() throws {
        let table = MessageTableView()
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let m1 = try makeMessage(id: #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")), content: "one")
        let m2 = try makeMessage(id: #require(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")), content: "two")

        table.apply(
            messages: [m1],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        table.apply(
            messages: [m1, m2],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        #expect(table.lastUpdateModeForTesting == .appendInsert(insertedCount: 1))
    }

    @Test("Prepend older history falls back to full reload")
    func prependFallsBackToReload() throws {
        let table = MessageTableView()
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let m1 = try makeMessage(id: #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")), content: "older")
        let m2 = try makeMessage(id: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")), content: "middle")
        let m3 = try makeMessage(id: #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")), content: "latest")

        table.apply(
            messages: [m2, m3],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        table.apply(
            messages: [m1, m2, m3],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        #expect(table.lastUpdateModeForTesting == .fullReload)
    }

    @Test("Same-count streaming update refreshes existing row")
    func sameCountStreamingRefreshesRow() throws {
        let table = MessageTableView()
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let messageID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
        let first = makeMessage(id: messageID, content: "partial")
        let second = makeMessage(id: messageID, content: "partial + delta")

        table.apply(
            messages: [first],
            activeConversationID: "conv-1",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        table.apply(
            messages: [second],
            activeConversationID: "conv-1",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        #expect(table.lastUpdateModeForTesting == .streamingRefresh(row: 0))
    }

    @Test("Streaming end with content change still refreshes row")
    func streamingEndWithContentChangeRefreshesRow() throws {
        let table = MessageTableView()
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let messageID = try #require(UUID(uuidString: "88888888-4444-4444-4444-444444444444"))
        let streaming = makeMessage(id: messageID, content: "partial")
        let final = makeMessage(id: messageID, content: "final")

        table.apply(
            messages: [streaming],
            activeConversationID: "conv-1",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        table.apply(
            messages: [final],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        #expect(table.lastUpdateModeForTesting == .streamingRefresh(row: 0))
    }

    @Test("Streaming end with unchanged content still refreshes row")
    func streamingEndWithUnchangedContentRefreshesRow() throws {
        let table = MessageTableView()
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let messageID = try #require(UUID(uuidString: "99999999-4444-4444-4444-444444444444"))
        let first = makeMessage(id: messageID, content: "same")
        let second = makeMessage(id: messageID, content: "same")

        table.apply(
            messages: [first],
            activeConversationID: "conv-1",
            isActiveConversationSending: true,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        table.apply(
            messages: [second],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        #expect(table.lastUpdateModeForTesting == .streamingRefresh(row: 0))
    }

    @Test("Non-streaming unchanged rows stay no-op")
    func nonStreamingUnchangedRowsNoOp() throws {
        let table = MessageTableView()
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let messageID = try #require(UUID(uuidString: "AAAAAAAA-4444-4444-4444-444444444444"))
        let first = makeMessage(id: messageID, content: "stable")
        let second = makeMessage(id: messageID, content: "stable")

        table.apply(
            messages: [first],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        table.apply(
            messages: [second],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        #expect(table.lastUpdateModeForTesting == .noOp)
    }

    @Test("Non-streaming content change does not use streaming refresh")
    func nonStreamingContentChangeNotStreamingRefresh() throws {
        let table = MessageTableView()
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let messageID = try #require(UUID(uuidString: "BBBBBBBB-4444-4444-4444-444444444444"))
        let first = makeMessage(id: messageID, content: "old")
        let second = makeMessage(id: messageID, content: "new")

        table.apply(
            messages: [first],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        table.apply(
            messages: [second],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        #expect(table.lastUpdateModeForTesting != .streamingRefresh(row: 0))
    }

    @Test("Generation switch always uses full reload mode")
    func generationSwitchUsesFullReload() throws {
        let table = MessageTableView()
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let m1 = try makeMessage(id: #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555")), content: "hello")

        table.apply(
            messages: [m1],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        table.apply(
            messages: [m1],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 2,
            runtime: runtime,
            container: container
        )

        #expect(table.lastUpdateModeForTesting == .fullReload)
    }

    @Test("Generation switch resets live scrolling state")
    func generationSwitchResetsLiveScrolling() throws {
        let table = MessageTableView()
        let runtime = MessageRenderRuntime()
        let container = AppContainer.forTesting(settings: .testDefault)

        let m1 = try makeMessage(id: #require(UUID(uuidString: "ABABABAB-5555-5555-5555-555555555555")), content: "hello")

        table.apply(
            messages: [m1],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 1,
            runtime: runtime,
            container: container
        )

        table.simulateLiveScrollStartForTesting()
        #expect(table.isLiveScrollingForTesting)

        table.apply(
            messages: [m1],
            activeConversationID: "conv-1",
            isActiveConversationSending: false,
            switchGeneration: 2,
            runtime: runtime,
            container: container
        )

        #expect(!table.isLiveScrollingForTesting)
    }
}
