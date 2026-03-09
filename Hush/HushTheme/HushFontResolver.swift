import AppKit
import SwiftUI

enum HushFontResolver {
    private struct FamilyMember {
        let fontName: String
        let weight: Int
        let isItalic: Bool

        init?(rawMember: [Any]) {
            guard rawMember.count >= 4,
                  let fontName = rawMember[0] as? String
            else {
                return nil
            }

            let weightNumber = rawMember[2] as? NSNumber
            let traitsNumber = rawMember[3] as? NSNumber

            self.fontName = fontName
            weight = weightNumber?.intValue ?? 5
            let traits = NSFontTraitMask(rawValue: UInt(traitsNumber?.uintValue ?? 0))
            isItalic = traits.contains(.italicFontMask)
        }
    }

    static func availableFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func contentFont(
        settings: AppFontSettings,
        referenceSize: Double,
        weight: NSFont.Weight = .regular,
        italic: Bool = false
    ) -> NSFont {
        let size = CGFloat(settings.scaledSize(from: referenceSize))
        guard let familyName = settings.normalizedFamilyName else {
            return systemFont(size: size, weight: weight, italic: italic)
        }

        if let fontName = preferredFontName(
            familyName: familyName,
            weight: weight,
            italic: italic
        ),
            let font = NSFont(name: fontName, size: size)
        {
            return font
        }

        return systemFont(size: size, weight: weight, italic: italic)
    }

    static func monospacedFont(
        settings: AppFontSettings,
        referenceSize: Double,
        weight: NSFont.Weight = .regular
    ) -> NSFont {
        let size = CGFloat(settings.scaledSize(from: referenceSize))
        return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }

    static func swiftUIFont(from font: NSFont) -> Font {
        .custom(font.fontName, size: font.pointSize)
    }

    private static func preferredFontName(
        familyName: String,
        weight: NSFont.Weight,
        italic: Bool
    ) -> String? {
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: familyName)?
            .compactMap({ FamilyMember(rawMember: $0) }),
            !members.isEmpty
        else {
            return nil
        }

        let exactStyleMatches = members.filter { $0.isItalic == italic }
        let candidatePool = exactStyleMatches.isEmpty ? members : exactStyleMatches
        let targetWeight = targetMemberWeight(for: weight)
        return candidatePool
            .min { lhs, rhs in
                abs(lhs.weight - targetWeight) < abs(rhs.weight - targetWeight)
            }?
            .fontName
    }

    private static func systemFont(
        size: CGFloat,
        weight: NSFont.Weight,
        italic: Bool
    ) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard italic else { return base }

        let descriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func targetMemberWeight(for weight: NSFont.Weight) -> Int {
        switch weight.rawValue {
        case ..<(-0.45):
            return 3
        case ..<(-0.15):
            return 4
        case ..<0.15:
            return 5
        case ..<0.35:
            return 6
        case ..<0.5:
            return 8
        default:
            return 9
        }
    }
}
