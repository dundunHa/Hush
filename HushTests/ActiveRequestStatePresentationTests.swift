import Foundation
@testable import Hush
import Testing

struct ActiveRequestStatePresentationTests {
    @Test("presented text remains separate from accumulated text")
    func presentedTextTracksRevealProgress() {
        let requestID = RequestID()
        var state = ActiveRequestState(requestID: requestID, conversationId: "conv-1")

        state.appendDelta("Hello")
        #expect(state.accumulatedText == "Hello")
        #expect(state.presentedText.isEmpty)
        #expect(state.pendingPresentedCharacterCount == 5)

        state.revealBy(characters: 2)
        #expect(state.presentedText == "He")
        #expect(state.pendingPresentedCharacterCount == 3)

        state.appendDelta(" world")
        #expect(state.accumulatedText == "Hello world")
        #expect(state.presentedText == "He")
        #expect(state.pendingPresentedCharacterCount == 9)

        state.revealAll()
        #expect(state.presentedText == "Hello world")
        #expect(state.pendingPresentedCharacterCount == 0)
    }

    @Test("reveal uses character boundaries for unicode content")
    func revealUsesCharacterBoundaries() {
        let requestID = RequestID()
        var state = ActiveRequestState(requestID: requestID, conversationId: "conv-1")

        state.appendDelta("你🙂界")
        state.revealBy(characters: 2)

        #expect(state.presentedText == "你🙂")
        #expect(state.presentedCharacterCount == 2)
        #expect(state.pendingPresentedCharacterCount == 1)
    }
}
