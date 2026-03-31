import SwiftUI

struct SettingsListRow: View {
    @Environment(\.hushThemePalette) private var palette

    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    let trailingView: AnyView?
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    init(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String? = nil,
        trailingView: AnyView? = nil,
        onTap: @escaping () -> Void
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.trailingView = trailingView
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: HushSpacing.md) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(isHovered ? 0.20 : 0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(HushTypography.body)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(HushTypography.caption)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let trailingView {
                    trailingView
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        palette.secondaryText.opacity(isHovered ? 1.0 : 0.6)
                    )
            }
            .padding(.horizontal, HushSpacing.lg)
            .padding(.vertical, HushSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                    .fill(isHovered ? palette.hoverFill : palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                            .stroke(
                                isHovered ? palette.hoverStroke : palette.subtleStroke,
                                lineWidth: 1
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#if DEBUG

    #Preview("SettingsListRow") {
        VStack(spacing: HushSpacing.md) {
            SettingsListRow(
                icon: "person.badge.key",
                iconColor: .purple,
                title: "Code Default",
                subtitle: "You are a helpful assistant.",
                onTap: {}
            )

            SettingsListRow(
                icon: "sparkles",
                iconColor: .blue,
                title: "O3 Mini",
                subtitle: nil,
                trailingView: AnyView(
                    Text("Default")
                        .font(HushTypography.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                ),
                onTap: {}
            )
        }
        .padding()
    }

#endif
