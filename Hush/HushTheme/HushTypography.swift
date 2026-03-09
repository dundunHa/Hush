import AppKit
import Foundation
import SwiftUI

enum HushTypography {
    private enum Metrics {
        static let pageTitle = 28.0
        static let heading = 20.0
        static let body = 14.0
        static let footnote = 13.0
        static let caption = 12.0
        static let captionBold = 11.0
    }

    static var pageTitle: Font {
        scaled(Metrics.pageTitle, weight: .semibold)
    }

    static var heading: Font {
        scaled(Metrics.heading, weight: .semibold)
    }

    static var body: Font {
        scaled(Metrics.body)
    }

    static var caption: Font {
        scaled(Metrics.caption)
    }

    static var captionBold: Font {
        scaled(Metrics.captionBold, weight: .semibold)
    }

    static var footnote: Font {
        scaled(Metrics.footnote)
    }

    static func scaled(
        _ referenceSize: Double,
        weight: Font.Weight = .regular,
        italic: Bool = false
    ) -> Font {
        let font = resolvedFont(referenceSize, weight: weight, italic: italic)
        return HushFontResolver.swiftUIFont(from: font)
    }

    static func monospaced(
        _ referenceSize: Double,
        weight: Font.Weight = .regular
    ) -> Font {
        return .system(
            size: CGFloat(referenceSize),
            weight: weight,
            design: .monospaced
        )
    }

    private static func resolvedFont(
        _ referenceSize: Double,
        weight: Font.Weight,
        italic: Bool
    ) -> NSFont {
        let size = CGFloat(referenceSize)
        let base = NSFont.systemFont(ofSize: size, weight: nsWeight(for: weight))
        guard italic else { return base }

        let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func nsWeight(for weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight:
            return .ultraLight
        case .thin:
            return .thin
        case .light:
            return .light
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        case .heavy:
            return .heavy
        case .black:
            return .black
        default:
            return .regular
        }
    }
}

#if DEBUG
    extension HushTypography {
        static func resolvedFontForTesting(
            _ referenceSize: Double,
            weight: Font.Weight = .regular,
            italic: Bool = false
        ) -> NSFont {
            resolvedFont(referenceSize, weight: weight, italic: italic)
        }
    }
#endif
