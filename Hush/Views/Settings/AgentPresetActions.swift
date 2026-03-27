import SwiftUI

// MARK: - Action Bar

extension AgentSettingsView {
    func actionBar(presetID: String) -> some View {
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

    func refreshPresets() {
        presets = container.fetchAgentPresets()
    }

    func openNewPresetDraft() {
        let draftPreset = AgentPreset(name: "New Agent")
        resetDraftFields(from: draftPreset)
        editingPresetID = draftPreset.id
    }

    func loadSnapshotForPreset(_ presetID: String) {
        guard let preset = presets.first(where: { $0.id == presetID }) else { return }
        resetDraftFields(from: preset)
    }

    func resetDraftFields(from preset: AgentPreset) {
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

    func savePreset(id: String) {
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
