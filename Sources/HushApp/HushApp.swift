import SwiftUI

@main
struct HushApp: App {
    @StateObject private var container = AppContainer.bootstrap()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup("Hush") {
            RootView()
                .environmentObject(container)
                .frame(minWidth: 980, minHeight: 640)
                .onChange(of: scenePhase) { _, newPhase in
                    container.handleScenePhaseChange(newPhase)
                }
        }
        .commands {
            CommandMenu("Hush") {
                Button("Toggle Quick Bar") {
                    container.toggleQuickBar()
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
            }
        }
    }
}
