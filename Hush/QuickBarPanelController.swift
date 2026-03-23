import AppKit
import Combine
import Darwin
import OSLog
import SwiftUI

@MainActor
final class QuickBarPanelController: NSObject, NSWindowDelegate {
    private static let logger = Logger(subsystem: "com.hush.app", category: "QuickBar")

    private enum Layout {
        static let width: CGFloat = 708
        static let compactHeight: CGFloat = 176
        static let expandedHeight: CGFloat = 552
        static let panelIdentifier = NSUserInterfaceItemIdentifier("com.dundunha.Hush.quickBarPanel")
        static let lockFilename = "com.dundunha.Hush.quickbar.lock"
    }

    private final class QuickBarPanelWindow: NSPanel {
        var onCloseCommand: (() -> Void)?

        override var canBecomeKey: Bool {
            true
        }

        override var canBecomeMain: Bool {
            false
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.type == .keyDown,
                  event.charactersIgnoringModifiers?.lowercased() == "w"
            else {
                return super.performKeyEquivalent(with: event)
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == [.option] || modifiers == [.command] || modifiers == [.command, .option] {
                onCloseCommand?()
                return true
            }

            return super.performKeyEquivalent(with: event)
        }

        override func keyDown(with event: NSEvent) {
            guard event.charactersIgnoringModifiers?.lowercased() == "w" else {
                super.keyDown(with: event)
                return
            }

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == [.option] || modifiers == [.command] || modifiers == [.command, .option] {
                onCloseCommand?()
                return
            }

            super.keyDown(with: event)
        }
    }

    private weak var container: AppContainer?
    private var panel: QuickBarPanelWindow?
    private var cancellables = Set<AnyCancellable>()
    private var presentationLockFileDescriptor: CInt = -1

    func bind(container: AppContainer) {
        self.container = container
        cancellables.removeAll()
        Self.logger.debug(
            "Bind quick bar controller pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) bundle=\(Bundle.main.bundleURL.path, privacy: .public)"
        )

        container.$showQuickBar
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                self?.syncVisibility(isVisible: isVisible)
            }
            .store(in: &cancellables)

        container.$quickBarState
            .map(\.isExpanded)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePanelFrame(animated: true)
            }
            .store(in: &cancellables)

