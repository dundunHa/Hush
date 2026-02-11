import SwiftUI

struct QuickBarView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.dismiss) private var dismiss

    @State private var prompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Quick Bar")
                .font(.title3.bold())

            Text("Use this as an instant prompt launcher, then continue in the main chat window.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Ask anything...", text: $prompt)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Button("Close") {
                    dismiss()
                }
                Spacer()
                Button("Send") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
    }

    private func submit() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        container.quickBarSubmit(text)
        dismiss()
    }
}

