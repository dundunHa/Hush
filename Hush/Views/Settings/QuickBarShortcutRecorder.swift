import AppKit
import Carbon.HIToolbox
import SwiftUI

struct QuickBarShortcutRecorder: View {
    @Binding var configuration: QuickBarConfiguration
    @Environment(\.hushThemePalette) private var palette
    @State private var isRecording = false

    var body: some View {
        HStack(spacing: HushSpacing.md) {
            Button(action: toggleRecording) {
                HStack(spacing: HushSpacing.sm) {
                    Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                        .font(.system(size: 13, weight: .semibold))

                    Text(isRecording ? "Press shortcut" : configuration.displayString)
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
            }
            .buttonStyle(.bordered)
        }
        .background(
            QuickBarShortcutCaptureBridge(
                isRecording: $isRecording,
                configuration: $configuration
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
        isRecording.toggle()
    }
}

private struct QuickBarShortcutCaptureBridge: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var configuration: QuickBarConfiguration

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isRecording: $isRecording,
            configuration: $configuration
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
            configuration: $configuration
        )
        context.coordinator.syncMonitor()
    }

    static func dismantleNSView(_: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        private var isRecording: Binding<Bool>
        private var configuration: Binding<QuickBarConfiguration>
        private var eventMonitor: Any?

        init(
            isRecording: Binding<Bool>,
            configuration: Binding<QuickBarConfiguration>
        ) {
            self.isRecording = isRecording
            self.configuration = configuration
        }

        deinit {
            removeMonitor()
        }

        func update(
            isRecording: Binding<Bool>,
            configuration: Binding<QuickBarConfiguration>
        ) {
            self.isRecording = isRecording
            self.configuration = configuration
        }

        func syncMonitor() {
            if isRecording.wrappedValue {
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

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard isRecording.wrappedValue else { return event }

            if event.keyCode == UInt16(kVK_Escape) {
                isRecording.wrappedValue = false
                return nil
            }

            guard let recordedConfiguration = QuickBarHotkeyController.configuration(for: event) else {
                NSSound.beep()
                return nil
            }

            configuration.wrappedValue = recordedConfiguration
            isRecording.wrappedValue = false
            return nil
        }
    }
}