        syncVisibility(isVisible: container.showQuickBar)
    }

    func windowShouldClose(_: NSWindow) -> Bool {
        Self.logger.debug("Window close requested for Quick Bar")
        container?.closeQuickBar()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow == panel
        else {
            return
        }

        Self.logger.debug("Quick Bar panel closed")
        releasePresentationLock(reason: "windowWillClose")
        panel = nil
    }

    private func syncVisibility(isVisible: Bool) {
        if isVisible {
            showPanel()
        } else {
            hidePanel()
        }
    }

    private func showPanel() {
        guard let container else { return }
        guard acquirePresentationLock() else {
            Self.logger.notice(
                "Skipped Quick Bar presentation because another process owns the presentation lock"
            )
            container.statusMessage = "Quick Bar is already open in another Hush instance"
            container.closeQuickBar()
            return
        }

        let panel = makePanelIfNeeded()
        retireDuplicatePanels(excluding: panel)
        panel.contentViewController = NSHostingController(
            rootView: QuickBarPanelView()
                .environmentObject(container)
        )
        updatePanelFrame(animated: false)
        Self.logger.debug(
            "Presenting Quick Bar visible=\(panel.isVisible, privacy: .public) expanded=\(container.quickBarState.isExpanded, privacy: .public) windowCount=\(NSApp.windows.count, privacy: .public)"
        )
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func hidePanel() {
        guard let panel else { return }
        if panel.isVisible {
            Self.logger.debug("Hiding Quick Bar")
            panel.orderOut(nil)
        }
        releasePresentationLock(reason: "hidePanel")
    }

    private func updatePanelFrame(animated: Bool) {
        guard let panel else { return }

        let targetHeight = (container?.quickBarState.isExpanded ?? false)
            ? Layout.expandedHeight
            : Layout.compactHeight
        let targetSize = NSSize(width: Layout.width, height: targetHeight)

        var nextFrame = panel.frame
        if !panel.isVisible {
            nextFrame.size = targetSize
            if let origin = centeredOrigin(for: targetSize, on: panel.screen ?? NSScreen.main) {
                nextFrame.origin = origin
            }
            panel.setFrame(nextFrame, display: false)
            return
        }

        let maxY = nextFrame.maxY
        nextFrame.size = targetSize
        nextFrame.origin.y = maxY - targetHeight

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                panel.animator().setFrame(nextFrame, display: true)
            }
        } else {
            panel.setFrame(nextFrame, display: true)
        }
    }

    private func makePanelIfNeeded() -> QuickBarPanelWindow {
        if let panel {
            return panel
        }

        let initialSize = NSSize(width: Layout.width, height: Layout.compactHeight)
        let origin = centeredOrigin(for: initialSize, on: NSScreen.main) ?? .zero
        let frame = NSRect(origin: origin, size: initialSize)

        let panel = QuickBarPanelWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.onCloseCommand = { [weak self] in
            self?.container?.closeQuickBar()
        }
        panel.delegate = self
        panel.identifier = Layout.panelIdentifier
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.tabbingMode = .disallowed
        panel.isExcludedFromWindowsMenu = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        Self.logger.debug("Created Quick Bar panel")
        self.panel = panel
        return panel
    }

    private func centeredOrigin(for size: NSSize, on screen: NSScreen?) -> CGPoint? {
        guard let visibleFrame = screen?.visibleFrame else { return nil }
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.maxY - size.height - 86
        return CGPoint(x: x, y: max(visibleFrame.minY + 40, y))
    }

    private func retireDuplicatePanels(excluding currentPanel: QuickBarPanelWindow) {
        let duplicatePanels = NSApp.windows
            .compactMap { $0 as? NSPanel }
            .filter { $0.identifier == Layout.panelIdentifier && $0 !== currentPanel }

        guard !duplicatePanels.isEmpty else { return }

        Self.logger.warning("Retiring \(duplicatePanels.count, privacy: .public) duplicate Quick Bar panel(s)")

        for duplicate in duplicatePanels {
            if let duplicateWindow = duplicate as? QuickBarPanelWindow {
                duplicateWindow.onCloseCommand = nil
            }
            duplicate.delegate = nil
            duplicate.orderOut(nil)
            duplicate.close()
        }
    }

    private func acquirePresentationLock() -> Bool {
        if presentationLockFileDescriptor >= 0 {
            return true
        }

        let lockPath = Self.lockFilePath
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        guard descriptor >= 0 else {
            Self.logger.error("Failed to open Quick Bar lock file path=\(lockPath, privacy: .public) errno=\(errno, privacy: .public)")
            return true
        }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            presentationLockFileDescriptor = descriptor
            writePresentationLockMetadata(to: descriptor)
            Self.logger.debug(
                "Acquired Quick Bar presentation lock path=\(lockPath, privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public)"
            )
            return true
        }

        let lockError = errno
        _ = close(descriptor)

        if lockError == EWOULDBLOCK {
            return false
        }

        Self.logger.error("Failed to acquire Quick Bar presentation lock errno=\(lockError, privacy: .public)")
        return true
    }

    private func releasePresentationLock(reason: String) {
        guard presentationLockFileDescriptor >= 0 else { return }

        let descriptor = presentationLockFileDescriptor
        presentationLockFileDescriptor = -1
        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
        Self.logger.debug("Released Quick Bar presentation lock reason=\(reason, privacy: .public)")
    }

    private func writePresentationLockMetadata(to descriptor: CInt) {
        let payload = [
            "pid=\(ProcessInfo.processInfo.processIdentifier)",
            "bundle=\(Bundle.main.bundleURL.path)",
            "timestamp=\(Date().timeIntervalSince1970)"
        ].joined(separator: "\n") + "\n"

        _ = ftruncate(descriptor, 0)
        _ = lseek(descriptor, 0, SEEK_SET)
        payload.withCString { cString in
            _ = write(descriptor, cString, strlen(cString))
        }
    }

    private static var lockFilePath: String {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(Layout.lockFilename)
            .path
    }
}
