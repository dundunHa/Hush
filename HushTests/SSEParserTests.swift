@testable import Hush
import Testing

struct SSEParserTests {
    @Test("Multiline data payload joins with newline")
    func multilineDataPayload() {
        var parser = SSEParser()
        _ = parser.feedLine("data: hello")
        _ = parser.feedLine("data: world")
        let events = parser.feedLine("")

        #expect(events.count == 1)
        #expect(events.first?.data == "hello\nworld")
    }

    @Test("Unknown fields are ignored")
    func unknownFieldsIgnored() {
        var parser = SSEParser()
        _ = parser.feedLine("data: hello")
        _ = parser.feedLine("foo: bar")
        _ = parser.feedLine("baz: qux")
        let events = parser.feedLine("")

        #expect(events.count == 1)
        #expect(events.first?.data == "hello")
    }

    @Test("[DONE] sentinel data is emitted as-is")
    func doneSentinel() {
        var parser = SSEParser()
        _ = parser.feedLine("data: [DONE]")
        let events = parser.feedLine("")

        #expect(events.count == 1)
        #expect(events.first?.data == "[DONE]")
    }

    @Test("Comments are ignored")
    func commentsIgnored() {
        var parser = SSEParser()
        _ = parser.feedLine(": this is a comment")
        _ = parser.feedLine("data: visible")
        _ = parser.feedLine(": another comment")
        let events = parser.feedLine("")

        #expect(events.count == 1)
        #expect(events.first?.data == "visible")
    }

    @Test("Empty events are not emitted")
    func emptyEventsNotEmitted() {
        var parser = SSEParser()
        let events = parser.feedLine("")

        #expect(events.isEmpty)
    }
}
