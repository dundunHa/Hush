import AppKit
import SwiftUI

struct SplitPaneSidebarSurface: View {
    let theme: AppTheme
    let palette: HushThemePalette
    let sidebarWidth: CGFloat
    let revealWidth: CGFloat
    let prefersNativeGlassShell: Bool

    init(
        theme: AppTheme,
        palette: HushThemePalette,
        sidebarWidth: CGFloat,
        revealWidth: CGFloat,
        prefersNativeGlassShell: Bool = false
    ) {
        self.theme = theme
        self.palette = palette
        self.sidebarWidth = sidebarWidth
        self.revealWidth = revealWidth
        self.prefersNativeGlassShell = prefersNativeGlassShell
    }

    private var totalWidth: CGFloat {
        max(0, sidebarWidth + revealWidth)
    }

    var body: some View {
        SidebarMaterialBackground(
            theme: theme,
            palette: palette,
            prefersNativeGlassShell: prefersNativeGlassShell
        )
        .frame(width: totalWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}

struct SidebarMaterialBackground: View {
    let theme: AppTheme
    let palette: HushThemePalette
    let prefersNativeGlassShell: Bool

    init(
        theme: AppTheme,
        palette: HushThemePalette,
        prefersNativeGlassShell: Bool = false
    ) {
        self.theme = theme
        self.palette = palette
        self.prefersNativeGlassShell = prefersNativeGlassShell
    }

    private var usesGlassSidebar: Bool {
        theme.usesGlassSurface
    }

    private var usesNativeGlassSidebar: Bool {
        guard prefersNativeGlassShell, usesGlassSidebar else { return false }
        if #available(macOS 26.0, *) {
            return true
        }
        return false
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
        shellBody
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

    @ViewBuilder
    private var shellBody: some View {
        if usesNativeGlassSidebar {
            if #available(macOS 26.0, *) {
                SidebarNativeGlassBackground(theme: theme, palette: palette)
            } else {
                fallbackShellBody
            }
        } else {
            fallbackShellBody
        }
    }

    @ViewBuilder
    private var fallbackShellBody: some View {
        if usesGlassSidebar {
            ZStack {
                BehindWindowVibrancyHost(material: .sidebar)

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
            }
        } else {
            Rectangle()
                .fill(palette.sidebarBackground)
        }
    }
}

@available(macOS 26.0, *)
private struct SidebarNativeGlassBackground: View {
    let theme: AppTheme
    let palette: HushThemePalette

    private var resolvedGlass: Glass {
        Glass.regular
            .interactive(false)
            .tint(palette.sidebarGlassTint)
    }

    private var baseTintTopOpacity: Double {
        theme.usesDarkAppearance ? 0.18 : 0.12
    }

    private var baseTintBottomOpacity: Double {
        theme.usesDarkAppearance ? 0.10 : 0.06
    }

    private var specularOpacity: Double {
        theme.usesDarkAppearance ? 0.14 : 0.10
    }

    private var specularTailOpacity: Double {
        theme.usesDarkAppearance ? 0.05 : 0.03
    }

    private var topGlowOpacity: Double {
        theme.usesDarkAppearance ? 0.07 : 0.05
    }

    private var radialHighlightOpacity: Double {
        theme.usesDarkAppearance ? 0.08 : 0.06
    }

    var body: some View {
        let shape = Rectangle()

        shape
            .fill(.clear)
            .glassEffect(resolvedGlass, in: shape)
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.sidebarBackground.opacity(baseTintTopOpacity),
                                palette.sidebarGlassTint.opacity(baseTintBottomOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.sidebarGlassHighlight.opacity(specularOpacity),
                                palette.sidebarGlassTint.opacity(specularTailOpacity),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                palette.sidebarGlassHighlight.opacity(topGlowOpacity),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RadialGradient(
                    colors: [
                        palette.sidebarGlassHighlight.opacity(radialHighlightOpacity),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 8,
                    endRadius: 190
                )
            )
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
