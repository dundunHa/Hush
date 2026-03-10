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

    private static let state = HushTypographyState()

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
        let settings = state.current()
        let size = CGFloat(settings.scaledSize(from: referenceSize))
        guard settings.normalizedFamilyName != nil else {
            let systemFont = Font.system(size: size, weight: weight)
            return italic ? systemFont.italic() : systemFont
        }

        let font = HushFontResolver.contentFont(
            settings: settings,
            referenceSize: referenceSize,
            weight: nsWeight(for: weight),
            italic: italic
        )
        return HushFontResolver.swiftUIFont(from: font)
    }

    static func monospaced(
        _ referenceSize: Double,
        weight: Font.Weight = .regular
    ) -> Font {
        let settings = state.current()
        return .system(
            size: CGFloat(settings.scaledSize(from: referenceSize)),
            weight: weight,
            design: .monospaced
        )
    }

    static func apply(_ settings: AppFontSettings) {
        state.update(settings)
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

private final class HushTypographyState {
    private let lock = NSLock()
    private var settings = AppFontSettings.default

    func current() -> AppFontSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    func update(_ next: AppFontSettings) {
        lock.lock()
        settings = next
        lock.unlock()
    }
}
