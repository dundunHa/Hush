import Foundation
import SwiftUI

struct ChatConfigPopover: View {
    @Binding var parameters: ModelParameters

    private enum Limits {
        static let contextMessages = 1 ... 30
    }

    private static let contextLimitFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = Limits.contextMessages.lowerBound as NSNumber
        formatter.maximum = Limits.contextMessages.upperBound as NSNumber
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

    private var topKBinding: Binding<Double> {
        Binding(
            get: { Double(parameters.topK ?? 0) },
            set: { parameters.topK = $0 > 0 ? Int($0) : nil }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HushSpacing.lg) {
            Text("Chat Configuration")
                .font(HushTypography.heading)
                .foregroundStyle(HushColors.primaryText)

            Divider()
                .background(HushColors.separator)

            VStack(alignment: .leading, spacing: HushSpacing.md) {
                configRow(
                    title: "Context Messages",
                    value: "\(contextLimitValueBinding.wrappedValue)"
                ) {
                    HStack(spacing: HushSpacing.sm) {
                        Slider(
                            value: contextLimitSliderBinding,
                            in: Double(Limits.contextMessages.lowerBound) ... Double(Limits.contextMessages.upperBound),
                            step: 1
                        )
                        .frame(width: 110)

                        TextField("", value: contextLimitValueBinding, formatter: Self.contextLimitFormatter)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.center)
                            .frame(width: 48)
                    }
                }

                configRow(
                    title: "Temperature",
                    value: String(format: "%.2f", parameters.temperature)
                ) {
                    Slider(value: $parameters.temperature, in: 0 ... 2, step: 0.05)
                        .frame(width: 120)
                }

                configRow(
                    title: "Top P",
                    value: String(format: "%.2f", parameters.topP)
                ) {
                    Slider(value: $parameters.topP, in: 0 ... 1, step: 0.05)
                        .frame(width: 120)
                }

                configRow(
                    title: "Top K",
                    value: parameters.topK.map { "\($0)" } ?? "Off"
                ) {
                    Slider(value: topKBinding, in: 0 ... 100, step: 1)
                        .frame(width: 120)
                }

                configRow(
                    title: "Max Tokens",
                    value: "\(parameters.maxTokens)"
                ) {
                    Stepper("", value: $parameters.maxTokens, in: 64 ... 8192, step: 64)
                        .labelsHidden()
                }
            }
        }
        .padding(HushSpacing.lg)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(HushColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(HushColors.subtleStroke, lineWidth: 1)
                )
        )
    }

    private func clampContextMessageLimit(_ value: Int) -> Int {
        min(max(value, Limits.contextMessages.lowerBound), Limits.contextMessages.upperBound)
    }

    private func configRow<Content: View>(
        title: String,
        value: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HushTypography.body)
                    .foregroundStyle(HushColors.primaryText)
                Text(value)
                    .font(HushTypography.caption)
                    .foregroundStyle(HushColors.secondaryText)
            }
            Spacer()
            control()
        }
    }
}
