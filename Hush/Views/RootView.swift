import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var showSettings: Bool
    @State private var showSidebar: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Split-color top bar

            SplitTopBar(
                showSidebar: $showSidebar,
                isSettingsMode: showSettings
            )

            // MARK: - Content

            if showSettings {
                SettingsWorkspaceView(showSettings: $showSettings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ConversationSidebarView(
                        showSettings: $showSettings
                    )
                    .frame(width: HushSpacing.sidebarWidth)
                    .frame(width: showSidebar ? HushSpacing.sidebarWidth : 0, alignment: .leading)
                    .clipped()
                    .allowsHitTesting(showSidebar)

                    Divider()
                        .overlay(HushColors.separator)
                        .opacity(showSidebar ? 1 : 0)

                    ChatDetailPane()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(HushColors.rootBackground.ignoresSafeArea())
        .preferredColorScheme(preferredScheme(forTheme: container.settings.theme))
    }

    private func preferredScheme(forTheme theme: AppTheme) -> ColorScheme {
        switch theme {
        case .dark:
            return .dark
        }
    }
}

#if DEBUG

    // MARK: - Previews

    #Preview("RootView — Chat Mode (Empty)") {
        RootView(showSettings: .constant(false))
            .environmentObject(AppContainer.makePreviewContainer())
    }

    #Preview("RootView — Settings Mode") {
        RootView(showSettings: .constant(true))
            .environmentObject(AppContainer.makePreviewContainer())
    }
#endif
