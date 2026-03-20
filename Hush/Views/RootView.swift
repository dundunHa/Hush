import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var showSettings: Bool
    @State private var showSidebar: Bool = true

    private var themePalette: HushThemePalette {
        HushColors.palette(for: container.settings.theme)
    }

    private var rightPaneTopCornerRadius: CGFloat {
        showSidebar ? min(HushSpacing.splitPaneCornerRadius, HushSpacing.topBarHeight / 2) : 0
    }

    private var rightPaneBottomCornerRadius: CGFloat {
        showSidebar ? HushSpacing.splitPaneCornerRadius : 0
    }

    private var sidebarRevealWidth: CGFloat {
        showSidebar ? max(rightPaneTopCornerRadius, rightPaneBottomCornerRadius) + 1 : 0
    }

    var body: some View {
        Group {
            if showSettings {
                SettingsWorkspaceView(showSettings: $showSettings)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    ConversationSidebarView(
                        showSettings: $showSettings,
                        showsMaterialBackground: false
                    )
                    .frame(width: HushSpacing.sidebarWidth)
                    .frame(width: showSidebar ? HushSpacing.sidebarWidth : 0, alignment: .leading)
                    .clipped()
                    .allowsHitTesting(showSidebar)

                    let shape = UnevenRoundedRectangle(
                        topLeadingRadius: rightPaneTopCornerRadius,
                        bottomLeadingRadius: rightPaneBottomCornerRadius,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )

                    VStack(spacing: 0) {
                        ChatTopBar(showSidebar: $showSidebar)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: HushSpacing.topBarHeight)
                            .background {
                                WorkspaceChromeBackground(
                                    theme: container.settings.theme,
                                    palette: themePalette
                                )
                                WindowDragArea()
                            }

                        ChatDetailPane()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(themePalette.rootBackground)
                    .clipShape(shape)
                    .overlay {
                        if showSidebar {
                            LeadingPaneBorder(
                                topRadius: rightPaneTopCornerRadius,
                                bottomRadius: rightPaneBottomCornerRadius,
                                color: themePalette.splitPaneEdgeStroke
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(alignment: .leading) {
                    SplitPaneSidebarSurface(
                        theme: container.settings.theme,
                        palette: themePalette,
                        sidebarWidth: showSidebar ? HushSpacing.sidebarWidth : 0,
                        revealWidth: sidebarRevealWidth
                    )
                }
                .overlay(alignment: .topLeading) {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            showSidebar.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.borderless)
                    .help("Toggle Sidebar")
                    .padding(.leading, HushSpacing.trafficLightInset)
                    .frame(height: 28)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .font(HushTypography.body)
        .background(themePalette.rootBackground.ignoresSafeArea())
        .environment(\.hushTheme, container.settings.theme)
        .environment(\.hushThemePalette, themePalette)
        .preferredColorScheme(preferredScheme(forTheme: container.settings.theme))
    }

    private func preferredScheme(forTheme theme: AppTheme) -> ColorScheme {
        theme.usesDarkAppearance ? .dark : .light
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
