import SwiftUI

// MARK: - Action Bar

extension ProviderSettingsView {
    var isCurrentDefault: Bool {
        guard let providerID = selectedProviderID else { return false }
        return container.settings.selectedProviderID == providerID
    }

    var canBeDefault: Bool {
        isEnabled && !defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var deleteConfirmationTitle: String {
        if providerName.isEmpty, let selectedProviderID {
            return "Delete \(selectedProviderID)?"
        }
        return "Delete \(providerName.isEmpty ? "Provider" : providerName)?"
    }

    func actionBar(_: ProviderConfiguration) -> some View {
        HStack {
            if isBuiltInProvider {
                HStack(spacing: HushSpacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                    Text("Built-in provider cannot be removed.")
                        .font(HushTypography.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            } else if !isCreatingNew {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Provider", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Spacer()

            if !isCurrentDefault, canBeDefault {
                Toggle("Set as Default", isOn: $setAsDefault)
                    .toggleStyle(.checkbox)
                    .font(HushTypography.footnote)
                    .foregroundStyle(palette.secondaryText)
            } else if isCurrentDefault {
                HStack(spacing: HushSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.successText)
                    Text("Default")
                        .font(HushTypography.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }

            Button("Save") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Save / Delete

    func triggerRefreshFromForm(providerID: String) {
        if usesDraftRefresh(for: providerID) {
            let draftInput = ProviderCatalogDraftInput(
                providerID: providerID,
                type: providerType,
                endpoint: endpoint,
                apiKey: apiKeyToSave,
                persistedAPIKey: persistedConfig(for: providerID)?.apiKey
            )
            let signature = currentCatalogDraftSignature(providerID: providerID)

            draftCatalogSignature = signature
            draftCatalogModels = []
            isDraftCatalogRefreshing = true
            draftCatalogError = nil
            saveMessage = ""
            saveFailed = false

            Task {
                let result = await container.previewModels(for: draftInput)
                await MainActor.run {
                    guard draftCatalogSignature == signature else { return }
                    draftCatalogModels = result.models
                    draftCatalogError = result.error
                    isDraftCatalogRefreshing = false
                }
            }
            return
        }

        resetDraftCatalogState()
        container.refreshCatalog(forProviderID: providerID)
    }

    func resetEditState(preserveFeedback: Bool = false) {
        apiKey = ""
        isAPIKeyRevealed = false
        showDeleteConfirmation = false
        setAsDefault = false
        if !preserveFeedback {
            saveMessage = ""
            saveFailed = false
        }
        resetDraftCatalogState()
    }

    func completeSave(selecting target: ProviderEditorTarget) {
        if let providerID = target.providerID, setAsDefault {
            container.setDefaultProvider(id: providerID)
        }

        forceApplySelection(
            makeSelectionRequest(target: target, reloadIfSame: true),
            preserveFeedback: true
        )
        saveMessage = "Saved."
        saveFailed = false
    }

    func nextTargetAfterDeleting(providerID: String) -> ProviderEditorTarget? {
        let ids = providers.map(\.id)
        guard let currentIndex = ids.firstIndex(of: providerID) else {
            return preferredInitialTarget
        }

        if let nextID = ids[(currentIndex + 1)...].first(where: { $0 != providerID }) {
            return .existing(nextID)
        }

        if currentIndex > 0,
           let previousID = ids[..<currentIndex].last(where: { $0 != providerID })
        {
            return .existing(previousID)
        }

        return nil
    }

    func deleteCurrentProvider() {
        guard let providerID = selectedProviderID, providerID != OpenAISettingsInput.providerID else { return }

        let nextTarget = nextTargetAfterDeleting(providerID: providerID)
        container.removeProviderProfile(id: providerID)

        if let nextTarget {
            forceApplySelection(makeSelectionRequest(target: nextTarget))
        } else {
            clearSelection()
        }
    }

    func validateDefaultModel(_ modelID: String) -> Bool {
        guard !isEnabled || !modelID.isEmpty else {
            saveMessage = "Choose a default model from the catalog or enter one manually."
            saveFailed = true
            return false
        }
        return true
    }

    func saveOpenAIProviderSettings(
        providerID: String,
        normalizedDefaultModelID: String,
        normalizedPinnedModelIDs: [String]
    ) {
        do {
            let snapshot = try container.saveOpenAISettings(
                OpenAISettingsInput(
                    endpoint: endpoint,
                    defaultModelID: normalizedDefaultModelID,
                    isEnabled: isEnabled,
                    apiKey: apiKeyToSave
                )
            )

            if var openAIConfig = container.settings.providerConfigurations.first(where: { $0.id == providerID }) {
                openAIConfig.pinnedModelIDs = normalizedPinnedModelIDs
                container.saveProviderProfile(openAIConfig)
            }

            hasStoredCredential = snapshot.hasCredential
            completeSave(selecting: .existing(providerID))
        } catch let error as OpenAISettingsSaveError {
            saveMessage = error.errorDescription ?? "Failed to save provider settings."
            saveFailed = true
        } catch {
            saveMessage = error.localizedDescription
            saveFailed = true
        }
    }

    func saveCustomProviderSettings(
        providerID: String?,
        normalizedDefaultModelID: String,
        normalizedPinnedModelIDs: [String]
    ) {
        var config: ProviderConfiguration
        if isCreatingNew {
            let newID = "provider-\(UUID().uuidString.prefix(8))"
            config = ProviderConfiguration(
                id: newID,
                name: providerName,
                type: providerType,
                endpoint: endpoint,
                apiKeyEnvironmentVariable: "HUSH_API_KEY",
                defaultModelID: normalizedDefaultModelID,
                isEnabled: isEnabled,
                pinnedModelIDs: normalizedPinnedModelIDs
            )
        } else {
            guard let providerID,
                  var existing = container.settings.providerConfigurations.first(where: { $0.id == providerID })
            else {
                saveMessage = "Provider not found."
                saveFailed = true
                return
            }
            existing.name = providerName
            existing.endpoint = endpoint
            existing.defaultModelID = normalizedDefaultModelID
            existing.isEnabled = isEnabled
            existing.pinnedModelIDs = normalizedPinnedModelIDs
            config = existing
        }

        let keyToSave = apiKeyToSave
        if !keyToSave.isEmpty {
            config.apiKey = keyToSave
        }

        container.saveProviderProfile(config)
        hasStoredCredential = config.hasPersistedAPIKey
        completeSave(selecting: .existing(config.id))

        if config.isEnabled, hasStoredCredential {
            container.refreshCatalog(forProviderID: config.id)
        }
    }

    func saveSettings() {
        guard let selectedTarget else { return }

        let normalizedDefaultModelID = defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPinnedModelIDs = normalizedModelIDs(
            pinnedModelIDs + (normalizedDefaultModelID.isEmpty ? [] : [normalizedDefaultModelID])
        )

        guard validateDefaultModel(normalizedDefaultModelID) else { return }

        defaultModelID = normalizedDefaultModelID
        pinnedModelIDs = normalizedPinnedModelIDs

        switch selectedTarget {
        case let .existing(providerID) where providerID == OpenAISettingsInput.providerID:
            saveOpenAIProviderSettings(
                providerID: providerID,
                normalizedDefaultModelID: normalizedDefaultModelID,
                normalizedPinnedModelIDs: normalizedPinnedModelIDs
            )
        case let .existing(providerID):
            saveCustomProviderSettings(
                providerID: providerID,
                normalizedDefaultModelID: normalizedDefaultModelID,
                normalizedPinnedModelIDs: normalizedPinnedModelIDs
            )
        case .new:
            saveCustomProviderSettings(
                providerID: nil,
                normalizedDefaultModelID: normalizedDefaultModelID,
                normalizedPinnedModelIDs: normalizedPinnedModelIDs
            )
        }
    }

    // MARK: - Selection State

    func snapshotForTarget(_ target: ProviderEditorTarget) -> ProviderEditorSnapshot? {
        switch target {
        case .new:
            return ProviderEditorSnapshot(
                name: defaultNewProviderName(for: .openAI),
                type: .openAI,
                endpoint: defaultEndpointPlaceholder(for: .openAI),
                defaultModelID: "",
                pinnedModelIDs: [],
                isEnabled: true,
                hasStoredCredential: false
            )
        case let .existing(providerID):
            if providerID == OpenAISettingsInput.providerID {
                let snapshot = container.openAISettingsSnapshot()
                let config = container.settings.providerConfigurations.first(where: { $0.id == providerID })
                return ProviderEditorSnapshot(
                    name: config?.name ?? "OpenAI",
                    type: .openAI,
                    endpoint: snapshot.endpoint,
                    defaultModelID: snapshot.defaultModelID,
                    pinnedModelIDs: config?.pinnedModelIDs ?? [],
                    isEnabled: snapshot.isEnabled,
                    hasStoredCredential: snapshot.hasCredential
                )
            }

            guard let config = container.settings.providerConfigurations.first(where: { $0.id == providerID }) else {
                return nil
            }
            return ProviderEditorSnapshot(
                name: config.name,
                type: config.type,
                endpoint: config.endpoint,
                defaultModelID: config.defaultModelID,
                pinnedModelIDs: config.pinnedModelIDs,
                isEnabled: config.isEnabled,
                hasStoredCredential: config.hasPersistedAPIKey
            )
        }
    }

    func baseline(for snapshot: ProviderEditorSnapshot, target: ProviderEditorTarget) -> ProviderEditorBaseline {
        ProviderEditorBaseline(
            target: target,
            name: snapshot.name,
            type: snapshot.type,
            endpoint: snapshot.endpoint,
            defaultModelID: snapshot.defaultModelID,
            pinnedModelIDs: snapshot.pinnedModelIDs,
            isEnabled: snapshot.isEnabled,
            hasStoredCredential: snapshot.hasStoredCredential
        )
    }

    func applySnapshot(
        _ snapshot: ProviderEditorSnapshot,
        target: ProviderEditorTarget,
        preserveFeedback: Bool = false
    ) {
        selectedTarget = target
        providerName = snapshot.name
        providerType = snapshot.type
        endpoint = snapshot.endpoint
        defaultModelID = snapshot.defaultModelID
        pinnedModelIDs = snapshot.pinnedModelIDs
        isEnabled = snapshot.isEnabled
        hasStoredCredential = snapshot.hasStoredCredential
        editorBaseline = baseline(for: snapshot, target: target)
        modelSearchText = ""
        isAdvancedSectionExpanded = false
        resetEditState(preserveFeedback: preserveFeedback)
    }

    func forceApplySelection(
        _ request: ProviderEditorSelectionRequest,
        preserveFeedback: Bool = false
    ) {
        guard request.reloadIfSame || request.target != selectedTarget || editorBaseline == nil else {
            return
        }
        guard let snapshot = snapshotForTarget(request.target) else {
            clearSelection()
            return
        }
        applySnapshot(snapshot, target: request.target, preserveFeedback: preserveFeedback)
    }

    func requestSelection(_ request: ProviderEditorSelectionRequest) {
        guard request.reloadIfSame || request.target != selectedTarget else {
            return
        }

        if hasUnsavedChanges {
            pendingSelectionRequest = request
            showDiscardChangesConfirmation = true
            return
        }

        forceApplySelection(request)
    }

    func ensureInitialSelection() {
        guard selectedTarget == nil else { return }
        guard let preferredInitialTarget else { return }
        forceApplySelection(makeSelectionRequest(target: preferredInitialTarget))
    }

    func reconcileSelectionAfterProviderListChange() {
        guard let selectedTarget else {
            ensureInitialSelection()
            return
        }

        switch selectedTarget {
        case .new:
            return
        case let .existing(providerID):
            guard providers.contains(where: { $0.id == providerID }) else {
                if let preferredInitialTarget {
                    forceApplySelection(makeSelectionRequest(target: preferredInitialTarget))
                } else {
                    clearSelection()
                }
                return
            }
        }
    }

    func clearSelection() {
        selectedTarget = nil
        editorBaseline = nil
        providerName = ""
        providerType = .openAI
        endpoint = OpenAIProvider.defaultEndpoint
        defaultModelID = ""
        pinnedModelIDs = []
        isEnabled = false
        hasStoredCredential = false
        modelSearchText = ""
        isAdvancedSectionExpanded = false
        resetEditState()
    }

    var currentBaseline: ProviderEditorBaseline? {
        guard let selectedTarget else { return nil }
        return ProviderEditorBaseline(
            target: selectedTarget,
            name: providerName,
            type: providerType,
            endpoint: endpoint,
            defaultModelID: defaultModelID,
            pinnedModelIDs: pinnedModelIDs,
            isEnabled: isEnabled,
            hasStoredCredential: hasStoredCredential
        )
    }

    var hasUnsavedChanges: Bool {
        guard let currentBaseline, let editorBaseline else { return false }
        guard currentBaseline == editorBaseline else { return true }
        return !apiKeyToSave.isEmpty || setAsDefault
    }

    func discardUnsavedChangesAndContinue() {
        guard let pendingSelectionRequest else { return }
        forceApplySelection(pendingSelectionRequest)
        self.pendingSelectionRequest = nil
    }
}
