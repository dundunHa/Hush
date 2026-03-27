import SwiftUI

struct QuickBarPanelView: View {
    @EnvironmentObject private var container: AppContainer

    private var palette: HushThemePalette {
        HushColors.palette(for: container.settings.theme)
    }

    private enum Layout {
        static let shellCornerRadius: CGFloat = 40
        static let transcriptCornerRadius: CGFloat = 28
        static let outerTopPadding: CGFloat = HushSpacing.xs + 2
        static let outerBottomPadding: CGFloat = HushSpacing.xs + 2
        static let contentHorizontalInset: CGFloat = HushSpacing.sm + 2
        static let headerHorizontalInset: CGFloat = HushSpacing.md
        static let headerHeight: CGFloat = 22
        static let transcriptTopPadding: CGFloat = HushSpacing.xs
        static let transcriptBottomPadding: CGFloat = HushSpacing.xs
        static let dividerHorizontalInset: CGFloat = HushSpacing.sm
        static let composerTopPadding: CGFloat = 0
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
        handle
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
        .padding(.horizontal, HushSpacing.xs)
        .padding(.top, HushSpacing.xs)
        .padding(.horizontal, Layout.contentHorizontalInset)
        .padding(.top, Layout.transcriptTopPadding)
        .padding(.bottom, Layout.transcriptBottomPadding + 1)
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
            .fill(palette.quickBarSurfaceStroke.opacity(container.settings.theme.usesDarkAppearance ? 0.05 : 0.08))
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
            .frame(width: QuickBarPanelReleaseMetrics.width, height: QuickBarPanelReleaseMetrics.compactHeight)
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
            .frame(width: QuickBarPanelReleaseMetrics.width, height: QuickBarPanelReleaseMetrics.expandedHeight)
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
            .frame(width: QuickBarPanelReleaseMetrics.width, height: QuickBarPanelReleaseMetrics.expandedHeight)
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
            .frame(width: QuickBarPanelReleaseMetrics.width, height: QuickBarPanelReleaseMetrics.compactHeight)
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
            .frame(width: QuickBarPanelReleaseMetrics.width, height: QuickBarPanelReleaseMetrics.compactHeight)
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
            .frame(width: QuickBarPanelReleaseMetrics.width, height: QuickBarPanelReleaseMetrics.expandedHeight)
            .padding()
    }
#endif
