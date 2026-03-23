import AppKit
import Carbon.HIToolbox
@testable import Hush
import Testing

struct QuickBarShortcutRecordingSessionTests {
    @Test("shows a live modifier preview before the final key is pressed")
    func showsLiveModifierPreview() {
        var session = QuickBarShortcutRecordingSession()

        session.handleFlagsChanged(modifierFlags: [.command, .shift])

        #expect(
            session.prompt == QuickBarShortcutRecordingPrompt(
                displayText: "⌘⇧...",
                hintText: "Press a key to complete the shortcut."
            )
        )
    }

    @Test("records the shortcut on key release instead of key down")
    func recordsShortcutOnKeyRelease() {
        var session = QuickBarShortcutRecordingSession()

        let keyDownAction = session.handleKeyDown(
            keyCode: UInt16(kVK_ANSI_K),
            modifierFlags: [.command, .shift]
        )
        #expect(keyDownAction == .none)
        #expect(
            session.prompt == QuickBarShortcutRecordingPrompt(
                displayText: "⌘⇧K",
                hintText: "Release to save."
            )
        )

        let keyUpAction = session.handleKeyUp(keyCode: UInt16(kVK_ANSI_K))
        #expect(
            keyUpAction == .record(
                QuickBarConfiguration(
                    key: "K",
                    modifiers: ["command", "shift"]
                )
            )
        )
    }

    @Test("rejects shortcuts without modifiers while staying in recording mode")
    func rejectsShortcutWithoutModifiers() {
        var session = QuickBarShortcutRecordingSession()

        let keyDownAction = session.handleKeyDown(
            keyCode: UInt16(kVK_ANSI_K),
            modifierFlags: []
        )
        #expect(keyDownAction == .beep)
        #expect(
            session.prompt == QuickBarShortcutRecordingPrompt(
                displayText: "Press shortcut",
                hintText: "Use at least one modifier with a letter, digit, or Space."
            )
        )

        let keyUpAction = session.handleKeyUp(keyCode: UInt16(kVK_ANSI_K))
        #expect(keyUpAction == .none)
    }

    @Test("escape cancels the recording session immediately")
    func escapeCancelsRecording() {
        var session = QuickBarShortcutRecordingSession()

        let action = session.handleKeyDown(
            keyCode: UInt16(kVK_Escape),
            modifierFlags: []
        )

        #expect(action == .cancel)
    }
}
