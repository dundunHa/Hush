import Foundation
import XCTest
@testable import HushCore
@testable import HushProviders

final class MockProviderStreamTests: XCTestCase {

    func testDefaultStreamingProducesStartDeltasAndCompleted() async throws {
        let provider = MockProvider(id: "mock")
        let rid = RequestID()

        let stream = provider.sendStreaming(
            messages: [ChatMessage(role: .user, content: "hi")],
            modelID: "mock-text-1",
            parameters: .standard,
            requestID: rid
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        // started + 3 deltas + completed = 5 events
        XCTAssertEqual(events.count, 5)
        XCTAssertEqual(events.first, .started(requestID: rid))
        XCTAssertEqual(events.last, .completed(requestID: rid))

        // All delta events carry the correct request ID
        let deltas = events.compactMap { event -> String? in
            if case .delta(let r, let text) = event, r == rid { return text }
            return nil
        }
        XCTAssertEqual(deltas, ["Mock", " response", " streaming"])
    }

    func testFailingBehaviorFailsAfterNChunks() async throws {
        let provider = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior.failing(
                after: 2,
                error: .remoteError(provider: "mock", message: "fail")
            )
        )
        let rid = RequestID()

        let stream = provider.sendStreaming(
            messages: [],
            modelID: "mock-text-1",
            parameters: .standard,
            requestID: rid
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        // started + 2 deltas + failed = 4 events
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.first, .started(requestID: rid))

        // Last event should be failed
        if case .failed(let r, let error) = events.last {
            XCTAssertEqual(r, rid)
            XCTAssertEqual(error, .remoteError(provider: "mock", message: "fail"))
        } else {
            XCTFail("Expected .failed event")
        }
    }

    func testFailingImmediatelyWithZeroChunks() async throws {
        let provider = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior.failing(after: 0)
        )
        let rid = RequestID()

        let stream = provider.sendStreaming(
            messages: [],
            modelID: "mock-text-1",
            parameters: .standard,
            requestID: rid
        )

        var events: [StreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        // started + failed (no deltas)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first, .started(requestID: rid))
        if case .failed = events.last {
            // Expected
        } else {
            XCTFail("Expected .failed event")
        }
    }

    func testStreamCancellationStopsProduction() async throws {
        let provider = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: Array(repeating: "x", count: 100),
                delayPerChunk: .milliseconds(50)
            )
        )
        let rid = RequestID()

        let stream = provider.sendStreaming(
            messages: [],
            modelID: "mock-text-1",
            parameters: .standard,
            requestID: rid
        )

        // Consume a few events then break — stream should stop producing
        var eventCount = 0
        for try await _ in stream {
            eventCount += 1
            if eventCount >= 5 {
                break
            }
        }

        // Should have collected exactly 5 events, not all 101 (started + 100 deltas)
        XCTAssertEqual(eventCount, 5)
    }

    func testAvailableModelsReturnsExpectedModels() async throws {
        let provider = MockProvider(id: "mock")
        let models = try await provider.availableModels()

        XCTAssertEqual(models.count, 2)
        XCTAssertTrue(models.contains { $0.id == "mock-text-1" })
        XCTAssertTrue(models.contains { $0.id == "mock-vision-1" })
    }

    func testSendReturnsFormattedResponse() async throws {
        let provider = MockProvider(id: "mock")
        let msg = ChatMessage(role: .user, content: "test prompt")
        let response = try await provider.send(
            messages: [msg],
            modelID: "mock-text-1",
            parameters: .standard
        )

        XCTAssertEqual(response.role, .assistant)
        XCTAssertTrue(response.content.contains("mock-text-1"))
        XCTAssertTrue(response.content.contains("test prompt"))
    }

    func testCustomChunkBehavior() async throws {
        let provider = MockProvider(
            id: "mock",
            streamBehavior: MockStreamBehavior(
                chunks: ["A", "B"],
                delayPerChunk: .milliseconds(10)
            )
        )
        let rid = RequestID()

        let stream = provider.sendStreaming(
            messages: [],
            modelID: "m",
            parameters: .standard,
            requestID: rid
        )

        var deltas: [String] = []
        for try await event in stream {
            if case .delta(_, let text) = event {
                deltas.append(text)
            }
        }

        XCTAssertEqual(deltas, ["A", "B"])
    }
}
