import AppKit

@MainActor
final class StatusBarController {
    // MARK: - Callbacks

    var onActivateWindow: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    // MARK: - Private

    private var statusItem: NSStatusItem?

    // MARK: - Public Interface

    func show() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "bubble.left.fill",
                accessibilityDescription: "Hush"
            )
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()

        let activateItem = NSMenuItem(
            title: "Activate Main Window",
            action: #selector(activateWindow),
            keyEquivalent: ""
        )
        activateItem.target = self

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self

        menu.addItem(activateItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Hush",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        item.menu = menu
        statusItem = item
    }

    func hide() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    // MARK: - Actions

    @objc private func activateWindow() {
        onActivateWindow?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}
