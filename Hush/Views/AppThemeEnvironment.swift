import SwiftUI

private struct HushThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppTheme = .graphiteGlass
}

private struct HushThemePaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue: HushThemePalette = HushColors.palette(for: .graphiteGlass)
}

extension EnvironmentValues {
    var hushTheme: AppTheme {
        get { self[HushThemeEnvironmentKey.self] }
        set { self[HushThemeEnvironmentKey.self] = newValue }
    }

    var hushThemePalette: HushThemePalette {
        get { self[HushThemePaletteEnvironmentKey.self] }
        set { self[HushThemePaletteEnvironmentKey.self] = newValue }
    }
}
