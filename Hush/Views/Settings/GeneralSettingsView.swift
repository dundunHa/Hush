import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.hushThemePalette) private var themePalette

    private let themeColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: HushSpacing.md)
    ]
    private let fontFamilies = HushFontResolver.availableFamilies()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HushSpacing.xl) {
                Text("General")
                    .font(HushTypography.heading)

                appearanceSection
                typographySection
                concurrencySection
            }
            .settingsCenteredContentColumn()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Appearance")
                .font(HushTypography.captionBold)
                .foregroundStyle(themePalette.secondaryText)

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
                "Dark stays familiar, Graphite Glass adds a liquid sidebar with a calmer workspace, " +
                    "Light is neutral for daily work, and ReadPaper uses a warmer reading surface."
            )
            .font(HushTypography.caption)
            .foregroundStyle(themePalette.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: themePalette.cardBackground,
            stroke: themePalette.subtleStroke
        )
    }

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Message Typography")
                .font(HushTypography.captionBold)
                .foregroundStyle(themePalette.secondaryText)

            HStack(alignment: .top, spacing: HushSpacing.xl) {
                VStack(alignment: .leading, spacing: HushSpacing.sm) {
                    Text("Font family")
                        .font(HushTypography.scaled(14, weight: .semibold))

                    Picker("", selection: fontFamilySelection) {
                        Text("System").tag(String?.none)
                        ForEach(fontFamilies, id: \.self) { family in
                            Text(family).tag(Optional(family))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 280, alignment: .leading)

                    Text("Applies only to chat rendering. System settings and app UI copy stay unchanged. Code stays monospaced.")
                        .font(HushTypography.caption)
                        .foregroundStyle(themePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: HushSpacing.sm) {
                    Text("Font size")
                        .font(HushTypography.scaled(14, weight: .semibold))

                    HStack(spacing: HushSpacing.md) {
                        Slider(
                            value: fontSizeBinding,
                            in: AppFontSettings.minimumSize ... AppFontSettings.maximumSize,
                            step: 1
                        )
                        .frame(width: 180)

                        Text("\(Int(container.settings.fontSettings.normalizedSize)) pt")
                            .font(HushTypography.scaled(14, weight: .semibold))
                            .frame(width: 48, alignment: .trailing)
                    }

                    Button("Reset to 14pt / System") {
                        container.settings.fontSettings = .default
                    }
                    .buttonStyle(.link)
                }
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Render preview")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(themePalette.secondaryText)

                Text("Aa Preview text 123")
                    .font(renderPreviewFont)
                    .foregroundStyle(themePalette.primaryText)

                Text(selectedFontSummary)
                    .font(HushTypography.caption)
                    .foregroundStyle(themePalette.secondaryText)
            }
            .padding(HushSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                    .fill(themePalette.softFillStrong)
                    .overlay(
                        RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                            .stroke(themePalette.subtleStroke, lineWidth: 1)
                    )
            )
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: themePalette.cardBackground,
            stroke: themePalette.subtleStroke
        )
    }

    private var concurrencySection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Concurrency")
                .font(HushTypography.captionBold)
                .foregroundStyle(themePalette.secondaryText)

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
                .foregroundStyle(themePalette.secondaryText)
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: themePalette.cardBackground,
            stroke: themePalette.subtleStroke
        )
    }

    private var fontFamilySelection: Binding<String?> {
        Binding(
            get: { container.settings.fontSettings.normalizedFamilyName },
            set: { container.settings.fontSettings.familyName = $0 }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { container.settings.fontSettings.normalizedSize },
            set: { container.settings.fontSettings.size = $0 }
        )
    }

    private var selectedFontSummary: String {
        let family = container.settings.fontSettings.normalizedFamilyName ?? "System"
        return "\(family) / \(Int(container.settings.fontSettings.normalizedSize))pt"
    }

    private var renderPreviewFont: Font {
        let font = HushFontResolver.contentFont(
            settings: container.settings.fontSettings,
            referenceSize: 16,
            weight: .medium
        )
        return HushFontResolver.swiftUIFont(from: font)
    }
}

private struct ThemeOptionCard: View {
    @Environment(\.hushThemePalette) private var themePalette
    let theme: AppTheme
    let isSelected: Bool
    let onTap: () -> Void

    private var previewPalette: HushThemePalette {
        HushColors.palette(for: theme)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: HushSpacing.md) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(previewPalette.rootBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    isSelected ? previewPalette.accentMutedStroke : previewPalette.subtleStroke,
                                    lineWidth: 1
                                )
                        }
                        .frame(height: 120)
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                SidebarMaterialBackground(theme: theme, palette: previewPalette)
                                    .frame(width: 52)

                                VStack(alignment: .leading, spacing: 8) {
                                    WorkspaceChromeBackground(theme: theme, palette: previewPalette)
                                        .frame(height: 12)

                                    VStack(alignment: .leading, spacing: 8) {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(previewPalette.cardBackground)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(previewPalette.subtleStroke, lineWidth: 1)
                                            )
                                            .frame(height: 22)

                                        HStack(spacing: 6) {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(previewPalette.accentMutedBackground)
                                                .frame(width: 46, height: 16)

                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(previewPalette.codeBlockBackground)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .stroke(previewPalette.codeBlockBorder, lineWidth: 1)
                                                )
                                                .frame(width: 54, height: 16)
                                        }

                                        Spacer(minLength: 0)

                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(
                                                LinearGradient(
                                                    colors: [previewPalette.composerShellTop, previewPalette.composerShellBottom],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .stroke(previewPalette.composerShellStroke, lineWidth: 1)
                                            )
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(previewPalette.composerEditorBackground)
                                                    .padding(.horizontal, 9)
                                                    .padding(.vertical, 6)
                                            }
                                            .frame(height: 20)
                                    }
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(previewPalette.accent)
                            .padding(10)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.displayName)
                        .font(HushTypography.body.weight(.semibold))
                        .foregroundStyle(themePalette.primaryText)

                    Text(theme.subtitle)
                        .font(HushTypography.caption)
                        .foregroundStyle(themePalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(HushSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                    .fill(isSelected ? themePalette.selectionFill : themePalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                            .stroke(
                                isSelected ? themePalette.selectionStroke : themePalette.subtleStroke,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
