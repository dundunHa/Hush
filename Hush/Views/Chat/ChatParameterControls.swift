import Foundation
import SwiftUI

extension ChatConfigDrawer {
    var contextLimitValueBinding: Binding<Int> {
        Binding(
            get: {
                clampContextMessageLimit(
                    parameters.contextMessageLimit ?? ModelParameters.standard.contextMessageLimit ?? 10
                )
            },
            set: { parameters.contextMessageLimit = clampContextMessageLimit($0) }
        )
    }

    var contextLimitSliderBinding: Binding<Double> {
        Binding(
            get: { Double(contextLimitValueBinding.wrappedValue) },
            set: { contextLimitValueBinding.wrappedValue = Int($0.rounded()) }
        )
    }

    var temperatureBinding: Binding<Double> {
        Binding(
            get: { parameters.temperature },
            set: {
                parameters.useModelDefaults = false
                parameters.temperature = $0
            }
        )
    }

    var topPBinding: Binding<Double> {
        Binding(
            get: { parameters.topP },
            set: {
                parameters.useModelDefaults = false
                parameters.topP = $0
            }
        )
    }

    var topKBinding: Binding<Double> {
        Binding(
            get: { Double(parameters.topK ?? 0) },
            set: {
                parameters.useModelDefaults = false
                parameters.topK = $0 > 0 ? Int($0) : nil
            }
        )
    }

    var maxTokensValueBinding: Binding<Int> {
        Binding(
            get: { clampMaxTokens(parameters.maxTokens) },
            set: {
                parameters.useModelDefaults = false
                parameters.maxTokens = clampMaxTokens($0)
            }
        )
    }

    var maxTokensSliderBinding: Binding<Double> {
        Binding(
            get: { Double(maxTokensValueBinding.wrappedValue) },
            set: { maxTokensValueBinding.wrappedValue = Int($0.rounded()) }
        )
    }

    var hasCustomizedVisibleParameters: Bool {
        let standard = ModelParameters.standard
        let standardContext = standard.contextMessageLimit ?? 10

        return contextLimitValueBinding.wrappedValue != standardContext ||
            maxTokensValueBinding.wrappedValue != standard.maxTokens ||
            abs(parameters.temperature - standard.temperature) > 0.001 ||
            abs(parameters.topP - standard.topP) > 0.001 ||
            parameters.topK != standard.topK
    }

    var contextMessagesText: String {
        "\(contextLimitValueBinding.wrappedValue)"
    }

    var temperatureText: String {
        String(format: "%.2f", parameters.temperature)
    }

    var topPText: String {
        String(format: "%.2f", parameters.topP)
    }

    var topKText: String {
        parameters.topK.map(String.init) ?? "Off"
    }

    var maxTokensText: String {
        let value = maxTokensValueBinding.wrappedValue
        return value == 0 ? "Unlimited" : "\(value)"
    }

    func clampContextMessageLimit(_ value: Int) -> Int {
        min(max(value, Limits.contextMessages.lowerBound), Limits.contextMessages.upperBound)
    }

    func clampMaxTokens(_ value: Int) -> Int {
        min(max(value, Limits.maxTokens.lowerBound), Limits.maxTokens.upperBound)
    }

    func compactTokenCount(_ value: Int) -> String {
        guard value >= 1000 else { return "\(value)" }
        return String(format: "%.1fK", Double(value) / 1000)
    }

    func resetVisibleParameters() {
        let standard = ModelParameters.standard
        parameters.contextMessageLimit = standard.contextMessageLimit
        parameters.maxTokens = standard.maxTokens
        parameters.temperature = standard.temperature
        parameters.topP = standard.topP
        parameters.topK = standard.topK
    }

    func parameterRow<Control: View>(
        icon: String,
        title: String,
        value: String,
        description: String,
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
    }

    func valueBadge(_ value: String) -> some View {
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

    func numberField(
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
