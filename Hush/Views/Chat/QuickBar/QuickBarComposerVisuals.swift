import SwiftUI

enum QuickBarComposerVisuals {
    @ViewBuilder
    static func shellSurface(
        isExpandedLayout: Bool,
        metrics: QuickBarComposerLayoutMetrics,
        palette: HushThemePalette,
        usesDarkAppearance: Bool
    ) -> some View {
        if isExpandedLayout {
            Color.clear
        } else {
            let shape = RoundedRectangle(cornerRadius: metrics.shellCornerRadius, style: .continuous)

            ZStack {
                QuickBarMinimalSurface(
                    shape: shape,
                    fill: palette.quickBarSurface.opacity(usesDarkAppearance ? 0.92 : 0.975),
                    stroke: palette.quickBarSurfaceStroke.opacity(usesDarkAppearance ? 0.22 : 0.48),
                    shadowColor: palette.splitPaneShadow,
                    shadowOpacity: usesDarkAppearance ? 0.18 : 0.10,
                    shadowRadius: 12,
                    shadowYOffset: 2
                )

                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(usesDarkAppearance ? 0.08 : 0.38),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .clipShape(shape)

                shape
                    .strokeBorder(
                        Color.white.opacity(usesDarkAppearance ? 0.04 : 0.16),
                        lineWidth: 0.5
                    )
            }
        }
    }

    static func controlCapsuleSurface(
        isHovered: Bool,
        isExpandedLayout: Bool,
        palette: HushThemePalette,
        usesDarkAppearance: Bool
    ) -> some View {
        QuickBarMinimalSurface(
            shape: Capsule(style: .continuous),
            fill: controlCapsuleFillColor(
                isHovered: isHovered,
                isExpandedLayout: isExpandedLayout,
                palette: palette,
                usesDarkAppearance: usesDarkAppearance
            ),
            stroke: controlCapsuleStrokeColor(
                isHovered: isHovered,
                isExpandedLayout: isExpandedLayout,
                palette: palette,
                usesDarkAppearance: usesDarkAppearance
            ),
            shadowColor: palette.splitPaneShadow,
            shadowOpacity: isExpandedLayout ? 0 : (isHovered ? 0.08 : 0.04),
            shadowRadius: isExpandedLayout ? 0 : 4,
            shadowYOffset: isExpandedLayout ? 0 : 1
        )
    }

    static func sendButtonSurface(
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool,
        isExpandedLayout: Bool,
        palette: HushThemePalette,
        usesDarkAppearance: Bool
    ) -> some View {
        QuickBarMinimalSurface(
            shape: Circle(),
            fill: actionFillColor(
                isHovered: isHovered,
                isEnabled: isEnabled,
                isSending: isSending,
                palette: palette,
                usesDarkAppearance: usesDarkAppearance
            ),
            stroke: actionStrokeColor(
                isHovered: isHovered,
                isEnabled: isEnabled,
                isSending: isSending,
                palette: palette
            ),
            shadowColor: palette.splitPaneShadow,
            shadowOpacity: actionShadowOpacity(
                isHovered: isHovered,
                isEnabled: isEnabled,
                isSending: isSending,
                isExpandedLayout: isExpandedLayout
            ),
            shadowRadius: isHovered ? 8 : 6,
            shadowYOffset: 2
        )
    }

    private static func controlCapsuleFillColor(
        isHovered: Bool,
        isExpandedLayout: Bool,
        palette: HushThemePalette,
        usesDarkAppearance: Bool
    ) -> Color {
        if isExpandedLayout {
            return palette.quickBarControlFill.opacity(
                usesDarkAppearance
                    ? (isHovered ? 0.18 : 0.10)
                    : (isHovered ? 0.24 : 0.14)
            )
        }

        return palette.quickBarControlFill.opacity(
            usesDarkAppearance
                ? (isHovered ? 0.34 : 0.18)
                : (isHovered ? 0.56 : 0.34)
        )
    }

    private static func controlCapsuleStrokeColor(
        isHovered: Bool,
        isExpandedLayout: Bool,
        palette: HushThemePalette,
        usesDarkAppearance: Bool
    ) -> Color {
        if isExpandedLayout {
            return palette.quickBarSurfaceStroke.opacity(
                isHovered
                    ? (usesDarkAppearance ? 0.12 : 0.18)
                    : (usesDarkAppearance ? 0.08 : 0.12)
            )
        }

        return palette.quickBarSurfaceStroke.opacity(
            isHovered
                ? (usesDarkAppearance ? 0.24 : 0.34)
                : (usesDarkAppearance ? 0.16 : 0.24)
        )
    }

    private static func actionFillColor(
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool,
        palette: HushThemePalette,
        usesDarkAppearance: Bool
    ) -> Color {
        if isSending {
            return palette.destructiveActionBackground.opacity(
                usesDarkAppearance
                    ? (isHovered ? 0.96 : 0.88)
                    : (isHovered ? 1 : 0.94)
            )
        }

        if isEnabled {
            return palette.quickBarButtonFill.opacity(
                usesDarkAppearance
                    ? (isHovered ? 0.98 : 0.92)
                    : (isHovered ? 1 : 0.96)
            )
        }

        return palette.quickBarDisabledButtonFill.opacity(usesDarkAppearance ? 0.88 : 0.96)
    }

    private static func actionStrokeColor(
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool,
        palette: HushThemePalette
    ) -> Color {
        if isSending {
            return palette.destructiveActionForeground.opacity(isHovered ? 0.32 : 0.22)
        }

        if isEnabled {
            return palette.quickBarButtonFill.opacity(isHovered ? 0.58 : 0.40)
        }

        return palette.quickBarSurfaceStroke.opacity(0.18)
    }

    private static func actionShadowOpacity(
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool,
        isExpandedLayout: Bool
    ) -> Double {
        if isExpandedLayout {
            if isSending {
                return isHovered ? 0.12 : 0.08
            }

            if isEnabled {
                return isHovered ? 0.10 : 0.06
            }

            return 0.02
        }

        if isSending {
            return isHovered ? 0.18 : 0.12
        }

        if isEnabled {
            return isHovered ? 0.14 : 0.10
        }

        return 0.04
    }
}
