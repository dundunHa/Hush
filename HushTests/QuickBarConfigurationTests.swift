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

    @Test("hotkey controller maps the standard shortcut to Carbon key codes")
    func carbonShortcutMappingMatchesStandardShortcut() {
        let shortcut = QuickBarHotkeyController.carbonShortcut(for: .standard)

        #expect(shortcut?.keyCode == UInt32(kVK_ANSI_K))
        #expect(shortcut?.modifiers == UInt32(cmdKey | optionKey))
    }
}
