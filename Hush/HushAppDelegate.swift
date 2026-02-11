import AppKit
import SwiftUI

@MainActor
final class HushAppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Dependencies

    let statusBarController = StatusBarController()
    var onActivateWindow: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var isMainWindowVisible = true

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

    // MARK: - Private

    private func activateMainWindow() {
        mainWindowWillOpen()
        onActivateWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
}
