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

    var body: some View {
        Group {
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

                    ZStack {
                        Rectangle()
                            .fill(showSidebar ? themePalette.sidebarBackground : themePalette.rootBackground)

                        let shape = UnevenRoundedRectangle(
                            topLeadingRadius: rightPaneTopCornerRadius,
                            bottomLeadingRadius: rightPaneBottomCornerRadius,
                            bottomTrailingRadius: 0,
                            topTrailingRadius: 0,
                            style: .continuous
                        )

                        if showSidebar {
                            shape
                                .fill(themePalette.rootBackground)
                                .shadow(
                                    color: themePalette.splitPaneShadow,
                                    radius: HushSpacing.splitPaneShadowRadius,
                                    x: HushSpacing.splitPaneShadowX,
                                    y: 0
                                )
                                .mask(alignment: .leading) {
                                    Rectangle()
                                        .frame(
                                            width: max(rightPaneTopCornerRadius, rightPaneBottomCornerRadius) +
                                                (HushSpacing.splitPaneShadowRadius * 2)
                                        )
                                }
                        }

                        VStack(spacing: 0) {
                            ChatTopBar(showSidebar: $showSidebar)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: HushSpacing.topBarHeight)
                                .background(WindowDragArea())

                            ChatDetailPane()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .background(themePalette.rootBackground)
                        .clipShape(shape)
                        .overlay {
                            if showSidebar {
                                shape
                                    .strokeBorder(themePalette.splitPaneEdgeStroke, lineWidth: 1)
                                    .mask(alignment: .leading) {
                                        Rectangle()
                                            .frame(width: max(rightPaneTopCornerRadius, rightPaneBottomCornerRadius) + 2)
                                    }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
