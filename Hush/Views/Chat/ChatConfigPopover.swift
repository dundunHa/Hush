import Foundation
import SwiftUI

struct ChatConfigPopover: View {
    @Binding var parameters: ModelParameters
    @Environment(\.hushThemePalette) private var palette

    private enum Limits {
        static let contextMessages = 1 ... 30
        static let maxTokens = 64 ... 8192
    }

    private enum Layout {
        static let popoverWidth: CGFloat = 420
        static let valueFieldWidth: CGFloat = 72
        static let cardCornerRadius: CGFloat = 18
        static let iconSize: CGFloat = 30
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
        return formatter
    }()

    private var contextLimitValueBinding: Binding<Int> {
        Binding(
            get: {
                clampContextMessageLimit(
                    parameters.contextMessageLimit ?? ModelParameters.standard.contextMessageLimit ?? 10
                )
            },
            set: { parameters.contextMessageLimit = clampContextMessageLimit($0) }
        )
    }

    private var contextLimitSliderBinding: Binding<Double> {
        Binding(
            get: { Double(contextLimitValueBinding.wrappedValue) },
            set: { contextLimitValueBinding.wrappedValue = Int($0.rounded()) }
        )
    }

    private var temperatureBinding: Binding<Double> {
        Binding(
            get: { parameters.temperature },
            set: {
                parameters.useModelDefaults = false
                parameters.temperature = $0
            }
        )
    }

    private var topPBinding: Binding<Double> {
        Binding(
            get: { parameters.topP },
            set: {
                parameters.useModelDefaults = false
                parameters.topP = $0
            }
        )
    }

    private var topKBinding: Binding<Double> {
        Binding(
            get: { Double(parameters.topK ?? 0) },
            set: {
                parameters.useModelDefaults = false
                parameters.topK = $0 > 0 ? Int($0) : nil
            }
        )
    }

    private var maxTokensValueBinding: Binding<Int> {
        Binding(
            get: { clampMaxTokens(parameters.maxTokens) },
            set: {
                parameters.useModelDefaults = false
                parameters.maxTokens = clampMaxTokens($0)
            }
        )
    }

    private var maxTokensSliderBinding: Binding<Double> {
        Binding(
            get: { Double(maxTokensValueBinding.wrappedValue) },
            set: { maxTokensValueBinding.wrappedValue = Int($0.rounded()) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HushSpacing.lg) {
            headerView
            summaryStrip

            configSection(
                title: "Context Window",
                subtitle: "Balance how much history is carried forward and how long the next reply can be."
            ) {
                parameterCard(
                    icon: "text.bubble",
                    title: "Context Messages",
                    value: contextMessagesText,
                    description: "How many earlier turns are sent with the next request."
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

                parameterCard(
                    icon: "text.alignleft",
                    title: "Max Tokens",
                    value: maxTokensText,
                    description: "Upper bound for generated output in the next reply."
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
                subtitle: "Tune whether responses feel steadier, broader, or more exploratory."
            ) {
                parameterCard(
                    icon: "dial.medium",
                    title: "Temperature",
                    value: temperatureText,
                    description: "Lower values are steadier. Higher values create more variation."
                ) {
                    Slider(value: temperatureBinding, in: 0 ... 2, step: 0.05)
                        .accessibilityLabel("Temperature")
                }

                parameterCard(
                    icon: "circle.lefthalf.filled",
                    title: "Top P",
                    value: topPText,
                    description: "Nucleus sampling keeps only the most likely probability mass."
                ) {
                    Slider(value: topPBinding, in: 0 ... 1, step: 0.05)
                        .accessibilityLabel("Top P")
                }

                parameterCard(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "Top K",
                    value: topKText,
                    description: "Candidate cap for token selection. Set it to 0 to turn it off."
                ) {
                    Slider(value: topKBinding, in: 0 ... 100, step: 1)
                        .accessibilityLabel("Top K")
                }
            }

            footerView
        }
        .padding(HushSpacing.xl)
        .frame(width: Layout.popoverWidth)
        .background(popoverBackground)
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: HushSpacing.xs) {
            Text("Chat Options")
                .font(HushTypography.heading)
                .foregroundStyle(palette.primaryText)

            Text("Adjust context and sampling before sending the next message.")
                .font(HushTypography.footnote)
                .foregroundStyle(palette.secondaryText)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: HushSpacing.sm) {
            summaryChip(title: "Context", value: "\(contextLimitValueBinding.wrappedValue)")
            summaryChip(title: "Temp", value: temperatureText)
            summaryChip(title: "Budget", value: compactTokenCount(maxTokensValueBinding.wrappedValue))
        }
    }

    private var footerView: some View {
        HStack(alignment: .center, spacing: HushSpacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.tertiaryText)

            Text("These controls affect upcoming requests. Model selection and reasoning strength stay separate.")
                .font(HushTypography.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.top, HushSpacing.xs)
    }

    private var popoverBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(palette.subtleStroke, lineWidth: 1)
            )
    }

    private var contextMessagesText: String {
        "\(contextLimitValueBinding.wrappedValue)"
    }

    private var temperatureText: String {
        String(format: "%.2f", parameters.temperature)
    }

    private var topPText: String {
        String(format: "%.2f", parameters.topP)
    }

    private var topKText: String {
        parameters.topK.map(String.init) ?? "Off"
    }

    private var maxTokensText: String {
        "\(maxTokensValueBinding.wrappedValue)"
    }

    private func clampContextMessageLimit(_ value: Int) -> Int {
        min(max(value, Limits.contextMessages.lowerBound), Limits.contextMessages.upperBound)
    }

    private func clampMaxTokens(_ value: Int) -> Int {
        min(max(value, Limits.maxTokens.lowerBound), Limits.maxTokens.upperBound)
    }

    private func compactTokenCount(_ value: Int) -> String {
        guard value >= 1000 else { return "\(value)" }
        return String(format: "%.1fK", Double(value) / 1000)
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
    }

    private func parameterCard<Control: View>(
        icon: String,
        title: String,
        value: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            HStack(alignment: .top, spacing: HushSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(palette.softFillStrong)
                        .overlay(
                            Circle()
                                .stroke(palette.subtleStroke, lineWidth: 1)
                        )

                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.controlForeground)
                }
                .frame(width: Layout.iconSize, height: Layout.iconSize)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(HushTypography.body.weight(.medium))
                        .foregroundStyle(palette.primaryText)

                    Text(description)
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: HushSpacing.md)

                valueBadge(value)
            }

            control()
        }
        .padding(HushSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .fill(palette.softFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                        .stroke(palette.subtleStroke, lineWidth: 1)
                )
        )
    }

    private func valueBadge(_ value: String) -> some View {
        Text(value)
            .font(HushTypography.captionBold)
            .monospacedDigit()
            .foregroundStyle(palette.primaryText)
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

    private func numberField(
        value: Binding<Int>,
        formatter: NumberFormatter,
        title: String
    ) -> some View {
        TextField("", value: value, formatter: formatter)
            .textFieldStyle(.plain)
            .font(HushTypography.footnote.weight(.semibold))
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.primaryText)
            .padding(.horizontal, HushSpacing.sm)
            .frame(width: Layout.valueFieldWidth, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(palette.softFillStrong)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(palette.subtleStroke, lineWidth: 1)
                    )
            )
            .accessibilityLabel(title)
    }
}
