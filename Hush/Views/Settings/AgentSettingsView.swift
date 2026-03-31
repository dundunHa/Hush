import SwiftUI

struct AgentSettingsView: View {
    @EnvironmentObject var container: AppContainer
    @Environment(\.hushThemePalette) var palette

    @State var presets: [AgentPreset] = []
    @State var editingPresetID: String?
    @State var showDeleteConfirmation: Bool = false

    @State var presetName: String = ""
    @State var systemPrompt: String = ""
    @State var selectedProviderID: String = ""
    @State var selectedModelID: String = ""
    @State var temperature: Double = 0.7
    @State var topP: Double = 1.0
    @State var topKString: String = ""
    @State var maxTokensString: String = "4096"
    @State var thinkingBudgetString: String = ""
    @State var presencePenalty: Double = 0.0
    @State var frequencyPenalty: Double = 0.0
    @State var isDefault: Bool = false

    var enabledProviders: [ProviderConfiguration] {
        #if DEBUG
            container.settings.providerConfigurations.filter { $0.isEnabled && $0.type != .mock }
        #else
            container.settings.providerConfigurations.filter(\.isEnabled)
        #endif
    }

    var availableModels: [String] {
        container.settings.providerConfigurations
            .first(where: { $0.id == selectedProviderID })?.pinnedModelIDs ?? []
    }

    var body: some View {
        presetListPane
            .onAppear { refreshPresets() }
            .sheet(isPresented: Binding(
                get: { editingPresetID != nil },
                set: { if !$0 { editingPresetID = nil } }
            )) {
                if let presetID = editingPresetID {
                    presetDetailSheet(presetID: presetID)
                }
            }
    }

    // MARK: - Preset List

    private var presetListPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                HStack {
                    Text("AI Agents")
                        .font(HushTypography.pageTitle)

                    Spacer()

                    Button {
                        openNewPresetDraft()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if presets.isEmpty {
                    EmptyStateView(
                        icon: "person.badge.key",
                        title: "No Agent Presets",
                        description: "Create presets to save your favorite AI configurations."
                    )
                } else {
                    VStack(spacing: HushSpacing.sm) {
                        ForEach(presets) { preset in
                            SettingsListRow(
                                icon: "person.badge.key",
                                iconColor: .purple,
                                title: preset.name,
                                trailingView: preset.isDefault ? AnyView(defaultBadge) : nil
                            ) {
                                loadSnapshotForPreset(preset.id)
                                editingPresetID = preset.id
                            }
                        }
                    }
                }
            }
            .settingsCenteredContentColumn()
        }
    }

    private var defaultBadge: some View {
        Text("Default")
            .font(HushTypography.caption)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, HushSpacing.sm)
            .padding(.vertical, 3)
            .background(palette.accentMutedBackground, in: Capsule())
    }
}

// MARK: - Previews

#if DEBUG

    #Preview("AgentSettingsView — Empty State") {
        let container = AppContainer.makePreviewContainer()
        return AgentSettingsView()
            .environmentObject(container)
            .frame(width: 800, height: 560)
    }

    #Preview("AgentSettingsView — With Data") {
        let dbManager = try? DatabaseManager.inMemory()
        let presetRepo = dbManager.map { GRDBAgentPresetRepository(dbManager: $0) }
        if let repo = presetRepo {
            try? repo.upsert(PreviewFixtures.agentPreset(isDefault: true))
            try? repo.upsert(PreviewFixtures.agentPreset(
                name: "Creative Writer",
                systemPrompt: "You are a creative writer. Help craft engaging stories.",
                temperature: 0.9
            ))
        }
        let container = AppContainer.makePreviewContainer(
            settings: .default,
            agentPresetRepository: presetRepo
        )
        return AgentSettingsView()
            .environmentObject(container)
            .frame(width: 800, height: 560)
    }

#endif
