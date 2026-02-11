import SwiftUI

struct HotScenePoolRepresentable: NSViewControllerRepresentable {
    @EnvironmentObject private var container: AppContainer

    func makeNSViewController(context _: Context) -> HotScenePoolController {
        HotScenePoolController()
    }

    func updateNSViewController(_ nsViewController: HotScenePoolController, context _: Context) {
        nsViewController.update(container: container)
    }
}
