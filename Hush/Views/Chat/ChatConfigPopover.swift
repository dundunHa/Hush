import Foundation
import SwiftUI

struct ChatConfigDrawer: View {
    @Binding var parameters: ModelParameters
    var onClose: () -> Void = {}
    @Environment(\.hushThemePalette) var palette

    enum Limits {
        static let contextMessages = 1 ... 30
        static let maxTokens = 0 ... 8192
    }

    enum Layout {
        static let drawerWidth: CGFloat = 356
        static let valueFieldWidth: CGFloat = 68
        static let sectionCornerRadius: CGFloat = 22
        static let panelCornerRadius: CGFloat = 28
        static let iconSize: CGFloat = 28
    }

    private static let contextLimitFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = Limits.contextMessages.lowerBound as NSNumber
        formatter.maximum = Limits.contextMessages.upperBound as NSNumber
        formatter.allowsFloats = false
        return formatter
    }()

    private static let maxTokensFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = Limits.maxTokens.lowerBound as NSNumber
        formatter.maximum = Limits.maxTokens.upperBound as NSNumber
        formatter.allowsFloats = false
        formatter.zeroSymbol = "Unlimited"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: HushSpacing.lg) {
            headerView
            summaryStrip
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: HushSpacing.md) {
                    configSection(
                        title: "History & Budget",
                        subtitle: "Carry enough context without letting each request sprawl."
                    ) {
                        parameterRow(
                            icon: "text.bubble",
                            title: "Context Messages",
                            value: contextMessagesText,
                            description: "How many earlier turns travel with the next prompt."
                        ) {
                            HStack(spacing: HushSpacing.md) {
                                Slider(
                                    value: contextLimitSliderBinding,
                                    in: Double(Limits.contextMessages.lowerBound) ... Double(Limits.contextMessages.upperBound),
                                    step: 1
                                )
                                .accessibilityLabel("Context Messages")

                                numberField(
                                    value: contextLimitValueBinding,
                                    formatter: Self.contextLimitFormatter,
                                    title: "Context Messages"
                                )
                            }
                        }

                        sectionDivider

                        parameterRow(
                            icon: "text.alignleft",
                            title: "Max Tokens",
                            value: maxTokensText,
                            description: "Output budget cap for the next assistant reply."
                        ) {
                            HStack(spacing: HushSpacing.md) {
                                Slider(
                                    value: maxTokensSliderBinding,
                                    in: Double(Limits.maxTokens.lowerBound) ... Double(Limits.maxTokens.upperBound),
                                    step: 64
                                )
                                .accessibilityLabel("Max Tokens")

                                numberField(
                                    value: maxTokensValueBinding,
                                    formatter: Self.maxTokensFormatter,
                                    title: "Max Tokens"
                                )
                            }
                        }
                    }

                    configSection(
                        title: "Sampling",
                        subtitle: "Shape whether the next replies feel steady, broad, or exploratory."
                    ) {
                        parameterRow(
                            icon: "dial.medium",
                            title: "Temperature",
                            value: temperatureText,
                            description: "Lower is steadier. Higher allows more variation."
                        ) {
                            Slider(value: temperatureBinding, in: 0 ... 2, step: 0.05)
                                .accessibilityLabel("Temperature")
                        }

                        sectionDivider

                        parameterRow(
                            icon: "circle.lefthalf.filled",
                            title: "Top P",
                            value: topPText,
                            description: "Keep only the most likely probability mass."
                        ) {
                            Slider(value: topPBinding, in: 0 ... 1, step: 0.05)
                                .accessibilityLabel("Top P")
                        }

                        sectionDivider

                        parameterRow(
                            icon: "line.3.horizontal.decrease.circle",
                            title: "Top K",
                            value: topKText,
                            description: "Candidate cap. Set to 0 when you want it off."
                        ) {
                            Slider(value: topKBinding, in: 0 ... 100, step: 1)
                                .accessibilityLabel("Top K")
                        }
                    }

                    footerView
                }
                .padding(.vertical, HushSpacing.xs)
            }
        }
        .padding(HushSpacing.xl)
        .frame(width: Layout.drawerWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(popoverBackground)
        .shadow(color: palette.splitPaneShadow, radius: 18, x: -10, y: 0)
    }
}

private extension ChatConfigDrawer {
    private var headerView: some View {
        HStack(alignment: .top, spacing: HushSpacing.md) {
            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Chat Tuning")
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.primaryText)

                Text("Low-frequency controls for history and sampling, moved out of the composer.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: HushSpacing.xs) {
                if hasCustomizedVisibleParameters {
                    Button("Reset") {
                        resetVisibleParameters()
                    }
                    .buttonStyle(.plain)
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.controlForeground)
                    .padding(.horizontal, HushSpacing.sm)
                    .padding(.vertical, HushSpacing.xs + 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(palette.softFillStrong)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(palette.subtleStroke, lineWidth: 1)
                            )
                    )
                }

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.controlForegroundMuted)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(palette.softFillStrong)
                                .overlay(
                                    Circle()
                                        .stroke(palette.subtleStroke, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close chat tuning")
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: HushSpacing.sm) {
            summaryChip(title: "Context", value: "\(contextLimitValueBinding.wrappedValue)")
            summaryChip(title: "Temp", value: temperatureText)
            summaryChip(
                title: "Budget",
                value: maxTokensValueBinding.wrappedValue == 0
                    ? "∞"
                    : compactTokenCount(maxTokensValueBinding.wrappedValue)
            )
        }
    }

    private var footerView: some View {
        HStack(alignment: .center, spacing: HushSpacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.tertiaryText)

            Text("These controls affect upcoming requests. Model and reasoning stay in the composer.")
                .font(HushTypography.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.top, HushSpacing.xs)
    }

    private var popoverBackground: some View {
        RoundedRectangle(cornerRadius: Layout.panelCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        palette.cardBackground,
                        palette.composerBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.panelCornerRadius, style: .continuous)
                    .stroke(palette.splitPaneEdgeStroke, lineWidth: 1)
            )
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(palette.subtleStroke)
            .frame(height: 1)
            .opacity(0.7)
    }

    private func summaryChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(HushTypography.caption)
                .foregroundStyle(palette.secondaryText)

            Text(value)
                .font(HushTypography.captionBold)
                .monospacedDigit()
                .foregroundStyle(palette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, HushSpacing.md)
        .padding(.vertical, HushSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.accentMutedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(palette.accentMutedStroke, lineWidth: 1)
                )
        )
    }

    private func configSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.primaryText)

                Text(subtitle)
                    .font(HushTypography.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: HushSpacing.sm) {
                content()
            }
        }
        .padding(HushSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: Layout.sectionCornerRadius, style: .continuous)
                .fill(palette.softFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.sectionCornerRadius, style: .continuous)
                        .stroke(palette.subtleStroke, lineWidth: 1)
                )
        )
    }
}
