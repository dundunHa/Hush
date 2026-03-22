import Foundation
import SwiftUI

struct ChatConfigDrawer: View {
    @Binding var parameters: ModelParameters
    var onClose: () -> Void = {}
    @Environment(\.hushThemePalette) private var palette

    private enum Limits {
        static let contextMessages = 1 ... 30
        static let maxTokens = 0 ... 8192
    }

    private enum Layout {
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

    private var hasCustomizedVisibleParameters: Bool {
        let standard = ModelParameters.standard
        let standardContext = standard.contextMessageLimit ?? 10

        return contextLimitValueBinding.wrappedValue != standardContext ||
            maxTokensValueBinding.wrappedValue != standard.maxTokens ||
            abs(parameters.temperature - standard.temperature) > 0.001 ||
            abs(parameters.topP - standard.topP) > 0.001 ||
            parameters.topK != standard.topK
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HushSpacing.lg) {
            headerView
            summaryStrip
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: HushSpacing.md) {
                    configSection(title: "History & Budget") {
                        parameterRow(
                            icon: "text.bubble",
                            title: "Context Messages",
                            value: contextMessagesText
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
                            value: maxTokensText
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

                    configSection(title: "Sampling") {
                        parameterRow(
                            icon: "dial.medium",
                            title: "Temperature",
                            value: temperatureText
                        ) {
                            Slider(value: temperatureBinding, in: 0 ... 2, step: 0.05)
                                .accessibilityLabel("Temperature")
                        }

                        sectionDivider

                        parameterRow(
                            icon: "circle.lefthalf.filled",
                            title: "Top P",
                            value: topPText
                        ) {
                            Slider(value: topPBinding, in: 0 ... 1, step: 0.05)
                                .accessibilityLabel("Top P")
                        }

                        sectionDivider

                        parameterRow(
                            icon: "line.3.horizontal.decrease.circle",
                            title: "Top K",
                            value: topKText
                        ) {
                            Slider(value: topKBinding, in: 0 ... 100, step: 1)
                                .accessibilityLabel("Top K")
                        }
                    }
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
        HStack(alignment: .center, spacing: HushSpacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Chat Tuning")
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.primaryText)
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
            summaryChip(title: "Budget", value: maxTokensValueBinding.wrappedValue == 0 ? "∞" : compactTokenCount(maxTokensValueBinding.wrappedValue))
        }
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
        let value = maxTokensValueBinding.wrappedValue
        return value == 0 ? "Unlimited" : "\(value)"
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
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.primaryText)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                }
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

    private func parameterRow<Control: View>(
        icon: String,
        title: String,
        value: String,
        description: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: HushSpacing.sm) {
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

                VStack(alignment: .leading, spacing: description == nil ? 0 : 3) {
                    Text(title)
                        .font(HushTypography.body.weight(.medium))
                        .foregroundStyle(palette.primaryText)

                    if let description, !description.isEmpty {
                        Text(description)
                            .font(HushTypography.caption)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: HushSpacing.md)

                valueBadge(value)
            }

            control()
        }
    }

    private func resetVisibleParameters() {
        let standard = ModelParameters.standard
        parameters.contextMessageLimit = standard.contextMessageLimit
        parameters.maxTokens = standard.maxTokens
        parameters.temperature = standard.temperature
        parameters.topP = standard.topP
        parameters.topK = standard.topK
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
