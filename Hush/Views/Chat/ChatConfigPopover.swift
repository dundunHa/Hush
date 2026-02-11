import SwiftUI

struct ChatConfigPopover: View {
    @Binding var parameters: ModelParameters

    private var contextLimitBinding: Binding<Double> {
        Binding(
            get: { Double(parameters.contextMessageLimit ?? ModelParameters.standard.contextMessageLimit ?? 10) },
            set: { parameters.contextMessageLimit = Int($0) }
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
                .foregroundStyle(.white)

            Divider()
                .background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: HushSpacing.md) {
                configRow(
                    title: "Context Messages",
                    value: "\(Int(contextLimitBinding.wrappedValue))"
                ) {
                    Slider(value: contextLimitBinding, in: 1 ... 100, step: 1)
                        .frame(width: 120)
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
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.16))
        )
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
                    .foregroundStyle(.white.opacity(0.9))
                Text(value)
                    .font(HushTypography.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            control()
        }
    }
}
