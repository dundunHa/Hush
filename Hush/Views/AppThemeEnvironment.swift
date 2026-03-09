import SwiftUI

private struct HushThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppTheme = .dark
}

extension EnvironmentValues {
    var hushTheme: AppTheme {
        get { self[HushThemeEnvironmentKey.self] }
        set { self[HushThemeEnvironmentKey.self] = newValue }
    }
}

private struct ThemeRefreshAwareModifier: ViewModifier {
    @Environment(\.hushTheme) private var theme

    func body(content: Content) -> some View {
        _ = theme
        return content
    }
}

extension View {
    func themeRefreshAware() -> some View {
        modifier(ThemeRefreshAwareModifier())
    }
}
