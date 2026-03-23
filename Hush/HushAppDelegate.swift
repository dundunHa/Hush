import AppKit
import Combine
import SwiftUI

@MainActor
final class HushAppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Dependencies

    let statusBarController = StatusBarController()
    let quickBarPanelController = QuickBarPanelController()
    let quickBarHotkeyController = QuickBarHotkeyController()
    var onActivateWindow: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var isMainWindowVisible = true
    private var subscriptions = Set<AnyCancellable>()

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_: Notification) {
        statusBarController.onActivateWindow = { [weak self] in
            self?.activateMainWindow()
        }
        statusBarController.onOpenSettings = { [weak self] in
            self?.activateMainWindow()
            self?.onOpenSettings?()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            activateMainWindow()
        }
        return true
    }

    // MARK: - Window Lifecycle

    func mainWindowDidClose() {
        isMainWindowVisible = false
        statusBarController.show()
        NSApp.setActivationPolicy(.accessory)
    }

    func mainWindowWillOpen() {
        guard !isMainWindowVisible else { return }
        isMainWindowVisible = true
        NSApp.setActivationPolicy(.regular)
        statusBarController.hide()
    }

    func configureQuickBar(with container: AppContainer) {
        quickBarPanelController.bind(container: container)
        quickBarHotkeyController.bind(container: container) { [weak self] in
            self?.handleQuickBarHotkey(container: container)
        }

        subscriptions.removeAll()
        NotificationCenter.default.publisher(for: .hushActivateMainWindow)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.activateMainWindow()
            }
            .store(in: &subscriptions)
    }

    // MARK: - Private

    private func activateMainWindow() {
        mainWindowWillOpen()
        onActivateWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handleQuickBarHotkey(container: AppContainer) {
        if !container.showQuickBar {
            NSApp.activate(ignoringOtherApps: true)
        }
        container.toggleQuickBar()
    }
}
