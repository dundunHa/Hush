import SwiftUI

struct QuickBarPanelView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var isOverflowHovered = false
    @State private var isCloseHovered = false

    private var palette: HushThemePalette {
        HushColors.palette(for: container.settings.theme)
    }

    private enum Layout {
        static let shellCornerRadius: CGFloat = 40
        static let transcriptCornerRadius: CGFloat = 28
        static let outerTopPadding: CGFloat = HushSpacing.sm + 2
        static let outerBottomPadding: CGFloat = HushSpacing.sm + 4
        static let contentHorizontalInset: CGFloat = HushSpacing.sm + 2
        static let headerHorizontalInset: CGFloat = HushSpacing.md
        static let headerHeight: CGFloat = 32
        static let transcriptTopPadding: CGFloat = HushSpacing.sm
        static let transcriptBottomPadding: CGFloat = HushSpacing.sm + 2
        static let dividerHorizontalInset: CGFloat = HushSpacing.md
        static let composerTopPadding: CGFloat = HushSpacing.sm
        static let toolbarButtonSize: CGFloat = 34
    }

    var body: some View {
        Group {
            if container.quickBarState.isExpanded {
                expandedBody
            } else {
                compactBody
            }
        }
        .preferredColorScheme(preferredScheme(for: container.settings.theme))
    }

    private var compactBody: some View {
        QuickBarComposer(layoutStyle: .compact)
            .environmentObject(container)
            .padding(.horizontal, HushSpacing.sm)
            .padding(.vertical, HushSpacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            expandedHeader
            transcriptRegion
            composerDivider

            QuickBarComposer(layoutStyle: .expanded)
                .environmentObject(container)
                .padding(.horizontal, Layout.contentHorizontalInset)
                .padding(.top, Layout.composerTopPadding)
        }
        .padding(.top, Layout.outerTopPadding)
        .padding(.bottom, Layout.outerBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(backgroundShell)
    }

    private var expandedHeader: some View {
        ZStack(alignment: .trailing) {
            handle
            controls
        }
        .padding(.horizontal, Layout.headerHorizontalInset)
        .frame(height: Layout.headerHeight)
    }

    private var transcriptRegion: some View {
        QuickConversationSurface(
            conversationId: container.quickBarState.conversationId,
            messages: container.quickBarState.messages,
            isSending: container.isQuickBarSending,
            generation: container.quickBarState.generation
        )
        .environmentObject(container)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(HushSpacing.xs)
        .padding(.horizontal, Layout.contentHorizontalInset)
        .padding(.top, Layout.transcriptTopPadding)
        .padding(.bottom, Layout.transcriptBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(transcriptShell)
        .clipShape(RoundedRectangle(cornerRadius: Layout.transcriptCornerRadius, style: .continuous))
        .overlay {
            if container.quickBarState.messages.isEmpty {
                transcriptEmptyState
            }
        }
    }

    private var transcriptEmptyState: some View {
        VStack(spacing: HushSpacing.xs) {
            Text("Quick chat")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.quickBarPrimaryText.opacity(0.88))

            Text("Responses will appear here after you send a message.")
                .font(HushTypography.caption)
                .foregroundStyle(palette.quickBarSecondaryText.opacity(0.84))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, HushSpacing.xl)
        .allowsHitTesting(false)
    }

    private var composerDivider: some View {
        Rectangle()
            .fill(palette.quickBarSurfaceStroke.opacity(container.settings.theme.usesDarkAppearance ? 0.12 : 0.18))
            .frame(height: 0.5)
            .padding(.horizontal, Layout.dividerHorizontalInset)
    }

    private var handle: some View {
        Capsule(style: .continuous)
            .fill(handleColor)
            .frame(width: 72, height: 3)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: HushSpacing.sm) {
            if container.isQuickBarSending {
                Circle()
                    .fill(palette.quickBarButtonFill.opacity(0.90))
                    .frame(width: 6, height: 6)
            }

            Menu {
                Button("New Chat") {
                    container.resetQuickBarConversation()
                }
                .disabled(container.isQuickBarSending)

                if !container.quickBarState.messages.isEmpty {
                    Button("Open in Main Chat") {
                        container.continueQuickBarInMainChat()
                    }
                    .disabled(container.isQuickBarSending)
                }
            } label: {
                toolbarOrb(
                    systemName: "ellipsis",
                    isHovered: isOverflowHovered
                )
            }
            .menuStyle(.borderlessButton)
            .help("Quick Bar actions")
            .onHover { isOverflowHovered = $0 }

            Button {
                container.closeQuickBar()
            } label: {
                toolbarOrb(
                    systemName: "xmark",
                    isHovered: isCloseHovered
                )
            }
            .buttonStyle(QuickBarScaleButtonStyle())
            .help("Close Quick Bar")
            .onHover { isCloseHovered = $0 }
            .keyboardShortcut("w", modifiers: [.option])
        }
    }

    private var backgroundShell: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.shellCornerRadius, style: .continuous)

        return ZStack {
            QuickBarMinimalSurface(
                shape: shape,
                fill: palette.quickBarSurface.opacity(
                    container.settings.theme.usesDarkAppearance ? 0.95 : 0.985
                ),
                stroke: palette.quickBarSurfaceStroke.opacity(
                    container.settings.theme.usesDarkAppearance ? 0.24 : 0.42
                ),
                shadowColor: palette.splitPaneShadow,
                shadowOpacity: container.settings.theme.usesDarkAppearance ? 0.20 : 0.10,
                shadowRadius: 12,
                shadowYOffset: 2
            )

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(container.settings.theme.usesDarkAppearance ? 0.06 : 0.22),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .clipShape(shape)
        }
    }

    private var transcriptShell: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.transcriptCornerRadius, style: .continuous)

        return ZStack {
            QuickBarMinimalSurface(
                shape: shape,
                fill: palette.quickBarSurface.opacity(
                    container.settings.theme.usesDarkAppearance ? 0.34 : 0.70
                ),
                stroke: palette.quickBarSurfaceStroke.opacity(
                    container.settings.theme.usesDarkAppearance ? 0.14 : 0.24
                ),
                shadowColor: palette.splitPaneShadow,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowYOffset: 0
            )

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(container.settings.theme.usesDarkAppearance ? 0.03 : 0.16),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(shape)
        }
    }

    private var handleColor: Color {
        palette.quickBarSurfaceStroke.opacity(0.20)
    }

    private func toolbarOrb(
        systemName: String,
        isHovered: Bool
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.quickBarControlMuted.opacity(isHovered ? 1 : 0.88))
            .frame(width: Layout.toolbarButtonSize, height: Layout.toolbarButtonSize)
            .background {
                QuickBarMinimalSurface(
                    shape: Circle(),
                    fill: palette.quickBarControlFill.opacity(
                        container.settings.theme.usesDarkAppearance
                            ? (isHovered ? 0.24 : 0.10)
                            : (isHovered ? 0.34 : 0.14)
                    ),
                    stroke: palette.quickBarSurfaceStroke.opacity(
                        container.settings.theme.usesDarkAppearance
                            ? (isHovered ? 0.18 : 0.08)
                            : (isHovered ? 0.26 : 0.14)
                    ),
                    shadowColor: palette.splitPaneShadow,
                    shadowOpacity: isHovered ? 0.08 : 0.03,
                    shadowRadius: 4,
                    shadowYOffset: 1
                )
            }
    }

    private func preferredScheme(for theme: AppTheme) -> ColorScheme {
        theme.usesDarkAppearance ? .dark : .light
    }
}

