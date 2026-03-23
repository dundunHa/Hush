import AppKit
import Carbon.HIToolbox
import SwiftUI

struct QuickBarShortcutRecorder: View {
    @Binding var configuration: QuickBarConfiguration
    @Environment(\.hushThemePalette) private var palette
    @State private var isRecording = false
    @State private var recordingPrompt = QuickBarShortcutRecordingPrompt.waiting

    var body: some View {
        VStack(alignment: .leading, spacing: HushSpacing.xs) {
            HStack(spacing: HushSpacing.md) {
                Button(action: toggleRecording) {
                    HStack(spacing: HushSpacing.sm) {
                        Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                            .font(.system(size: 13, weight: .semibold))

                        Text(isRecording ? recordingPrompt.displayText : configuration.displayString)
                            .font(HushTypography.scaled(14, weight: .semibold))
                    }
                    .foregroundStyle(recorderForeground)
                    .frame(minWidth: 180)
                    .padding(.horizontal, HushSpacing.md)
                    .padding(.vertical, HushSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                            .fill(recorderBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                                    .stroke(recorderStroke, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                Button("Reset to \(QuickBarConfiguration.standard.displayString)") {
                    configuration = .standard
                    isRecording = false
                    recordingPrompt = .waiting
                }
                .buttonStyle(.bordered)
            }

            if isRecording {
                Text(recordingPrompt.hintText)
                    .font(HushTypography.caption)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .background(
            QuickBarShortcutCaptureBridge(
                isRecording: $isRecording,
                configuration: $configuration,
                recordingPrompt: $recordingPrompt
            )
            .frame(width: 0, height: 0)
        )
    }

    private var recorderBackground: Color {
        isRecording ? palette.primaryActionBackground : palette.softFillStrong
    }

    private var recorderForeground: Color {
        isRecording ? palette.primaryActionForeground : palette.primaryText
    }

    private var recorderStroke: Color {
        isRecording ? palette.accentMutedStroke : palette.subtleStroke
    }

    private func toggleRecording() {
        if !isRecording {
            recordingPrompt = .waiting
        }
        isRecording.toggle()
    }
}

struct QuickBarShortcutRecordingPrompt: Equatable {
    static let waiting = QuickBarShortcutRecordingPrompt(
        displayText: "Press shortcut",
        hintText: "Press a key while holding at least one modifier."
    )

    var displayText: String
    var hintText: String
}

enum QuickBarShortcutRecordingAction: Equatable {
    case none
    case beep
    case cancel
    case record(QuickBarConfiguration)
}

struct QuickBarShortcutRecordingSession {
    private static let releaseHintText = "Release to save."
    private static let partialShortcutHintText = "Press a key to complete the shortcut."
    private static let invalidShortcutHintText = "Use at least one modifier with a letter, digit, or Space."

    private var pendingKeyCode: UInt16?
    private var pendingConfiguration: QuickBarConfiguration?
    private(set) var prompt = QuickBarShortcutRecordingPrompt.waiting

    mutating func reset() {
        pendingKeyCode = nil
        pendingConfiguration = nil
        prompt = .waiting
    }

    mutating func handleFlagsChanged(modifierFlags: NSEvent.ModifierFlags) {
        guard pendingKeyCode == nil else { return }

        let normalizedFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        let prefix = Self.modifierPrefix(for: normalizedFlags)
        guard !prefix.isEmpty else {
            prompt = .waiting
            return
        }

        prompt = QuickBarShortcutRecordingPrompt(
            displayText: "\(prefix)...",
            hintText: Self.partialShortcutHintText
        )
    }

    mutating func handleKeyDown(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool = false
    ) -> QuickBarShortcutRecordingAction {
        if keyCode == UInt16(kVK_Escape) {
            reset()
            return .cancel
        }

        guard !isRepeat, pendingKeyCode == nil else {
            return .none
        }

        guard let recordedConfiguration = QuickBarHotkeyController.configuration(
            forKeyCode: keyCode,
            modifierFlags: modifierFlags
        ) else {
            prompt.hintText = Self.invalidShortcutHintText
            return .beep
        }

        pendingKeyCode = keyCode
        pendingConfiguration = recordedConfiguration
        prompt = QuickBarShortcutRecordingPrompt(
            displayText: recordedConfiguration.displayString,
            hintText: Self.releaseHintText
        )
        return .none
    }

    mutating func handleKeyUp(keyCode: UInt16) -> QuickBarShortcutRecordingAction {
        guard keyCode == pendingKeyCode, let pendingConfiguration else {
            return .none
        }

        reset()
        return .record(pendingConfiguration)
    }

    private static func modifierPrefix(for modifierFlags: NSEvent.ModifierFlags) -> String {
        QuickBarConfiguration.supportedModifiers
            .filter { modifier in
                switch modifier {
                case "command":
                    return modifierFlags.contains(.command)
                case "option":
                    return modifierFlags.contains(.option)
                case "shift":
                    return modifierFlags.contains(.shift)
                case "control":
                    return modifierFlags.contains(.control)
                default:
                    return false
                }
            }
            .compactMap(QuickBarConfiguration.modifierSymbol(for:))
            .joined()
    }
}

private struct QuickBarShortcutCaptureBridge: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var configuration: QuickBarConfiguration
    @Binding var recordingPrompt: QuickBarShortcutRecordingPrompt

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isRecording: $isRecording,
            configuration: $configuration,
            recordingPrompt: $recordingPrompt
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.syncMonitor()
        return view
    }

    func updateNSView(_: NSView, context: Context) {
        context.coordinator.update(
            isRecording: $isRecording,
            configuration: $configuration,
            recordingPrompt: $recordingPrompt
        )
        context.coordinator.syncMonitor()
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        private var isRecording: Binding<Bool>
        private var configuration: Binding<QuickBarConfiguration>
        private var recordingPrompt: Binding<QuickBarShortcutRecordingPrompt>
        private var eventMonitor: Any?
        private var recordingSession = QuickBarShortcutRecordingSession()
        private var wasRecording = false

        init(
            isRecording: Binding<Bool>,
            configuration: Binding<QuickBarConfiguration>,
            recordingPrompt: Binding<QuickBarShortcutRecordingPrompt>
        ) {
            self.isRecording = isRecording
            self.configuration = configuration
            self.recordingPrompt = recordingPrompt
        }

        deinit {
            removeMonitor()
        }

        func update(
            isRecording: Binding<Bool>,
            configuration: Binding<QuickBarConfiguration>,
            recordingPrompt: Binding<QuickBarShortcutRecordingPrompt>
        ) {
            self.isRecording = isRecording
            self.configuration = configuration
            self.recordingPrompt = recordingPrompt
        }

        func syncMonitor() {
            let isRecordingNow = isRecording.wrappedValue
            if isRecordingNow != wasRecording {
                recordingSession.reset()
                recordingPrompt.wrappedValue = recordingSession.prompt
                wasRecording = isRecordingNow
            }

            if isRecordingNow {
                installMonitorIfNeeded()
            } else {
                removeMonitor()
            }
        }

        func removeMonitor() {
            guard let eventMonitor else { return }
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        private func installMonitorIfNeeded() {
            guard eventMonitor == nil else { return }

            eventMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.flagsChanged, .keyDown, .keyUp]
            ) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isRecording.wrappedValue else { return event }

            let action: QuickBarShortcutRecordingAction
            switch event.type {
            case .flagsChanged:
                recordingSession.handleFlagsChanged(modifierFlags: event.modifierFlags)
                action = .none
            case .keyDown:
                action = recordingSession.handleKeyDown(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags,
                    isRepeat: event.isARepeat
                )
            case .keyUp:
                action = recordingSession.handleKeyUp(keyCode: event.keyCode)
            default:
                return event
            }

            recordingPrompt.wrappedValue = recordingSession.prompt

            switch action {
            case .none:
                return nil
            case .beep:
                NSSound.beep()
                return nil
            case .cancel:
                recordingSession.reset()
                recordingPrompt.wrappedValue = recordingSession.prompt
                isRecording.wrappedValue = false
                return nil
            case let .record(recordedConfiguration):
                recordingSession.reset()
                recordingPrompt.wrappedValue = recordingSession.prompt
                configuration.wrappedValue = recordedConfiguration
                isRecording.wrappedValue = false
                return nil
            }
        }
    }
}
