import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var showSettings: Bool
    @State private var showSidebar: Bool = true

    private var rightPaneCornerRadius: CGFloat {
        showSidebar ? HushSpacing.splitPaneCornerRadius : 0
    }

    var body: some View {
        Group {
            if showSettings {
                SettingsWorkspaceView(showSettings: $showSettings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // MARK: - Split-color top bar

                    SplitTopBar(
                        showSidebar: $showSidebar,
                        isSettingsMode: false
                    )

                    // MARK: - Content

                    HStack(spacing: 0) {
                        ConversationSidebarView(
                            showSettings: $showSettings
                        )
                        .frame(width: HushSpacing.sidebarWidth)
                        .frame(width: showSidebar ? HushSpacing.sidebarWidth : 0, alignment: .leading)
                        .clipped()
                        .allowsHitTesting(showSidebar)

                        ZStack {
                            Rectangle()
                                .fill(showSidebar ? HushColors.sidebarBackground : HushColors.rootBackground)

                            let shape = UnevenRoundedRectangle(
                                topLeadingRadius: 0,
                                bottomLeadingRadius: rightPaneCornerRadius,
                                bottomTrailingRadius: 0,
                                topTrailingRadius: 0,
                                style: .continuous
                            )

                            ChatDetailPane()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(HushColors.rootBackground)
                                .clipShape(shape)
                                .overlay {
                                    if showSidebar {
                                        shape
                                            .strokeBorder(HushColors.splitPaneEdgeStroke, lineWidth: 1)
                                            .mask(
                                                ZStack(alignment: .topLeading) {
                                                    Rectangle()
                                                        .frame(width: 2)

                                                    Rectangle()
                                                        .frame(width: rightPaneCornerRadius + 2)
                                                        .padding(.top, 1)
                                                }
                                            )
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(HushColors.rootBackground.ignoresSafeArea())
        .environment(\.hushTheme, container.settings.theme)
        .preferredColorScheme(preferredScheme(forTheme: container.settings.theme))
    }

    private func preferredScheme(forTheme theme: AppTheme) -> ColorScheme {
        switch theme {
        case .dark:
            return .dark
        case .light, .readPaper:
            return .light
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