#if DEBUG
    #Preview("QuickBar Panel — Compact") {
        QuickBarPanelView()
            .environmentObject(
                AppContainer.makeQuickBarPreviewContainer(
                    messages: [],
                    draft: "",
                    isExpanded: false
                )
            )
            .frame(width: 708, height: 196)
            .padding()
    }

    #Preview("QuickBar Panel — Expanded") {
        QuickBarPanelView()
            .environmentObject(
                AppContainer.makeQuickBarPreviewContainer(
                    messages: PreviewFixtures.sampleConversation,
                    draft: "",
                    isExpanded: true
                )
            )
            .frame(width: 708, height: 584)
            .padding()
    }

    #Preview("QuickBar Panel — Streaming") {
        QuickBarPanelView()
            .environmentObject(
                AppContainer.makeQuickBarPreviewContainer(
                    messages: [PreviewFixtures.userMessage(content: "Summarize the latest design changes.")],
                    draft: "",
                    isExpanded: true,
                    isSending: true
                )
            )
            .frame(width: 708, height: 584)
            .padding()
    }

    #Preview("QuickBar Panel — No Provider") {
        QuickBarPanelView()
            .environmentObject(
                AppContainer.makeQuickBarPreviewContainer(
                    messages: [],
                    draft: "",
                    isExpanded: false,
                    hasConfiguredProvider: false
                )
            )
            .frame(width: 708, height: 196)
            .padding()
    }

    #Preview("QuickBar Panel — Light Theme") {
        QuickBarPanelView()
            .environmentObject(
                AppContainer.makeQuickBarPreviewContainer(
                    theme: .lightGlass,
                    messages: [],
                    draft: "",
                    isExpanded: false
                )
            )
            .frame(width: 708, height: 196)
            .padding()
    }

    #Preview("QuickBar Panel — Ivory Theme") {
        QuickBarPanelView()
            .environmentObject(
                AppContainer.makeQuickBarPreviewContainer(
                    theme: .ivoryGlass,
                    messages: PreviewFixtures.sampleConversation,
                    draft: "",
                    isExpanded: true
                )
            )
            .frame(width: 708, height: 584)
            .padding()
    }
#endif
