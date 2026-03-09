import SwiftUI

enum SettingsLayout {
    static let contentMaxWidth: CGFloat = 720
}

extension View {
    func settingsCenteredContentColumn(
        maxWidth: CGFloat = SettingsLayout.contentMaxWidth,
        horizontalPadding: CGFloat = HushSpacing.xl,
        verticalPadding: CGFloat = HushSpacing.xl
    ) -> some View {
        frame(maxWidth: maxWidth, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
