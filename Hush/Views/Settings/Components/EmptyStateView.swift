import SwiftUI

struct EmptyStateView: View {
    @Environment(\.hushThemePalette) private var palette

    let icon: String
    let title: String
    let description: String?

    init(icon: String, title: String, description: String? = nil) {
        self.icon = icon
        self.title = title
        self.description = description
    }

    var body: some View {
        VStack(spacing: HushSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(palette.secondaryText.opacity(0.5))

            VStack(spacing: 4) {
                Text(title)
                    .font(HushTypography.body)
                    .foregroundStyle(palette.secondaryText)

                if let description {
                    Text(description)
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, HushSpacing.xl)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, HushSpacing.xl)
    }
}

#if DEBUG

    #Preview("EmptyStateView") {
        EmptyStateView(
            icon: "archivebox",
            title: "No archived threads",
            description: "Threads you archive will appear here."
        )
        .padding()
    }

#endif
