import SwiftUI

struct DataSettingsView: View {
    @EnvironmentObject private var container: AppContainer

    @State private var stats: DataStats?
    @State private var isLoadingStats = true
    @State private var clearState: ClearState = .idle
    @State private var showDeleteConfirmation = false

    private enum ClearState: Equatable {
        case idle
        case clearing
        case done
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                Text("Data && Storage")
                    .font(HushTypography.pageTitle)

                storageSection
                dangerZoneSection
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, HushSpacing.xl)
            .padding(.vertical, HushSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await loadStats() }
    }

    // MARK: - Storage Section

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Storage")
                .font(HushTypography.heading)
                .foregroundStyle(HushColors.secondaryText)

            VStack(spacing: 0) {
                statRow(
                    icon: "internaldrive",
                    label: "Database Size",
                    value: formattedSize
                )

                Divider().overlay(HushColors.subtleStroke)

                statRow(
                    icon: "bubble.left.and.bubble.right",
                    label: "Conversations",
                    value: stats.map { "\($0.conversationCount)" }
                )

                Divider().overlay(HushColors.subtleStroke)

                statRow(
                    icon: "text.bubble",
                    label: "Messages",
                    value: stats.map { "\($0.messageCount)" }
                )
            }
            .cardStyle(
                background: HushColors.cardBackground,
                stroke: HushColors.subtleStroke
            )
        }
    }

    private func statRow(icon: String, label: String, value: String?) -> some View {
        HStack(spacing: HushSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(HushColors.secondaryText)
                .frame(width: 24)

            Text(label)
                .font(HushTypography.body)

            Spacer()

            if isLoadingStats {
                RoundedRectangle(cornerRadius: 4)
                    .fill(HushColors.secondaryText.opacity(0.18))
                    .frame(width: 56, height: 14)
            } else {
                Text(value ?? "0")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(HushColors.secondaryText)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, HushSpacing.lg)
        .padding(.vertical, HushSpacing.md)
    }

    // MARK: - Danger Zone

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Danger Zone")
                .font(HushTypography.heading)
                .foregroundStyle(HushColors.errorText)

            VStack(alignment: .leading, spacing: HushSpacing.md) {
                HStack(spacing: HushSpacing.md) {
                    VStack(alignment: .leading, spacing: HushSpacing.xs) {
                        Text("Clear All Chat History")
                            .font(HushTypography.body)

                        Text("Permanently delete all conversations and messages. This cannot be undone.")
                            .font(HushTypography.caption)
                            .foregroundStyle(HushColors.secondaryText)
                    }

                    Spacer()

                    clearButton
                }
            }
            .padding(HushSpacing.lg)
            .cardStyle(
                background: HushColors.cardBackground,
                stroke: Color.red.opacity(0.30)
            )
            .alert("Clear All Chat History?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    Task { await performClear() }
                }
            } message: {
                Text(
                    "All conversations and messages will be permanently deleted. This action cannot be undone."
                )
            }
        }
    }

    @ViewBuilder
    private var clearButton: some View {
        switch clearState {
        case .idle:
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Clear Data", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)

        case .clearing:
            HStack(spacing: HushSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("Clearing…")
                    .font(HushTypography.caption)
                    .foregroundStyle(HushColors.secondaryText)
            }

        case .done:
            Label("Cleared", systemImage: "checkmark.circle.fill")
                .font(HushTypography.caption)
                .foregroundStyle(HushColors.successText)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }

    // MARK: - Private

    private func loadStats() async {
        isLoadingStats = true
        let result = await container.fetchDataStats()
        withAnimation(.easeOut(duration: 0.25)) {
            stats = result
            isLoadingStats = false
        }
    }

    private func performClear() async {
        withAnimation(.easeInOut(duration: 0.2)) {
            clearState = .clearing
        }

        await container.deleteAllChatHistory()
        let result = await container.fetchDataStats()

        withAnimation(.easeInOut(duration: 0.3)) {
            stats = result
            clearState = .done
        }

        try? await Task.sleep(for: .seconds(2))

        withAnimation(.easeInOut(duration: 0.3)) {
            clearState = .idle
        }
    }

    private var formattedSize: String? {
        guard let stats else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(stats.databaseSizeBytes))
    }
}

#if DEBUG

    // MARK: - Previews

    #Preview("DataSettingsView — Empty State") {
        DataSettingsView()
            .environmentObject(AppContainer.makePreviewContainer())
    }

    #Preview("DataSettingsView — With Data") {
        DataSettingsView()
            .environmentObject(AppContainer.makePreviewContainerWithPersistence())
    }
#endif
