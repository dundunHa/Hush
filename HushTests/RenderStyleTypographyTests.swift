import AppKit
import Foundation
@testable import Hush
import Testing

struct RenderStyleTypographyTests {
    @Test("RenderStyle uses configured body font size")
    func renderStyleUsesConfiguredBodyFontSize() {
        let fontSettings = AppFontSettings(size: 18)
        let style = RenderStyle.fromTheme(.dark, fontSettings: fontSettings)

        #expect(abs(style.bodyFont.pointSize - 18) < 0.001)
        #expect(style.heading1Font.pointSize > style.bodyFont.pointSize)
        #expect(style.codeFont.pointSize < style.bodyFont.pointSize)
    }

    @Test("RenderStyle cache key changes when font family changes")
    func renderStyleCacheKeyChangesWithFontFamily() throws {
        let familyName = try #require(HushFontResolver.availableFamilies().first)

        let baseline = RenderStyle.fromTheme(.dark, fontSettings: .default)
        let custom = RenderStyle.fromTheme(
            .dark,
            fontSettings: AppFontSettings(
                familyName: familyName,
                size: AppFontSettings.defaultSize
            )
        )

        #expect(baseline.cacheKey != custom.cacheKey)
    }
}
