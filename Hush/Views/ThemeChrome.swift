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

    var body: some View {
        ZStack {
            if usesGlassSidebar {
                SidebarVibrancyHost()

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.sidebarBackground,
                                palette.sidebarGlassTint.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.sidebarGlassHighlight.opacity(0.90),
                                palette.sidebarGlassTint.opacity(0.18),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RadialGradient(
                    colors: [
                        palette.sidebarGlassHighlight.opacity(0.18),
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
                    .fill(palette.sidebarGlassHighlight.opacity(0.40))
                    .frame(width: 1)
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
