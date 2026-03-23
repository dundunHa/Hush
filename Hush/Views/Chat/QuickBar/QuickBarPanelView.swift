import SwiftUI

struct QuickBarPanelView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var isOverflowHovered = false
    @State private var isCloseHovered = false
    @Namespace private var glassNamespace

    private var palette: HushThemePalette {
        HushColors.palette(for: container.settings.theme)
    }

    private enum Layout {
        static let shellCornerRadius: CGFloat = 38
        static let outerTopPadding: CGFloat = HushSpacing.xs + 6
        static let outerBottomPadding: CGFloat = HushSpacing.sm + 2
        static let contentHorizontalInset: CGFloat = HushSpacing.sm
        static let headerHorizontalInset: CGFloat = HushSpacing.sm + 2
        static let headerHeight: CGFloat = 28
        static let transcriptTopPadding: CGFloat = HushSpacing.xs
        static let transcriptBottomPadding: CGFloat = HushSpacing.sm + 1
        static let dividerHorizontalInset: CGFloat = HushSpacing.sm + 2
        static let composerTopPadding: CGFloat = HushSpacing.xs + 2
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
        QuickBarComposer(
            glassNamespace: activeGlassNamespace,
            prefersNativeGlass: usesNativeGlass,
            layoutStyle: .compact
        )
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

            QuickBarComposer(
                glassNamespace: activeGlassNamespace,
                prefersNativeGlass: usesNativeGlass,
                layoutStyle: .expanded
            )
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
        ZStack {
            QuickConversationSurface(
                conversationId: container.quickBarState.conversationId,
                messages: container.quickBarState.messages,
                isSending: container.isQuickBarSending,
                generation: container.quickBarState.generation
            )
            .environmentObject(container)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if container.quickBarState.messages.isEmpty {
                transcriptEmptyState
            }
        }
        .padding(.horizontal, Layout.contentHorizontalInset)
        .padding(.top, Layout.transcriptTopPadding)
        .padding(.bottom, Layout.transcriptBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
            .fill(
                LinearGradient(
                    colors: [
                        .clear,
                        palette.quickBarSurfaceStroke.opacity(0.09),
                        palette.quickBarSurfaceStroke.opacity(0.12),
                        palette.quickBarSurfaceStroke.opacity(0.09),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
            .padding(.horizontal, Layout.dividerHorizontalInset)
    }

    private var handle: some View {
        Capsule(style: .continuous)
            .fill(handleColor)
            .frame(width: 90, height: 4)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: HushSpacing.sm) {
            if container.isQuickBarSending {
                Circle()
                    .fill(palette.quickBarButtonFill.opacity(0.88))
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
                    isHovered: isOverflowHovered,
                    registration: QuickBarNativeGlassRegistration(
                        id: .overflowButton,
                        transition: .materialize
                    )
                )
            }
            .menuStyle(.borderlessButton)
            .onHover { isOverflowHovered = $0 }

            Button {
                container.closeQuickBar()
            } label: {
                toolbarOrb(
                    systemName: "xmark",
                    isHovered: isCloseHovered,
                    registration: QuickBarNativeGlassRegistration(
                        id: .closeButton,
                        transition: .materialize
                    )
                )
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .keyboardShortcut("w", modifiers: [.option])
        }
    }

    private var backgroundShell: some View {
        QuickBarLiquidGlassSurface(
            shape: RoundedRectangle(cornerRadius: Layout.shellCornerRadius, style: .continuous),
            baseTint: palette.quickBarSurface,
            highlightTint: palette.quickBarSurfaceStroke,
            shadowColor: palette.splitPaneShadow,
            style: .panelShell
        )
    }

    private var handleColor: Color {
        palette.quickBarSurfaceStroke.opacity(0.22)
    }

    private func toolbarOrb(
        systemName: String,
        isHovered: Bool,
        registration: QuickBarNativeGlassRegistration
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.quickBarControlMuted.opacity(isHovered ? 1 : 0.92))
            .frame(width: 28, height: 28)
            .background {
                QuickBarGlassSurface(
                    shape: Circle(),
                    registration: registration,
                    namespace: activeGlassNamespace,
                    nativeStyle: nativeToolbarOrbStyle(isHovered: isHovered),
                    fallbackBaseTint: palette.quickBarSurface,
                    fallbackHighlightTint: palette.quickBarSurfaceStroke,
                    fallbackShadowColor: palette.splitPaneShadow,
                    fallbackStyle: .toolbarOrb(isHovered: isHovered)
                )
            }
    }

    private var usesNativeGlass: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    private var activeGlassNamespace: Namespace.ID? {
        usesNativeGlass ? glassNamespace : nil
    }

    private func nativeToolbarOrbStyle(isHovered: Bool) -> QuickBarNativeGlassStyle {
        let tint: Color? = if isHovered {
            palette.quickBarSurface.opacity(
                container.settings.theme.usesDarkAppearance ? 0.18 : 0.12
            )
        } else {
            nil
        }

        return QuickBarNativeGlassStyle(
            tint: tint,
            isInteractive: true,
            strokeColor: palette.quickBarSurfaceStroke.opacity(isHovered ? 0.16 : 0.10),
            shadowColor: palette.splitPaneShadow,
            shadowOpacity: 0.01,
            shadowRadius: 2,
            shadowYOffset: 0
        )
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
            .frame(width: 708, height: 176)
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
            .frame(width: 708, height: 552)
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
            .frame(width: 708, height: 552)
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
            .frame(width: 708, height: 176)
            .padding()
    }
#endif
