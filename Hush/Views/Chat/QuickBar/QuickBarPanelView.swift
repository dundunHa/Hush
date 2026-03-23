import SwiftUI

struct QuickBarPanelView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var isOverflowHovered = false
    @State private var isCloseHovered = false
    @Namespace private var glassNamespace

    private var palette: HushThemePalette {
        HushColors.palette(for: container.settings.theme)
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
            prefersNativeGlass: usesNativeGlass
        )
        .environmentObject(container)
        .padding(.horizontal, HushSpacing.sm)
        .padding(.vertical, HushSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var expandedBody: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: HushSpacing.md) {
                handle

                QuickConversationSurface(
                    conversationId: container.quickBarState.conversationId,
                    messages: container.quickBarState.messages,
                    isSending: container.isQuickBarSending,
                    generation: container.quickBarState.generation
                )
                .environmentObject(container)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(transcriptSurface)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

                QuickBarComposer(
                    glassNamespace: activeGlassNamespace,
                    prefersNativeGlass: usesNativeGlass
                )
                .environmentObject(container)
            }
            .padding(.horizontal, HushSpacing.lg + 2)
            .padding(.top, HushSpacing.sm + 2)
            .padding(.bottom, HushSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            controls
                .padding(.top, HushSpacing.md)
                .padding(.trailing, HushSpacing.md)
        }
        .background(backgroundShell)
    }

    private var handle: some View {
        Capsule(style: .continuous)
            .fill(handleColor)
            .frame(width: 132, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: HushSpacing.sm) {
            if container.isQuickBarSending {
                Circle()
                    .fill(palette.quickBarControlForeground.opacity(0.88))
                    .frame(width: 7, height: 7)
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

    private var transcriptSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        let topOpacity = container.settings.theme.usesDarkAppearance ? 0.72 : 0.62
        let bottomOpacity = container.settings.theme.usesDarkAppearance ? 0.64 : 0.56
        let highlightOpacity = container.settings.theme.usesDarkAppearance ? 0.08 : 0.06
        let strokeOpacity = container.settings.theme.usesDarkAppearance ? 0.44 : 0.36

        return shape
            .fill(
                LinearGradient(
                    colors: [
                        palette.quickBarSurface.opacity(topOpacity),
                        palette.quickBarSurface.opacity(bottomOpacity)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.quickBarSurfaceStroke.opacity(highlightOpacity),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                shape
                    .stroke(palette.quickBarSurfaceStroke.opacity(strokeOpacity), lineWidth: 0.5)
            )
    }

    private var backgroundShell: some View {
        QuickBarLiquidGlassSurface(
            shape: RoundedRectangle(cornerRadius: 38, style: .continuous),
            baseTint: palette.quickBarSurface,
            highlightTint: palette.quickBarSurfaceStroke,
            shadowColor: palette.splitPaneShadow,
            style: .panelShell
        )
    }

    private var handleColor: Color {
        palette.quickBarSurfaceStroke.opacity(0.68)
    }

    private func toolbarOrb(
        systemName: String,
        isHovered: Bool,
        registration: QuickBarNativeGlassRegistration
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.quickBarControlMuted)
            .frame(width: 30, height: 30)
            .background {
                QuickBarGlassSurface(
                    shape: Circle(),
                    registration: registration,
                    namespace: activeGlassNamespace,
                    nativeStyle: nativeToolbarOrbStyle(isHovered: isHovered),
                    fallbackBaseTint: isHovered ? palette.quickBarControlFillHover : palette.quickBarControlFill,
                    fallbackHighlightTint: palette.quickBarSurfaceStroke,
                    fallbackShadowColor: palette.splitPaneShadow,
                    fallbackStyle: .control(isHovered: isHovered)
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
            palette.quickBarControlFillHover.opacity(
                container.settings.theme.usesDarkAppearance ? 0.22 : 0.12
            )
        } else {
            nil
        }

        return QuickBarNativeGlassStyle(
            tint: tint,
            isInteractive: true,
            strokeColor: palette.quickBarSurfaceStroke.opacity(isHovered ? 0.26 : 0.18),
            shadowColor: palette.splitPaneShadow,
            shadowOpacity: 0.04,
            shadowRadius: 5,
            shadowYOffset: 1
        )
    }

    private func preferredScheme(for theme: AppTheme) -> ColorScheme {
        theme.usesDarkAppearance ? .dark : .light
    }
}
