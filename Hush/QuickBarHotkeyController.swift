import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class QuickBarHotkeyController {
    struct CarbonShortcut: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private static let hotKeySignature: OSType = 0x48515348 // HQSH
    private static let hotKeyIdentifier: UInt32 = 1
    private static let keyCodes: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A),
        "B": UInt32(kVK_ANSI_B),
        "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D),
        "E": UInt32(kVK_ANSI_E),
        "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G),
        "H": UInt32(kVK_ANSI_H),
        "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J),
        "K": UInt32(kVK_ANSI_K),
        "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M),
        "N": UInt32(kVK_ANSI_N),
        "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P),
        "Q": UInt32(kVK_ANSI_Q),
        "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S),
        "T": UInt32(kVK_ANSI_T),
        "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V),
        "W": UInt32(kVK_ANSI_W),
        "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y),
        "Z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9)
    ]

    private var eventHandler: EventHandlerRef?
    private var hotKeyReference: EventHotKeyRef?
    private var settingsCancellables = Set<AnyCancellable>()
    private var workspaceCancellables = Set<AnyCancellable>()
    private var onPress: (() -> Void)?
    private var currentConfiguration: QuickBarConfiguration?

    init() {
        installEventHandlerIfNeeded()
        observeWorkspaceLifecycle()
    }

    deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
        }
    }

    func bind(
        container: AppContainer,
        onPress: @escaping () -> Void
    ) {
        self.onPress = onPress
        settingsCancellables.removeAll()

        container.$settings
            .map(\.quickBar)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] configuration in
                self?.register(configuration: configuration)
            }
            .store(in: &settingsCancellables)

        register(configuration: container.settings.quickBar)
    }

    func unregister() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
    }

    func register(configuration: QuickBarConfiguration) {
        currentConfiguration = configuration.validated(fallback: configuration)
        unregister()

        guard let currentConfiguration,
              shouldOwnHotKey(),
              let shortcut = Self.carbonShortcut(for: currentConfiguration)
        else {
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: Self.hotKeyIdentifier
        )
        RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
    }

    static func carbonShortcut(for configuration: QuickBarConfiguration) -> CarbonShortcut? {
        guard configuration.isValid else { return nil }
        let validated = configuration.validated(fallback: configuration)
        guard validated.isValid else { return nil }
        guard let keyCode = keyCodes[validated.normalizedKey] else { return nil }

        let modifiers = validated.normalizedModifiers.reduce(into: UInt32(0)) { result, modifier in
            switch modifier {
            case "command":
                result |= UInt32(cmdKey)
            case "option":
                result |= UInt32(optionKey)
            case "shift":
                result |= UInt32(shiftKey)
            case "control":
                result |= UInt32(controlKey)
            default:
                break
            }
        }

        guard modifiers != 0 else { return nil }
        return CarbonShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let controllerPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let controller = Unmanaged<QuickBarHotkeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return controller.handleHotKeyEvent(event)
            },
            1,
            &eventType,
            controllerPointer,
            &eventHandler
        )
    }

    private func observeWorkspaceLifecycle() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        Publishers.Merge(
            notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification),
            notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.refreshRegistrationIfNeeded()
        }
        .store(in: &workspaceCancellables)
    }

    private func refreshRegistrationIfNeeded() {
        guard let currentConfiguration else { return }
        register(configuration: currentConfiguration)
    }

    private func shouldOwnHotKey() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let runningApplications = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }

        guard runningApplications.count > 1 else {
            return true
        }

        let preferredApplication = runningApplications.max { lhs, rhs in
            let leftLaunchDate = lhs.launchDate ?? .distantPast
            let rightLaunchDate = rhs.launchDate ?? .distantPast
            if leftLaunchDate != rightLaunchDate {
                return leftLaunchDate < rightLaunchDate
            }
            return lhs.processIdentifier < rhs.processIdentifier
        }

        return preferredApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        guard hotKeyID.signature == Self.hotKeySignature,
              hotKeyID.id == Self.hotKeyIdentifier
        else {
            return OSStatus(eventNotHandledErr)
        }

        onPress?()
        return noErr
    }
}
