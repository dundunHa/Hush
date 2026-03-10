import SwiftUI

// swiftlint:disable type_body_length file_length

struct AgentSettingsView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.hushThemePalette) private var palette

    @State private var presets: [AgentPreset] = []
    @State private var editingPresetID: String?
    @State private var showDeleteConfirmation: Bool = false

    // Edit state
    @State private var presetName: String = ""
    @State private var systemPrompt: String = ""
    @State private var selectedProviderID: String = ""
    @State private var selectedModelID: String = ""
    @State private var temperature: Double = 0.7
    @State private var topP: Double = 1.0
    @State private var topKString: String = ""
    @State private var maxTokensString: String = "4096"
    @State private var thinkingBudgetString: String = ""
    @State private var presencePenalty: Double = 0.0
    @State private var frequencyPenalty: Double = 0.0
    @State private var isDefault: Bool = false

    private var enabledProviders: [ProviderConfiguration] {
        #if DEBUG
            container.settings.providerConfigurations.filter { $0.isEnabled && $0.type != .mock }
        #else
            container.settings.providerConfigurations.filter(\.isEnabled)
        #endif
    }

    private var availableModels: [String] {
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
                    emptyState
                } else {
                    VStack(spacing: HushSpacing.sm) {
                        ForEach(presets) { preset in
                            AgentPresetRow(
                                preset: preset,
                                subtitle: presetSubtitle(preset)
                            ) {
                                loadSnapshotForPreset(preset.id)
                                editingPresetID = preset.id
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, HushSpacing.xl)
            .padding(.vertical, HushSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        VStack(spacing: HushSpacing.md) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 40))
                .foregroundStyle(palette.secondaryText)

            Text("No Agent Presets")
                .font(HushTypography.heading)

            Text("Create presets to save your favorite AI configurations.")
                .font(HushTypography.body)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, HushSpacing.xl * 2)
    }

    private func presetSubtitle(_ preset: AgentPreset) -> String {
        let providerName = container.settings.providerConfigurations
            .first(where: { $0.id == preset.providerID })?.name ?? preset.providerID
        if !preset.modelID.isEmpty {
            return "\(providerName) / \(preset.modelID)"
        }
        return providerName
    }

    // MARK: - Detail Sheet

    private func presetDetailSheet(presetID: String) -> some View {
        VStack(spacing: 0) {
            presetHeader
                .padding(.horizontal, HushSpacing.xl)
                .padding(.top, HushSpacing.xl)
                .padding(.bottom, HushSpacing.lg)

            Divider()
                .foregroundStyle(palette.separator)

            HStack(alignment: .top, spacing: HushSpacing.lg) {
                leftColumn
                    .frame(width: 320)

                Divider()
                    .foregroundStyle(palette.separator)

                rightColumn
                    .frame(minWidth: 280)
            }
            .padding(.horizontal, HushSpacing.xl)
            .padding(.vertical, HushSpacing.lg)

            Spacer(minLength: 0)

            Divider()
                .foregroundStyle(palette.separator)

            actionBar(presetID: presetID)
                .padding(.horizontal, HushSpacing.xl)
                .padding(.vertical, HushSpacing.lg)
        }
        .frame(width: 720, height: 720)
        .background(palette.rootBackground)
    }

    private var presetHeader: some View {
        HStack(alignment: .center, spacing: HushSpacing.md) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "person.badge.key")
                    .font(.system(size: 20))
                    .foregroundStyle(.purple)
            }

            TextField("Agent Name", text: $presetName)
                .font(HushTypography.pageTitle)
                .textFieldStyle(.plain)
        }
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                providerModelSection
                thinkingSection
                systemPromptSection
            }
        }
    }

    private var providerModelSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Label("Provider & Model", systemImage: "cpu")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                Text("Select an API provider and one of its pinned models for this agent.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: HushSpacing.sm) {
                HStack {
                    Text("Provider")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 60, alignment: .leading)

                    Picker("", selection: $selectedProviderID) {
                        Text("None").tag("")
                        ForEach(enabledProviders) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onChange(of: selectedProviderID) { _, _ in
                        selectedModelID = ""
                    }
                }

                HStack {
                    Text("Model")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 60, alignment: .leading)

                    Picker("", selection: $selectedModelID) {
                        Text("None").tag("")
                        ForEach(availableModels, id: \.self) { modelID in
                            Text(modelID).tag(modelID)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(selectedProviderID.isEmpty)
                }
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    private var systemPromptSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Label("System Prompt", systemImage: "text.quote")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                Text("Instructions that define this agent's behavior and persona. Sent at the start of every conversation.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextEditor(text: $systemPrompt)
                .font(HushTypography.body)
                .scrollContentBackground(.hidden)
                .padding(HushSpacing.sm)
                .frame(minHeight: 200, maxHeight: 320)
                .background(palette.softFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.subtleStroke, lineWidth: 1)
                )
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                generationSection
                samplingSection
                penaltiesSection
            }
        }
    }

    private var generationSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Generation", systemImage: "slider.horizontal.3")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.secondaryText)

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Temperature")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(String(format: "%.1f", temperature))
                        .font(HushTypography.monospaced(12))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 2)
                        .background(palette.softFillStrong, in: RoundedRectangle(cornerRadius: 4))
                }
                Slider(value: $temperature, in: 0 ... 2, step: 0.1)
                    .controlSize(.small)
                Text("Controls randomness. Lower values produce more focused output, higher values increase creativity.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Max Tokens")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    TextField("4096", text: $maxTokensString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Text("Maximum number of tokens the model can generate in a single response.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    private var samplingSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Sampling", systemImage: "dial.low")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.secondaryText)

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Top P")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(String(format: "%.2f", topP))
                        .font(HushTypography.monospaced(12))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 2)
                        .background(palette.softFillStrong, in: RoundedRectangle(cornerRadius: 4))
                }
                Slider(value: $topP, in: 0 ... 1, step: 0.05)
                    .controlSize(.small)
                Text("Nucleus sampling. Only considers tokens within the top cumulative probability. Use with temperature.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Top K")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    TextField("Optional", text: $topKString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Text("Limits sampling to the K most likely tokens. Leave empty to disable.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    private var penaltiesSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Penalties", systemImage: "arrow.triangle.branch")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.secondaryText)

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Presence Penalty")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(String(format: "%.2f", presencePenalty))
                        .font(HushTypography.monospaced(12))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 2)
                        .background(palette.softFillStrong, in: RoundedRectangle(cornerRadius: 4))
                }
                Slider(value: $presencePenalty, in: 0 ... 2, step: 0.05)
                    .controlSize(.small)
                Text("Encourages the model to talk about new topics. Higher values reduce repetition of ideas.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Frequency Penalty")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Text(String(format: "%.2f", frequencyPenalty))
                        .font(HushTypography.monospaced(12))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 2)
                        .background(palette.softFillStrong, in: RoundedRectangle(cornerRadius: 4))
                }
                Slider(value: $frequencyPenalty, in: 0 ... 2, step: 0.05)
                    .controlSize(.small)
                Text("Penalizes tokens based on how often they appear. Higher values discourage word repetition.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Label("Thinking", systemImage: "brain")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.secondaryText)

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                HStack {
                    Text("Thinking Budget")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    TextField("Optional", text: $thinkingBudgetString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
                Text("Token budget for extended thinking models (e.g. o1, Claude 3.5). Leave empty if not supported.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    // MARK: - Action Bar

    private func actionBar(presetID: String) -> some View {
        let isExistingPreset = presets.contains(where: { $0.id == presetID })

        return HStack(spacing: HushSpacing.md) {
            if isExistingPreset {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .alert("Delete Agent Preset?", isPresented: $showDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        container.deleteAgentPreset(id: presetID)
                        editingPresetID = nil
                        refreshPresets()
                    }
                } message: {
                    Text("This preset will be permanently deleted.")
                }

                Divider()
                    .frame(height: 20)
                    .foregroundStyle(palette.separator)
            }

            Toggle("Default", isOn: $isDefault)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer()

            Button("Cancel") {
                editingPresetID = nil
            }
            .buttonStyle(.bordered)

            Button("Save") {
                savePreset(id: presetID)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func refreshPresets() {
        presets = container.fetchAgentPresets()
    }

    private func openNewPresetDraft() {
        let draftPreset = AgentPreset(name: "New Agent")
        resetDraftFields(from: draftPreset)
        editingPresetID = draftPreset.id
    }

    private func loadSnapshotForPreset(_ presetID: String) {
        guard let preset = presets.first(where: { $0.id == presetID }) else { return }
        resetDraftFields(from: preset)
    }

    private func resetDraftFields(from preset: AgentPreset) {
        presetName = preset.name
        systemPrompt = preset.systemPrompt
        selectedProviderID = preset.providerID
        selectedModelID = preset.modelID
        temperature = preset.temperature
        topP = preset.topP
        topKString = preset.topK.map { String($0) } ?? ""
        maxTokensString = String(preset.maxTokens)
        thinkingBudgetString = preset.thinkingBudget.map { String($0) } ?? ""
        presencePenalty = preset.presencePenalty
        frequencyPenalty = preset.frequencyPenalty
        isDefault = preset.isDefault
    }

    private func savePreset(id: String) {
        let existingPreset = presets.first(where: { $0.id == id })

        let topK = Int(topKString.trimmingCharacters(in: .whitespacesAndNewlines))
        let maxTokens = Int(maxTokensString.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 4096
        let thinkingBudget = Int(thinkingBudgetString.trimmingCharacters(in: .whitespacesAndNewlines))

        let updatedPreset = AgentPreset(
            id: id,
            name: presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Agent" : presetName,
            systemPrompt: systemPrompt,
            providerID: selectedProviderID,
            modelID: selectedModelID,
            temperature: temperature,
            topP: topP,
            topK: topK,
            maxTokens: maxTokens,
            thinkingBudget: thinkingBudget,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            isDefault: isDefault,
            createdAt: existingPreset?.createdAt ?? .now,
            updatedAt: .now
        )

        container.saveAgentPreset(updatedPreset)
        editingPresetID = nil
        refreshPresets()
    }
}

// swiftlint:enable type_body_length

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

// MARK: - AgentPresetRow

private struct AgentPresetRow: View {
    @Environment(\.hushThemePalette) private var palette
    let preset: AgentPreset
    let subtitle: String
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: HushSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(isHovered ? 0.20 : 0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "person.badge.key")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.purple)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.name)
                        .font(HushTypography.body)
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)

//                    if !subtitle.isEmpty {
//                        Text(subtitle)
//                            .font(HushTypography.caption)
//                            .foregroundStyle(palette.secondaryText)
//                            .lineLimit(1)
//                    }
                }

                Spacer()

                if preset.isDefault {
                    Text("Default")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 3)
                        .background(palette.accentMutedBackground, in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        palette.secondaryText.opacity(isHovered ? 1.0 : 0.6)
                    )
            }
            .padding(.horizontal, HushSpacing.lg)
            .padding(.vertical, HushSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                    .fill(isHovered ? palette.hoverFill : palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                            .stroke(
                                isHovered ? palette.hoverStroke : palette.subtleStroke,
                                lineWidth: 1
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#if DEBUG

    #Preview("AgentPresetRow") {
        VStack(spacing: HushSpacing.sm) {
            AgentPresetRow(
                preset: PreviewFixtures.agentPreset(isDefault: true),
                subtitle: "OpenAI / gpt-4o"
            ) {}

            AgentPresetRow(
                preset: PreviewFixtures.agentPreset(name: "Creative Writer"),
                subtitle: "Anthropic / claude-sonnet-4-20250514"
            ) {}
        }
        .padding(HushSpacing.lg)
        .frame(width: 600)
        .background(HushColors.palette(for: .dark).rootBackground)
    }

#endif
