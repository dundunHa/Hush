import SwiftUI

struct HotScenePoolRepresentable: NSViewControllerRepresentable {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.hushTheme) private var theme

    func makeNSViewController(context _: Context) -> HotScenePoolController {
        HotScenePoolController()
    }

    func updateNSViewController(_ nsViewController: HotScenePoolController, context _: Context) {
        nsViewController.update(container: container, theme: theme)
    }
}
