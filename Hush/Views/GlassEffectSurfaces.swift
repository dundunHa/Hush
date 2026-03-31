import AppKit
import SwiftUI

struct BehindWindowVibrancyHost: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context _: Context) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
    }
}

enum QuickBarNativeGlassID: String, Hashable, Sendable {
    case modelControl
    case openSettingsControl
    case sendAction
    case overflowButton
    case closeButton
}

enum QuickBarNativeGlassTransitionKind: Sendable {
    case matchedGeometry
    case materialize
    case identity
}

struct QuickBarNativeGlassRegistration: Sendable {
    let id: QuickBarNativeGlassID
    let transition: QuickBarNativeGlassTransitionKind

    init(
        id: QuickBarNativeGlassID,
        transition: QuickBarNativeGlassTransitionKind = .identity
    ) {
        self.id = id
        self.transition = transition
    }
}

struct QuickBarNativeGlassStyle: Sendable {
    let tint: Color?
    let isInteractive: Bool
    let strokeColor: Color
    let shadowColor: Color
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    init(
        tint: Color? = nil,
        isInteractive: Bool,
        strokeColor: Color,
        shadowColor: Color,
        shadowOpacity: Double,
        shadowRadius: CGFloat,
        shadowYOffset: CGFloat
    ) {
        self.tint = tint
        self.isInteractive = isInteractive
        self.strokeColor = strokeColor
        self.shadowColor = shadowColor
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowYOffset = shadowYOffset
    }
}

@available(macOS 26.0, *)
private extension View {
    @ViewBuilder
    func quickBarNativeGlassTransition(
        _ transition: QuickBarNativeGlassTransitionKind
    ) -> some View {
        switch transition {
        case .matchedGeometry:
            glassEffectTransition(.matchedGeometry)
        case .materialize:
            glassEffectTransition(.materialize)
        case .identity:
            self
        }
    }

    func quickBarNativeGlassRegistration(
        _ registration: QuickBarNativeGlassRegistration,
        namespace: Namespace.ID
    ) -> some View {
        glassEffectID(registration.id.rawValue, in: namespace)
            .quickBarNativeGlassTransition(registration.transition)
    }
}

@available(macOS 26.0, *)
struct QuickBarNativeGlassSurface<S: InsettableShape>: View {
    let shape: S
    let style: QuickBarNativeGlassStyle
    let registration: QuickBarNativeGlassRegistration
    let namespace: Namespace.ID

    private var resolvedGlass: Glass {
        let interactiveGlass = Glass.regular.interactive(style.isInteractive)
        if let tint = style.tint {
            return interactiveGlass.tint(tint)
        }
        return interactiveGlass
    }

    var body: some View {
        shape
            .fill(.clear)
            .glassEffect(resolvedGlass, in: shape)
            .quickBarNativeGlassRegistration(registration, namespace: namespace)
            .overlay(
                shape
                    .stroke(style.strokeColor, lineWidth: 0.5)
            )
            .shadow(
                color: style.shadowColor.opacity(style.shadowOpacity),
                radius: style.shadowRadius,
                x: 0,
                y: style.shadowYOffset
            )
    }
}

struct QuickBarLiquidGlassStyle {
    let tintTopOpacity: Double
    let tintBottomOpacity: Double
    let specularOpacity: Double
    let specularTailOpacity: Double
    let topGlowOpacity: Double
    let innerRimOpacity: Double
    let hotspotOpacity: Double
    let hotspotRadius: CGFloat
    let strokeOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    static func composerShell(isExpanded: Bool) -> Self {
        if isExpanded {
            return Self(
                tintTopOpacity: 0.028,
                tintBottomOpacity: 0.018,
                specularOpacity: 0.045,
                specularTailOpacity: 0.012,
                topGlowOpacity: 0.03,
                innerRimOpacity: 0.02,
                hotspotOpacity: 0.012,
                hotspotRadius: 120,
                strokeOpacity: 0.16,
                shadowOpacity: 0.0,
                shadowRadius: 0,
                shadowYOffset: 0
            )
        }

        return Self(
            tintTopOpacity: 0.11,
            tintBottomOpacity: 0.07,
            specularOpacity: 0.20,
            specularTailOpacity: 0.05,
            topGlowOpacity: 0.13,
            innerRimOpacity: 0.10,
            hotspotOpacity: 0.07,
            hotspotRadius: 145,
            strokeOpacity: 0.54,
            shadowOpacity: 0.04,
            shadowRadius: 6,
            shadowYOffset: 2
        )
    }

    static let panelShell = Self(
        tintTopOpacity: 0.08,
        tintBottomOpacity: 0.05,
        specularOpacity: 0.16,
        specularTailOpacity: 0.04,
        topGlowOpacity: 0.10,
        innerRimOpacity: 0.08,
        hotspotOpacity: 0.05,
        hotspotRadius: 190,
        strokeOpacity: 0.46,
        shadowOpacity: 0.03,
        shadowRadius: 6,
        shadowYOffset: 2
    )

    static let transcriptInset = Self(
        tintTopOpacity: 0.024,
        tintBottomOpacity: 0.014,
        specularOpacity: 0.036,
        specularTailOpacity: 0.01,
        topGlowOpacity: 0.024,
        innerRimOpacity: 0.016,
        hotspotOpacity: 0.01,
        hotspotRadius: 132,
        strokeOpacity: 0.13,
        shadowOpacity: 0.0,
        shadowRadius: 0,
        shadowYOffset: 0
    )

