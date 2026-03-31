import Carbon.HIToolbox
@testable import Hush
import Testing

struct QuickBarConfigurationTests {
    @Test("invalid quick bar configuration falls back to the standard shortcut")
    func invalidConfigurationFallsBackToStandard() {
        let invalid = QuickBarConfiguration(
            key: "",
            modifiers: []
        )

        #expect(invalid.validated() == .standard)
    }

    @Test("space shortcut normalizes to a visible display string")
    func spaceShortcutNormalizesAndFormats() {
        let shortcut = QuickBarConfiguration(
            key: "space",
            modifiers: ["option", "option"]
        ).validated()

        #expect(shortcut.key == QuickBarConfiguration.spaceKey)
        #expect(shortcut.modifiers == ["option"])
        #expect(shortcut.displayString == "⌥Space")
    }

    @Test("hotkey controller maps the standard shortcut to Carbon key codes")
    func carbonShortcutMappingMatchesStandardShortcut() {
        let shortcut = QuickBarHotkeyController.carbonShortcut(for: .standard)

        #expect(shortcut?.keyCode == UInt32(kVK_Space))
        #expect(shortcut?.modifiers == UInt32(optionKey))
    }
}
