import Foundation
import XCTest
@testable import HushCore

// MARK: - RequestID Tests

final class RequestIDTests: XCTestCase {

    func testUniqueness() {
        let a = RequestID()
        let b = RequestID()
        XCTAssertNotEqual(a, b)
    }

    func testHashEquality() {
        let uuid = UUID()
        let a = RequestID(value: uuid)
        let b = RequestID(value: uuid)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testDescription() {
        let uuid = UUID()
        let rid = RequestID(value: uuid)
        XCTAssertEqual(rid.description, uuid.uuidString)
    }

    func testCodableRoundTrip() throws {
        let original = RequestID()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RequestID.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}

// MARK: - ActiveRequestState Tests

final class ActiveRequestStateTests: XCTestCase {

    func testInitialState() {
        let rid = RequestID()
        let state = ActiveRequestState(requestID: rid)

        XCTAssertEqual(state.requestID, rid)
        XCTAssertEqual(state.status, .preflight)
        XCTAssertEqual(state.accumulatedText, "")
        XCTAssertNil(state.assistantMessageID)
        XCTAssertFalse(state.isTerminal)
    }

    func testPreflightIsNotTerminal() {
        var state = ActiveRequestState(requestID: RequestID())
        state.status = .preflight
        XCTAssertFalse(state.isTerminal)
    }

    func testStreamingIsNotTerminal() {
        var state = ActiveRequestState(requestID: RequestID())
        state.status = .streaming
        XCTAssertFalse(state.isTerminal)
    }

    func testCompletedIsTerminal() {
        var state = ActiveRequestState(requestID: RequestID())
        state.status = .completed
        XCTAssertTrue(state.isTerminal)
    }

    func testFailedIsTerminal() {
        var state = ActiveRequestState(requestID: RequestID())
        state.status = .failed(.cancelled)
        XCTAssertTrue(state.isTerminal)
    }

    func testStoppedIsTerminal() {
        var state = ActiveRequestState(requestID: RequestID())
        state.status = .stopped
        XCTAssertTrue(state.isTerminal)
    }

    func testAccumulatedTextAppend() {
        var state = ActiveRequestState(requestID: RequestID())
        state.accumulatedText += "Hello"
        state.accumulatedText += " World"
        XCTAssertEqual(state.accumulatedText, "Hello World")
    }
}

// MARK: - QueueItemSnapshot Tests

final class QueueItemSnapshotTests: XCTestCase {

    func testInitCapturesAllFields() {
        let msgID = UUID()
        let params = ModelParameters.standard
        let snapshot = QueueItemSnapshot(
            prompt: "test",
            providerID: "mock",
            modelID: "mock-text-1",
            parameters: params,
            userMessageID: msgID
        )

        XCTAssertEqual(snapshot.prompt, "test")
        XCTAssertEqual(snapshot.providerID, "mock")
        XCTAssertEqual(snapshot.modelID, "mock-text-1")
        XCTAssertEqual(snapshot.parameters, params)
        XCTAssertEqual(snapshot.userMessageID, msgID)
    }

    func testAutoGeneratesRequestID() {
        let a = QueueItemSnapshot(
            prompt: "a",
            providerID: "mock",
            modelID: "m",
            parameters: .standard,
            userMessageID: UUID()
        )
        let b = QueueItemSnapshot(
            prompt: "b",
            providerID: "mock",
            modelID: "m",
            parameters: .standard,
            userMessageID: UUID()
        )
        XCTAssertNotEqual(a.id, b.id)
    }

    func testEquality() {
        let rid = RequestID()
        let msgID = UUID()
        let date = Date.now
        let a = QueueItemSnapshot(
            id: rid,
            prompt: "test",
            providerID: "mock",
            modelID: "m",
            parameters: .standard,
            userMessageID: msgID,
            createdAt: date
        )
        let b = QueueItemSnapshot(
            id: rid,
            prompt: "test",
            providerID: "mock",
            modelID: "m",
            parameters: .standard,
            userMessageID: msgID,
            createdAt: date
        )
        XCTAssertEqual(a, b)
    }
}

// MARK: - StreamEvent Tests

final class StreamEventTests: XCTestCase {

    func testStartedEquality() {
        let rid = RequestID()
        XCTAssertEqual(
            StreamEvent.started(requestID: rid),
            StreamEvent.started(requestID: rid)
        )
    }

    func testDeltaEquality() {
        let rid = RequestID()
        XCTAssertEqual(
            StreamEvent.delta(requestID: rid, text: "hello"),
            StreamEvent.delta(requestID: rid, text: "hello")
        )
    }

    func testDeltaInequalityOnText() {
        let rid = RequestID()
        XCTAssertNotEqual(
            StreamEvent.delta(requestID: rid, text: "a"),
            StreamEvent.delta(requestID: rid, text: "b")
        )
    }

    func testCompletedEquality() {
        let rid = RequestID()
        XCTAssertEqual(
            StreamEvent.completed(requestID: rid),
            StreamEvent.completed(requestID: rid)
        )
    }

    func testFailedEquality() {
        let rid = RequestID()
        XCTAssertEqual(
            StreamEvent.failed(requestID: rid, error: .cancelled),
            StreamEvent.failed(requestID: rid, error: .cancelled)
        )
    }

    func testDifferentEventsAreNotEqual() {
        let rid = RequestID()
        let started = StreamEvent.started(requestID: rid)
        let completed = StreamEvent.completed(requestID: rid)
        XCTAssertNotEqual(started, completed)
    }
}

// MARK: - RequestError Tests

final class RequestErrorTests: XCTestCase {

    func testProviderMissingDescription() {
        let error = RequestError.providerMissing(providerID: "openai")
        XCTAssertTrue(error.errorDescription!.contains("openai"))
        XCTAssertTrue(error.errorDescription!.contains("not found"))
    }

    func testProviderDisabledDescription() {
        let error = RequestError.providerDisabled(providerID: "openai")
        XCTAssertTrue(error.errorDescription!.contains("disabled"))
    }

    func testProviderNotRegisteredDescription() {
        let error = RequestError.providerNotRegistered(providerID: "openai")
        XCTAssertTrue(error.errorDescription!.contains("No runtime implementation"))
    }

    func testModelInvalidDescription() {
        let error = RequestError.modelInvalid(modelID: "gpt-5", providerID: "openai")
        XCTAssertTrue(error.errorDescription!.contains("gpt-5"))
        XCTAssertTrue(error.errorDescription!.contains("openai"))
    }

    func testPreflightTimeoutDescription() {
        let error = RequestError.preflightTimeout(seconds: 3.0)
        XCTAssertTrue(error.errorDescription!.contains("3.0"))
        XCTAssertTrue(error.errorDescription!.contains("timed out"))
    }

    func testGenerationTimeoutDescription() {
        let error = RequestError.generationTimeout(seconds: 60.0)
        XCTAssertTrue(error.errorDescription!.contains("60"))
        XCTAssertTrue(error.errorDescription!.contains("timed out"))
    }

    func testRemoteErrorDescription() {
        let error = RequestError.remoteError(provider: "openai", message: "rate limit")
        XCTAssertTrue(error.errorDescription!.contains("openai"))
        XCTAssertTrue(error.errorDescription!.contains("rate limit"))
    }

    func testQueueFullDescription() {
        let error = RequestError.queueFull(capacity: 5)
        XCTAssertTrue(error.errorDescription!.contains("5"))
    }

    func testCancelledDescription() {
        let error = RequestError.cancelled
        XCTAssertTrue(error.errorDescription!.contains("cancelled"))
    }

    func testEquality() {
        XCTAssertEqual(RequestError.cancelled, RequestError.cancelled)
        XCTAssertNotEqual(
            RequestError.providerMissing(providerID: "a"),
            RequestError.providerMissing(providerID: "b")
        )
    }
}

// MARK: - RuntimeConstants Tests

final class RuntimeConstantsTests: XCTestCase {

    func testDefaultPendingQueueCapacity() {
        XCTAssertEqual(RuntimeConstants.pendingQueueCapacity, 5)
    }

    func testDefaultPreflightTimeout() {
        XCTAssertEqual(RuntimeConstants.preflightTimeoutSeconds, 3.0)
    }

    func testDefaultGenerationTimeout() {
        XCTAssertEqual(RuntimeConstants.generationTimeoutSeconds, 60.0)
    }

    func testDurationConsistency() {
        XCTAssertEqual(
            RuntimeConstants.preflightTimeout,
            Duration.seconds(RuntimeConstants.preflightTimeoutSeconds)
        )
        XCTAssertEqual(
            RuntimeConstants.generationTimeout,
            Duration.seconds(RuntimeConstants.generationTimeoutSeconds)
        )
    }

    func testSettingsDebounceInterval() {
        XCTAssertEqual(RuntimeConstants.settingsDebounceInterval, .seconds(1))
    }
}

// MARK: - ChatMessage Tests

final class ChatMessageTests: XCTestCase {

    func testDefaultIDIsGenerated() {
        let a = ChatMessage(role: .user, content: "hi")
        let b = ChatMessage(role: .user, content: "hi")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testExplicitID() {
        let uuid = UUID()
        let msg = ChatMessage(id: uuid, role: .assistant, content: "test")
        XCTAssertEqual(msg.id, uuid)
    }

    func testCodableRoundTrip() throws {
        let msg = ChatMessage(role: .user, content: "hello world")
        let data = try JSONEncoder().encode(msg)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)
        XCTAssertEqual(msg, decoded)
    }

    func testAllRoles() {
        for role in ChatRole.allCases {
            let msg = ChatMessage(role: role, content: "test")
            XCTAssertEqual(msg.role, role)
        }
    }
}
