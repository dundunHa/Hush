import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var container: AppContainer

    private let themeColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: HushSpacing.md)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HushSpacing.xl) {
                Text("General")
                    .font(HushTypography.heading)

                appearanceSection
                concurrencySection
            }
            .padding(HushSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themeRefreshAware()
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Appearance")
                .font(HushTypography.captionBold)
                .foregroundStyle(HushColors.secondaryText)

            LazyVGrid(columns: themeColumns, alignment: .leading, spacing: HushSpacing.md) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    ThemeOptionCard(
                        theme: theme,
                        isSelected: container.settings.theme == theme
                    ) {
                        container.settings.theme = theme
                    }
                }
            }

            Text(
                "Dark keeps the app contrasty, Light is neutral for daily work, " +
                    "and ReadPaper uses a warmer canvas inspired by Claude's reading surface."
            )
            .font(HushTypography.caption)
            .foregroundStyle(HushColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }

    private var concurrencySection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Concurrency")
                .font(HushTypography.captionBold)
                .foregroundStyle(HushColors.secondaryText)

            HStack(spacing: HushSpacing.md) {
                Text("Max concurrent requests")
                    .font(HushTypography.body)

                Spacer(minLength: 0)

                Picker("", selection: $container.settings.maxConcurrentRequests) {
                    ForEach(1 ... 5, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Text("Maximum number of conversations that can stream responses simultaneously.")
                .font(HushTypography.caption)
                .foregroundStyle(HushColors.secondaryText)
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }
}

private struct ThemeOptionCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let onTap: () -> Void

    private var palette: HushThemePalette {
        HushColors.palette(for: theme)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: HushSpacing.md) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.rootBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(isSelected ? palette.accentMutedStroke : palette.subtleStroke, lineWidth: 1)
                        }
                        .frame(height: 120)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(palette.sidebarBackground)
                                    .frame(width: 52)

                                VStack(alignment: .leading, spacing: 8) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(palette.cardBackground)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(palette.subtleStroke, lineWidth: 1)
                                        )
                                        .frame(height: 36)

                                    HStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(palette.accentMutedBackground)
                                            .frame(width: 58, height: 18)

                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(palette.softFillStrong)
                                            .frame(width: 40, height: 18)
                                    }

                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(
                                            LinearGradient(
                                                colors: [palette.composerShellTop, palette.composerShellBottom],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .stroke(palette.composerShellStroke, lineWidth: 1)
                                        )
                                        .frame(height: 22)
                                }
                                .padding(10)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(palette.accent)
                            .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.displayName)
                        .font(HushTypography.body.weight(.semibold))
                        .foregroundStyle(HushColors.primaryText)

                    Text(theme.subtitle)
                        .font(HushTypography.caption)
                        .foregroundStyle(HushColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(HushSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                    .fill(isSelected ? HushColors.selectionFill : HushColors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                            .stroke(isSelected ? HushColors.selectionStroke : HushColors.subtleStroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .themeRefreshAware()
    }
}
