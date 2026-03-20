import AppKit
import SwiftUI

private struct SidebarVibrancyHost: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }
}

private struct LeadingPaneBorderMask: View {
    let topRadius: CGFloat
    let bottomRadius: CGFloat

    private var leadingMaskWidth: CGFloat {
        max(topRadius, bottomRadius) + 2
    }

    var body: some View {
        if bottomRadius > 0 {
            Rectangle()
                .frame(width: leadingMaskWidth)
        } else if topRadius > 0 {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .frame(width: 2)

                Rectangle()
                    .frame(width: topRadius + 2)
                    .padding(.bottom, 1)
            }
        } else {
            Rectangle()
                .frame(width: 1)
        }
    }
}

struct LeadingPaneBorder: View {
    let topRadius: CGFloat
    let bottomRadius: CGFloat
    let color: Color

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: 0,
            topTrailingRadius: 0,
            style: .continuous
        )

        shape
            .strokeBorder(color, lineWidth: 1)
            .mask(alignment: .leading) {
                LeadingPaneBorderMask(topRadius: topRadius, bottomRadius: bottomRadius)
            }
    }
}

struct SplitPaneSidebarSurface: View {
    let theme: AppTheme
    let palette: HushThemePalette
    let sidebarWidth: CGFloat
    let revealWidth: CGFloat

    private var totalWidth: CGFloat {
        max(0, sidebarWidth + revealWidth)
    }

    var body: some View {
        SidebarMaterialBackground(theme: theme, palette: palette)
            .frame(width: totalWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }
}

struct SidebarMaterialBackground: View {
    let theme: AppTheme
    let palette: HushThemePalette

    private var usesGlassSidebar: Bool {
        theme.usesGlassSurface
    }

    private var glassTintOpacity: Double {
        theme.usesDarkAppearance ? 0.72 : 0.64
    }

    private var glassHighlightOpacity: Double {
        theme.usesDarkAppearance ? 0.90 : 0.58
    }

    private var glassSecondaryTintOpacity: Double {
        theme.usesDarkAppearance ? 0.18 : 0.10
    }

    private var glassRadialHighlightOpacity: Double {
        theme.usesDarkAppearance ? 0.18 : 0.14
    }

    private var leadingEdgeStrokeOpacity: Double {
        theme.usesDarkAppearance ? 0.40 : 0.68
    }

    private var trailingEdgeStrokeOpacity: Double {
        theme.usesDarkAppearance ? 0.18 : 0.56
    }

    private var trailingEdgeShadowOpacity: Double {
        theme.usesDarkAppearance ? 0.12 : 0.18
    }

    private var trailingEdgeShadowWidth: CGFloat {
        theme.usesDarkAppearance ? 14 : 22
    }

    var body: some View {
        ZStack {
            if usesGlassSidebar {
                SidebarVibrancyHost()

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.sidebarBackground,
                                palette.sidebarGlassTint.opacity(glassTintOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.sidebarGlassHighlight.opacity(glassHighlightOpacity),
                                palette.sidebarGlassTint.opacity(glassSecondaryTintOpacity),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RadialGradient(
                    colors: [
                        palette.sidebarGlassHighlight.opacity(glassRadialHighlightOpacity),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 190
                )
            } else {
                Rectangle()
                    .fill(palette.sidebarBackground)
            }
        }
        .overlay(alignment: .leading) {
            if usesGlassSidebar {
                Rectangle()
                    .fill(palette.sidebarGlassStroke.opacity(leadingEdgeStrokeOpacity))
                    .frame(width: 1)
            }
        }
        .overlay(alignment: .trailing) {
            if usesGlassSidebar {
                ZStack(alignment: .trailing) {
                    LinearGradient(
                        colors: [
                            palette.sidebarGlassShadow.opacity(trailingEdgeShadowOpacity),
                            .clear
                        ],
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                    .frame(width: trailingEdgeShadowWidth)

                    Rectangle()
                        .fill(palette.sidebarGlassStroke.opacity(trailingEdgeStrokeOpacity))
                        .frame(width: 1)
                }
            }
        }
    }
}

struct WorkspaceChromeBackground: View {
    let theme: AppTheme
    let palette: HushThemePalette

    private var usesGlassChrome: Bool {
        theme.usesGlassSurface
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(usesGlassChrome ? palette.workspaceChromeBackground : palette.rootBackground)

            if usesGlassChrome {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.sidebarGlassHighlight.opacity(0.08),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(usesGlassChrome ? palette.separator : .clear)
                .frame(height: 1)
        }
    }
}
