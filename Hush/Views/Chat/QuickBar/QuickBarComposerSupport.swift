import SwiftUI

enum QuickBarPanelReleaseMetrics {
    static let width: CGFloat = 708
    static let compactHeight: CGFloat = 196
    static let expandedHeight: CGFloat = 548
}

struct QuickBarComposerLayoutMetrics: Sendable {
    let shellCornerRadius: CGFloat
    let shellHorizontalInset: CGFloat
    let shellTopInset: CGFloat
    let shellBottomInset: CGFloat
    let editorMinHeight: CGFloat
    let editorMaxHeight: CGFloat
    let editorHorizontalPadding: CGFloat
    let editorVerticalPadding: CGFloat
    let placeholderHorizontalInset: CGFloat
    let placeholderTopInset: CGFloat
    let placeholderFontSize: CGFloat
    let editorSurfaceHorizontalInset: CGFloat
    let editorSurfaceVerticalInset: CGFloat
    let toolbarTopPadding: CGFloat
    let toolbarHorizontalInset: CGFloat
    let toolbarBottomPadding: CGFloat
    let toolbarMinHeight: CGFloat
    let toolbarSpacing: CGFloat
    let controlHitSize: CGFloat
    let providerLabelFontSize: CGFloat
    let modelIconSize: CGFloat
    let modelLabelFontSize: CGFloat
    let modelChevronSize: CGFloat
    let capsuleHorizontalPadding: CGFloat
    let capsuleVisualHeight: CGFloat
    let sendButtonHitSize: CGFloat
    let sendButtonVisualSize: CGFloat
    let sendIconSize: CGFloat
}

struct QuickBarComposerExpandedEditorSurface: View {
    let palette: HushThemePalette
    let usesDarkAppearance: Bool
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            QuickBarMinimalSurface(
                shape: shape,
                fill: palette.quickBarSurface.opacity(usesDarkAppearance ? 0.11 : 0.30),
                stroke: palette.quickBarSurfaceStroke.opacity(usesDarkAppearance ? 0.06 : 0.11),
                shadowColor: palette.splitPaneShadow,
                shadowOpacity: 0,
                shadowRadius: 0,
                shadowYOffset: 0
            )

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(usesDarkAppearance ? 0.012 : 0.06),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .clipShape(shape)
        }
    }
}
