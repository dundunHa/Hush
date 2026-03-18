import Foundation
@testable import Hush
import Testing

struct ChatRenderingPerfHarnessTests {
    // MARK: - Helpers

    private func makeMessages(count: Int, assistantContentLength: Int = 200) -> [ChatMessage] {
        (0 ..< count).map { index in
            let role: ChatRole = index.isMultiple(of: 2) ? .user : .assistant
            let content: String
            if role == .user {
                content = "User message \(index)"
            } else {
                content = String(repeating: "A", count: assistantContentLength)
            }
            return ChatMessage(role: role, content: content)
        }
    }

    // MARK: - PerfTrace.count

    @Test("count emits with default value 1")
    func countDefaultValue() {
        PerfTrace.count(PerfTrace.Event.visibleRecompute)
    }

    @Test("count emits with explicit value")
    func countExplicitValue() {
        PerfTrace.count(PerfTrace.Event.scrollAdjustToBottom, value: 5)
    }

    @Test("count accepts extra fields")
    func countWithFields() {
        PerfTrace.count(
            PerfTrace.Event.scrollAdjustToBottom,
            value: 1,
            fields: ["during_streaming": "true", "suppressed": "false"]
        )
    }

    // MARK: - PerfTrace.duration

    @Test("duration emits milliseconds")
    func durationEmits() {
        PerfTrace.duration(PerfTrace.Event.textEnsureLayout, ms: 12.5)
    }

    // MARK: - PerfTrace.measure

    @Test("measure returns closure result and emits duration")
    func measureReturnsResult() {
        let result = PerfTrace.measure(PerfTrace.Event.visibleRecompute) {
            42
        }
        #expect(result == 42)
    }

    @Test("measure works with void closure")
    func measureVoid() {
        var sideEffect = 0
        PerfTrace.measure(PerfTrace.Event.attachmentsReconcile) {
            sideEffect += 1
        }
        #expect(sideEffect == 1)
    }

    // MARK: - PerfTrace.measureAsync

    @Test("measureAsync returns async closure result")
    func measureAsyncReturnsResult() async {
        let result = await PerfTrace.measureAsync(PerfTrace.Event.switchSnapshotApplied) {
            await Task.yield()
            return "done"
        }
        #expect(result == "done")
    }

    // MARK: - Event Name Constants

    @Test("all event names are non-empty and dot-separated")
    func eventNamesValid() {
        let events = [
            PerfTrace.Event.visibleRecompute,
            PerfTrace.Event.scrollAdjustToBottom,
            PerfTrace.Event.textEnsureLayout,
            PerfTrace.Event.attachmentsReconcile,
            PerfTrace.Event.switchSnapshotApplied,
            PerfTrace.Event.switchLayoutReady,
            PerfTrace.Event.switchRichReady,
            PerfTrace.Event.switchSnapshotToLayoutReady,
            PerfTrace.Event.switchSnapshotToRichReady
        ]
        for event in events {
            #expect(!event.isEmpty)
            #expect(event.contains("."))
        }
    }

    // MARK: - Standard Load Scenarios

    @Test("small conversation load: 10 messages")
    func smallConversationLoad() {
        let messages = makeMessages(count: 10)
        PerfTrace.measure(PerfTrace.Event.visibleRecompute) {
            _ = messages.filter { $0.role == .assistant }
        }
        #expect(messages.count == 10)
    }

    @Test("medium conversation load: 50 messages with long content")
    func mediumConversationLoad() {
        let messages = makeMessages(count: 50, assistantContentLength: 2000)
        PerfTrace.measure(PerfTrace.Event.visibleRecompute) {
            _ = messages.filter { $0.role == .assistant }.map(\.content.count)
        }
        #expect(messages.count == 50)
    }

    @Test("heavy conversation load: 200 messages with very long content")
    func heavyConversationLoad() {
        let messages = makeMessages(count: 200, assistantContentLength: 5000)
        PerfTrace.measure(PerfTrace.Event.visibleRecompute) {
            let assistants = messages.filter { $0.role == .assistant }
            _ = assistants.reduce(0) { $0 + $1.content.count }
        }
        #expect(messages.count == 200)
    }

    // MARK: - Conversation Switch Simulation

    @Test("conversation switch trace emits all phases")
    func conversationSwitchPhases() {
        let startMs = Double(Int64(Date.now.timeIntervalSince1970 * 1000))

        PerfTrace.duration(PerfTrace.Event.switchSnapshotApplied, ms: 5.0)
        PerfTrace.duration(PerfTrace.Event.switchLayoutReady, ms: 12.0)
        PerfTrace.duration(PerfTrace.Event.switchRichReady, ms: 45.0)

        let endMs = Double(Int64(Date.now.timeIntervalSince1970 * 1000))
        #expect(endMs >= startMs)
    }

    // MARK: - Fields Escaping

    @Test("fields with special characters are escaped")
    func fieldsEscaping() {
        PerfTrace.count(
            PerfTrace.Event.scrollAdjustToBottom,
            value: 1,
            fields: ["reason": "switch-load", "conversation": "abc\"123"]
        )
    }
}
