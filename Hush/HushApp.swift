import AppKit
import SwiftUI

@main
struct HushApp: App {
    @NSApplicationDelegateAdaptor(HushAppDelegate.self) private var appDelegate
    @StateObject private var container = AppContainer.bootstrap()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings: Bool = false

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup("Hush") {
            RootView(showSettings: $showSettings)
                .environmentObject(container)
                .frame(minWidth: 980, minHeight: 640)
                .onChange(of: scenePhase) { _, newPhase in
                    container.handleScenePhaseChange(newPhase)
                }
                .background(
                    WindowCloseObserver {
                        appDelegate.mainWindowDidClose()
                    }
                )
                .onAppear {
                    wireAppDelegateCallbacks()
                    #if DEBUG
                        container.runAutomationScenarioIfNeeded()
                    #endif
                }
                .onReceive(NotificationCenter.default.publisher(for: .hushOpenSettings)) { _ in
                    showSettings = true
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Hush") {
                Button("Toggle Quick Bar") {
                    container.toggleQuickBar()
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
            }
        }
    }

    private func wireAppDelegateCallbacks() {
        appDelegate.onActivateWindow = {
            for window in NSApp.windows {
                guard window.level == .normal,
                      window.canBecomeKey
                else { continue }
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        appDelegate.onOpenSettings = {
            showSettings = true
        }
    }
}

// MARK: - WindowCloseObserver

struct WindowCloseObserver: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.observe(window: window)
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    final class Coordinator: NSObject {
        let onClose: () -> Void
        private var observation: Any?

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        func observe(window: NSWindow) {
            observation = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.onClose()
            }
        }

        deinit {
            if let observation {
                NotificationCenter.default.removeObserver(observation)
            }
        }
    }
}