    static func control(isHovered: Bool) -> Self {
        if isHovered {
            return Self(
                tintTopOpacity: 0.24,
                tintBottomOpacity: 0.16,
                specularOpacity: 0.24,
                specularTailOpacity: 0.07,
                topGlowOpacity: 0.18,
                innerRimOpacity: 0.12,
                hotspotOpacity: 0.10,
                hotspotRadius: 82,
                strokeOpacity: 0.34,
                shadowOpacity: 0.03,
                shadowRadius: 4,
                shadowYOffset: 1
            )
        }

        return Self(
            tintTopOpacity: 0.18,
            tintBottomOpacity: 0.11,
            specularOpacity: 0.18,
            specularTailOpacity: 0.05,
            topGlowOpacity: 0.12,
            innerRimOpacity: 0.09,
            hotspotOpacity: 0.07,
            hotspotRadius: 72,
            strokeOpacity: 0.28,
            shadowOpacity: 0.02,
            shadowRadius: 4,
            shadowYOffset: 1
        )
    }

    static func actionButton(isHovered: Bool) -> Self {
        if isHovered {
            return Self(
                tintTopOpacity: 0.28,
                tintBottomOpacity: 0.18,
                specularOpacity: 0.26,
                specularTailOpacity: 0.08,
                topGlowOpacity: 0.18,
                innerRimOpacity: 0.14,
                hotspotOpacity: 0.11,
                hotspotRadius: 84,
                strokeOpacity: 0.36,
                shadowOpacity: 0.04,
                shadowRadius: 5,
                shadowYOffset: 1
            )
        }

        return Self(
            tintTopOpacity: 0.22,
            tintBottomOpacity: 0.14,
            specularOpacity: 0.20,
            specularTailOpacity: 0.06,
            topGlowOpacity: 0.14,
            innerRimOpacity: 0.10,
            hotspotOpacity: 0.08,
            hotspotRadius: 76,
            strokeOpacity: 0.30,
            shadowOpacity: 0.03,
            shadowRadius: 4,
            shadowYOffset: 1
        )
    }

    static func toolbarOrb(isHovered: Bool) -> Self {
        if isHovered {
            return Self(
                tintTopOpacity: 0.10,
                tintBottomOpacity: 0.06,
                specularOpacity: 0.10,
                specularTailOpacity: 0.03,
                topGlowOpacity: 0.06,
                innerRimOpacity: 0.04,
                hotspotOpacity: 0.03,
                hotspotRadius: 64,
                strokeOpacity: 0.18,
                shadowOpacity: 0.01,
                shadowRadius: 2,
                shadowYOffset: 0
            )
        }

        return Self(
            tintTopOpacity: 0.045,
            tintBottomOpacity: 0.028,
            specularOpacity: 0.05,
            specularTailOpacity: 0.012,
            topGlowOpacity: 0.03,
            innerRimOpacity: 0.02,
            hotspotOpacity: 0.015,
            hotspotRadius: 56,
            strokeOpacity: 0.12,
            shadowOpacity: 0.0,
            shadowRadius: 0,
            shadowYOffset: 0
        )
    }
}

struct QuickBarLiquidGlassSurface<S: InsettableShape>: View {
    let shape: S
    let baseTint: Color
    let highlightTint: Color
    let shadowColor: Color
    let style: QuickBarLiquidGlassStyle

    var body: some View {
        shape
            .fill(.clear)
            .background {
                BehindWindowVibrancyHost(material: .hudWindow)
                    .clipShape(shape)
            }
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                baseTint.opacity(style.tintTopOpacity),
                                baseTint.opacity(style.tintBottomOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                highlightTint.opacity(style.specularOpacity),
                                highlightTint.opacity(style.specularTailOpacity),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                highlightTint.opacity(style.topGlowOpacity),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                shape
                    .inset(by: 1)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                highlightTint.opacity(style.innerRimOpacity),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .overlay(
                RadialGradient(
                    colors: [
                        highlightTint.opacity(style.hotspotOpacity),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 6,
                    endRadius: style.hotspotRadius
                )
                .clipShape(shape)
            )
            .overlay(
                shape
                    .stroke(highlightTint.opacity(style.strokeOpacity), lineWidth: 0.5)
            )
            .shadow(
                color: shadowColor.opacity(style.shadowOpacity),
                radius: style.shadowRadius,
                x: 0,
                y: style.shadowYOffset
            )
    }
}

struct QuickBarMinimalSurface<S: InsettableShape>: View {
    let shape: S
    let fill: Color
    let stroke: Color
    let shadowColor: Color
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat

    var body: some View {
        shape
            .fill(fill)
            .overlay(
                shape
                    .strokeBorder(stroke, lineWidth: 0.5)
            )
            .shadow(
                color: shadowColor.opacity(shadowOpacity),
                radius: shadowRadius,
                x: 0,
                y: shadowYOffset
            )
    }
}

struct QuickBarGlassSurface<S: InsettableShape>: View {
    let shape: S
    let registration: QuickBarNativeGlassRegistration
    let namespace: Namespace.ID?
    let nativeStyle: QuickBarNativeGlassStyle
    let fallbackBaseTint: Color
    let fallbackHighlightTint: Color
    let fallbackShadowColor: Color
    let fallbackStyle: QuickBarLiquidGlassStyle

    var body: some View {
        if #available(macOS 26.0, *), let namespace {
            QuickBarNativeGlassSurface(
                shape: shape,
                style: nativeStyle,
                registration: registration,
                namespace: namespace
            )
        } else {
            QuickBarLiquidGlassSurface(
                shape: shape,
                baseTint: fallbackBaseTint,
                highlightTint: fallbackHighlightTint,
                shadowColor: fallbackShadowColor,
                style: fallbackStyle
            )
        }
    }
}
