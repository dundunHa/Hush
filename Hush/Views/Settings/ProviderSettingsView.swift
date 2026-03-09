import AppKit
import SwiftUI

// swiftlint:disable type_body_length function_body_length file_length

enum ProviderCatalogRefreshGate {
    static func usesDraftRefresh(
        persistedConfig: ProviderConfiguration?,
        draftType: ProviderType,
        draftEndpoint: String,
        pendingAPIKey: String
    ) -> Bool {
        guard let persistedConfig else { return true }
        guard draftType == persistedConfig.type else { return true }
        let draftNormalizedEndpoint = normalizedEndpoint(draftEndpoint, type: draftType)
        let persistedNormalizedEndpoint = normalizedEndpoint(
            persistedConfig.endpoint,
            type: persistedConfig.type
        )
        guard draftNormalizedEndpoint == persistedNormalizedEndpoint else {
            return true
        }
        return !pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func normalizedEndpoint(_ raw: String, type: ProviderType) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch type {
            case .openAI:
                return OpenAIProvider.defaultEndpoint
            #if DEBUG
                case .mock:
                    return "local://mock-provider"
            #endif
            }
        }
        return trimmed
    }
}

private struct ProviderCatalogDraftSignature: Equatable {
    let type: ProviderType
    let normalizedEndpoint: String
}

struct ProviderSettingsView: View {
    @EnvironmentObject private var container: AppContainer

    @State private var editingProviderID: String?
    @State private var providerName: String = ""
    @State private var providerType: ProviderType = .openAI
    @State private var endpoint: String = OpenAIProvider.defaultEndpoint
    @State private var defaultModelID: String = ""
    @State private var pinnedModelIDs: [String] = []
    @State private var isEnabled: Bool = false
    @State private var apiKey: String = ""
    @State private var isAPIKeyRevealed: Bool = false
    @State private var hasStoredCredential: Bool = false
    @State private var saveMessage: String = ""
    @State private var saveFailed: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var modelSearchText: String = ""
    @State private var draftCatalogModels: [ModelDescriptor] = []
    @State private var draftCatalogError: String?
    @State private var draftCatalogSignature: ProviderCatalogDraftSignature?
    @State private var isDraftCatalogRefreshing: Bool = false
    @State private var prefersManualDefaultModelEntry: Bool = false

    private var isCreatingNew: Bool {
        editingProviderID == "__new__"
    }

    private var providers: [ProviderConfiguration] {
        let openAIProviderID = OpenAISettingsInput.providerID
        #if DEBUG
            var configurations = container.settings.providerConfigurations.filter { $0.type != .mock }
        #else
            var configurations = container.settings.providerConfigurations
        #endif

        if !configurations.contains(where: { $0.id == openAIProviderID }) {
            configurations.insert(
                ProviderConfiguration(
                    id: openAIProviderID,
                    name: "OpenAI",
                    type: .openAI,
                    endpoint: OpenAIProvider.defaultEndpoint,
                    apiKeyEnvironmentVariable: "OPENAI_API_KEY",
                    defaultModelID: "",
                    isEnabled: false,
                    credentialRef: openAIProviderID
                ),
                at: 0
            )
        }

        return configurations
    }

    var body: some View {
        providerListPane
            .sheet(isPresented: Binding(
                get: { editingProviderID != nil },
                set: { if !$0 { editingProviderID = nil } }
            )) {
                if let providerID = editingProviderID {
                    providerDetailSheet(providerID: providerID)
                }
            }
            .themeRefreshAware()
    }

    // MARK: - Helpers

    private func providerIcon(for type: ProviderType) -> String {
        switch type {
        case .openAI: "brain"
        #if DEBUG
            case .mock: "ladybug"
        #endif
        }
    }

    private func providerAccent(for type: ProviderType) -> Color {
        switch type {
        case .openAI: .green
        #if DEBUG
            case .mock: .gray
        #endif
        }
    }

    private func defaultEndpointPlaceholder(for type: ProviderType) -> String {
        switch type {
        case .openAI:
            OpenAIProvider.defaultEndpoint
        #if DEBUG
            case .mock:
                "local://mock-provider"
        #endif
        }
    }

    private func defaultNewProviderName(for type: ProviderType) -> String {
        switch type {
        case .openAI:
            "OpenAI Compatible"
        #if DEBUG
            case .mock:
                "Local Mock"
        #endif
        }
    }

    private func normalizedModelIDs(_ modelIDs: [String]) -> [String] {
        var uniqueIDs: [String] = []
        for rawID in modelIDs {
            let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !uniqueIDs.contains(trimmed) else { continue }
            uniqueIDs.append(trimmed)
        }
        return uniqueIDs
    }

    private func currentCatalogDraftSignature() -> ProviderCatalogDraftSignature {
        ProviderCatalogDraftSignature(
            type: providerType,
            normalizedEndpoint: ProviderCatalogRefreshGate.normalizedEndpoint(endpoint, type: providerType)
        )
    }

    private func persistedConfig(for providerID: String) -> ProviderConfiguration? {
        container.settings.providerConfigurations.first(where: { $0.id == providerID })
    }

    private func usesDraftRefresh(for providerID: String) -> Bool {
        ProviderCatalogRefreshGate.usesDraftRefresh(
            persistedConfig: persistedConfig(for: providerID),
            draftType: providerType,
            draftEndpoint: endpoint,
            pendingAPIKey: apiKeyToSave
        )
    }

    private func shouldDisplayDraftCatalog() -> Bool {
        guard draftCatalogSignature == currentCatalogDraftSignature() else {
            return false
        }
        return isDraftCatalogRefreshing || draftCatalogError != nil || !draftCatalogModels.isEmpty
    }

    private func visibleCatalogModels(for providerID: String) -> [ModelDescriptor] {
        let models = shouldDisplayDraftCatalog()
            ? draftCatalogModels
            : container.cachedModels(forProviderID: providerID)
        return models.sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    private func visibleCatalogRefreshError(for providerID: String) -> String? {
        shouldDisplayDraftCatalog()
            ? draftCatalogError
            : container.catalogRefreshErrors[providerID]
    }

    private func isCatalogRefreshing(for providerID: String) -> Bool {
        shouldDisplayDraftCatalog()
            ? isDraftCatalogRefreshing
            : container.catalogRefreshingProviderIDs.contains(providerID)
    }

    private func resetDraftCatalogState() {
        draftCatalogModels = []
        draftCatalogError = nil
        draftCatalogSignature = nil
        isDraftCatalogRefreshing = false
    }

    private func normalizedDefaultModel(for provider: ProviderConfiguration) -> String {
        provider.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func providerHasCredential(_ provider: ProviderConfiguration) -> Bool {
        let credentialRef = container.normalizedCredentialRef(from: provider)
        return container.hasProviderCredential(forRef: credentialRef)
    }

    private func canSetProviderAsDefault(_ provider: ProviderConfiguration) -> Bool {
        provider.isEnabled && providerHasCredential(provider) && !normalizedDefaultModel(for: provider).isEmpty
    }

    private func providerStatusText(_ provider: ProviderConfiguration) -> String {
        if !provider.isEnabled {
            return "Disabled"
        }
        if !providerHasCredential(provider) {
            return "API key required"
        }
        let defaultModel = normalizedDefaultModel(for: provider)
        if defaultModel.isEmpty {
            return "Choose a default model in the catalog"
        }
        return defaultModel
    }

    private func providerBadgeText(_ provider: ProviderConfiguration) -> String? {
        guard container.settings.selectedProviderID != provider.id else { return nil }
        if !provider.isEnabled {
            return "Disabled"
        }
        if !providerHasCredential(provider) {
            return "Key Needed"
        }
        if normalizedDefaultModel(for: provider).isEmpty {
            return "Pick Model"
        }
        return nil
    }

    private func openProviderSettings(providerID: String) {
        loadSnapshotForProvider(providerID)
        editingProviderID = providerID
    }

    private func startNewProviderDraft(type: ProviderType) {
        loadDefaultsForNewProvider(type: type)
        editingProviderID = "__new__"
    }

    // MARK: - Provider List

    private var providerListPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                HStack {
                    Text("Providers")
                        .font(HushTypography.pageTitle)
                    Spacer()

                    Button {
                        startNewProviderDraft(type: .openAI)
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("Set the app default here after a provider has an API key and a default model.")
                    .font(HushTypography.footnote)
                    .foregroundStyle(HushColors.secondaryText)

                VStack(spacing: HushSpacing.sm) {
                    ForEach(providers) { provider in
                        providerListRow(provider)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, HushSpacing.xl)
            .padding(.vertical, HushSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func providerListRow(_ provider: ProviderConfiguration) -> some View {
        ProviderListRowView(
            provider: provider,
            isDefault: container.settings.selectedProviderID == provider.id,
            subtitle: providerStatusText(provider),
            badgeText: providerBadgeText(provider),
            canSetDefault: canSetProviderAsDefault(provider),
            icon: providerIcon(for: provider.type),
            accent: providerAccent(for: provider.type)
        ) {
            openProviderSettings(providerID: provider.id)
        } onSetDefault: {
            container.setDefaultProvider(id: provider.id)
        }
    }

    // MARK: - Provider Detail Sheet

    private func providerDetailSheet(providerID: String) -> some View {
        let config: ProviderConfiguration = isCreatingNew
            ? ProviderConfiguration(
                id: "__new__",
                name: providerName,
                type: providerType,
                endpoint: endpoint,
                apiKeyEnvironmentVariable: "HUSH_API_KEY",
                defaultModelID: defaultModelID,
                isEnabled: isEnabled,
                pinnedModelIDs: pinnedModelIDs
            )
            : providers.first(where: { $0.id == providerID })
            ?? ProviderConfiguration(
                id: providerID,
                name: "",
                type: .openAI,
                endpoint: "",
                apiKeyEnvironmentVariable: "",
                defaultModelID: "",
                isEnabled: false
            )

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                providerHeader(config)
                connectionSection(config)

                catalogRefreshSection(providerID: providerID)

                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(HushTypography.footnote)
                        .foregroundStyle(saveFailed ? HushColors.errorText : HushColors.successText)
                }

                actionBar(config)
            }
            .padding(.horizontal, HushSpacing.xl)
        }
        .contentMargins(.vertical, 40)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 580, height: 600)
        .background(HushColors.rootBackground)
    }

    private func providerHeader(_ config: ProviderConfiguration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: HushSpacing.sm) {
            Image(systemName: providerIcon(for: config.type))
                .font(.system(size: 22))
                .foregroundStyle(providerAccent(for: config.type))

            if config.id == OpenAISettingsInput.providerID {
                Text("OpenAI")
                    .font(HushTypography.pageTitle)
            } else {
                TextField("Provider Name", text: $providerName)
                    .font(HushTypography.pageTitle)
                    .textFieldStyle(.plain)
            }
        }
    }

    private func connectionSection(_ config: ProviderConfiguration) -> some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Connection")
                .font(HushTypography.heading)
                .foregroundStyle(HushColors.secondaryText)

            Toggle("Enabled", isOn: $isEnabled)

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Endpoint")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(HushColors.secondaryText)
                TextField(defaultEndpointPlaceholder(for: config.type), text: $endpoint)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("API Key")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(HushColors.secondaryText)
                HStack(spacing: HushSpacing.xs) {
                    if isAPIKeyRevealed {
                        TextField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        isAPIKeyRevealed.toggle()
                    } label: {
                        Image(systemName: isAPIKeyRevealed ? "eye.slash" : "eye")
                            .foregroundStyle(HushColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(isAPIKeyRevealed ? "Hide" : "Reveal")
                }

                if hasStoredCredential, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Saved in Keychain. Leave blank to keep the existing key.")
                        .font(HushTypography.footnote)
                        .foregroundStyle(HushColors.secondaryText)
                }
            }

            HStack(alignment: .top, spacing: HushSpacing.sm) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .foregroundStyle(HushColors.secondaryText)
                Text(
                    container.settings.selectedProviderID == config.id
                        ? "This provider is currently the default. Change the default provider from the list on the left."
                        : "Choose the default provider from the list after this provider has an API key and a default model."
                )
                .font(HushTypography.footnote)
                .foregroundStyle(HushColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }

    // MARK: - Catalog Refresh

    private func catalogRefreshSection(providerID: String) -> some View {
        let hasPersistedProfile = persistedConfig(for: providerID) != nil
        let allModels = visibleCatalogModels(for: providerID)
        let isRefreshing = isCatalogRefreshing(for: providerID)
        let refreshError = visibleCatalogRefreshError(for: providerID)
        let isDraftSource = shouldDisplayDraftCatalog()

        return VStack(alignment: .leading, spacing: HushSpacing.md) {
            HStack {
                Text("Model Catalog")
                    .font(HushTypography.heading)
                    .foregroundStyle(HushColors.secondaryText)

                Spacer()

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    triggerRefreshFromForm(providerID: providerID)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }

            HStack(spacing: HushSpacing.sm) {
                Image(systemName: defaultModelID.isEmpty ? "target" : "checkmark.circle.fill")
                    .foregroundStyle(defaultModelID.isEmpty ? HushColors.secondaryText : HushColors.successText)

                Text(
                    defaultModelID.isEmpty
                        ? "Choose one default model here before making this provider the app default."
                        : "Default model: \(defaultModelID)"
                )
                .font(HushTypography.body)
                .foregroundStyle(defaultModelID.isEmpty ? HushColors.secondaryText : .white)
                .lineLimit(1)

                Spacer()

                if !defaultModelID.isEmpty {
                    Button("Clear") {
                        defaultModelID = ""
                    }
                    .buttonStyle(.plain)
                    .font(HushTypography.footnote)
                }
            }
            .padding(.horizontal, HushSpacing.md)
            .padding(.vertical, HushSpacing.sm)
            .background(HushColors.rootBackground.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))

            if let refreshError {
                HStack(spacing: HushSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HushColors.errorText)
                    Text(refreshError)
                        .font(HushTypography.caption)
                        .foregroundStyle(HushColors.errorText)
                }
                .padding(.vertical, HushSpacing.xs)
            }

            if prefersManualDefaultModelEntry {
                VStack(alignment: .leading, spacing: HushSpacing.xs) {
                    HStack {
                        Text("Default Model ID")
                            .font(HushTypography.captionBold)
                            .foregroundStyle(HushColors.secondaryText)
                        Spacer()
                        Button("Use Catalog") {
                            prefersManualDefaultModelEntry = false
                        }
                        .buttonStyle(.plain)
                        .font(HushTypography.footnote)
                    }

                    TextField("model-id", text: $defaultModelID)
                        .textFieldStyle(.roundedBorder)

                    Text("Use manual entry only when the provider does not expose the model in the catalog.")
                        .font(HushTypography.footnote)
                        .foregroundStyle(HushColors.secondaryText)
                }
            } else {
                HStack {
                    Text("Select the default model directly in the catalog list.")
                        .font(HushTypography.footnote)
                        .foregroundStyle(HushColors.secondaryText)
                    Spacer()
                    Button("Model Missing? Enter ID") {
                        prefersManualDefaultModelEntry = true
                    }
                    .buttonStyle(.plain)
                    .font(HushTypography.footnote)
                }
            }

            if allModels.isEmpty {
                HStack(spacing: HushSpacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(HushColors.secondaryText)
                    Text(
                        isRefreshing
                            ? "Fetching models…"
                            : (isDraftSource
                                ? "No models returned for the current draft. Adjust API key or endpoint and refresh again."
                                : (hasPersistedProfile
                                    ? "No models cached. Tap Refresh to fetch."
                                    : "Refresh to fetch models for this draft before saving."))
                    )
                    .font(HushTypography.caption)
                    .foregroundStyle(HushColors.secondaryText)
                }
                .padding(.vertical, HushSpacing.sm)
            } else {
                VStack(alignment: .leading, spacing: HushSpacing.xs) {
                    TextField("Filter models…", text: $modelSearchText)
                        .textFieldStyle(.roundedBorder)

                    let filtered = modelSearchText.isEmpty
                        ? allModels
                        : allModels.filter { $0.id.localizedCaseInsensitiveContains(modelSearchText) }

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { model in
                                let isPinned = pinnedModelIDs.contains(model.id)
                                let isDefault = model.id == defaultModelID

                                HStack(spacing: HushSpacing.md) {
                                    Button {
                                        setDefaultModel(model.id)
                                    } label: {
                                        HStack(spacing: HushSpacing.md) {
                                            Image(systemName: isDefault ? "largecircle.fill.circle" : "circle")
                                                .foregroundStyle(isDefault ? HushColors.successText : HushColors.secondaryText)
                                                .frame(width: 20)

                                            Text(model.id)
                                                .font(HushTypography.body)
                                                .foregroundStyle(HushColors.primaryText)
                                                .lineLimit(1)

                                            Spacer()

                                            if model.modelType != .unknown {
                                                Text(model.modelType.rawValue)
                                                    .font(HushTypography.caption)
                                                    .foregroundStyle(HushColors.secondaryText)
                                                    .padding(.horizontal, HushSpacing.sm)
                                                    .padding(.vertical, 2)
                                                    .background(HushColors.softFillStrong, in: Capsule())
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .help(isDefault ? "Default model" : "Set as default model")

                                    Button {
                                        togglePinnedModel(model.id)
                                    } label: {
                                        Image(systemName: isPinned ? "pin.fill" : "pin")
                                            .foregroundStyle(isPinned ? HushColors.successText : HushColors.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                    .help(isPinned ? "Unpin" : "Pin")
                                }
                                .padding(.horizontal, HushSpacing.sm)
                                .padding(.vertical, HushSpacing.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isDefault ? HushColors.selectionFill : .clear)
                                )

                                if model.id != filtered.last?.id {
                                    Divider()
                                        .foregroundStyle(HushColors.subtleStroke)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)

                    Text("\(allModels.count) models · \(pinnedModelIDs.count) pinned · tap a row to set the default")
                        .font(HushTypography.footnote)
                        .foregroundStyle(HushColors.secondaryText)
                }
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }

    private func togglePinnedModel(_ modelID: String) {
        if pinnedModelIDs.contains(modelID) {
            pinnedModelIDs.removeAll { $0 == modelID }
            if defaultModelID == modelID {
                defaultModelID = ""
            }
        } else {
            pinnedModelIDs.append(modelID)
        }
    }

    private func setDefaultModel(_ modelID: String) {
        defaultModelID = modelID
        prefersManualDefaultModelEntry = false
        if !pinnedModelIDs.contains(modelID) {
            pinnedModelIDs.append(modelID)
        }
    }

    // MARK: - Action Bar

    private func actionBar(_ config: ProviderConfiguration) -> some View {
        HStack {
            if !isCreatingNew, config.id != OpenAISettingsInput.providerID {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Provider", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .alert(Text("Delete \(providerName.isEmpty ? config.name : providerName)?"), isPresented: $showDeleteConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        container.removeProviderProfile(id: config.id)
                        editingProviderID = nil
                    }
                } message: {
                    Text("This provider and its cached models will be removed.")
                }
            }

            Spacer()

            Button("Save") {
                saveSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Load / Save

    private func triggerRefreshFromForm(providerID: String) {
        if usesDraftRefresh(for: providerID) {
            let draftInput = ProviderCatalogDraftInput(
                providerID: providerID,
                type: providerType,
                endpoint: endpoint,
                apiKey: apiKeyToSave,
                credentialRef: container.normalizedCredentialRef(from: persistedConfig(for: providerID))
            )
            let signature = currentCatalogDraftSignature()

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
                    if !result.models.contains(where: { $0.id == defaultModelID }), !prefersManualDefaultModelEntry {
                        defaultModelID = ""
                    }
                }
            }
            return
        }

        resetDraftCatalogState()
        container.refreshCatalog(forProviderID: providerID)
    }

    private func loadDefaultsForNewProvider(type: ProviderType) {
        providerType = type
        providerName = defaultNewProviderName(for: type)
        endpoint = defaultEndpointPlaceholder(for: type)
        defaultModelID = ""
        pinnedModelIDs = []
        isEnabled = true
        hasStoredCredential = false
        modelSearchText = ""
        prefersManualDefaultModelEntry = false
        resetEditState()
    }

    private func loadSnapshotForProvider(_ providerID: String) {
        if providerID == OpenAISettingsInput.providerID {
            let snapshot = container.openAISettingsSnapshot()
            let config = container.settings.providerConfigurations.first(where: { $0.id == providerID })
            providerName = config?.name ?? "OpenAI"
            providerType = .openAI
            endpoint = snapshot.endpoint
            defaultModelID = snapshot.defaultModelID
            isEnabled = snapshot.isEnabled
            pinnedModelIDs = config?.pinnedModelIDs ?? []
            hasStoredCredential = snapshot.hasCredential
        } else if let config = container.settings.providerConfigurations.first(where: { $0.id == providerID }) {
            providerName = config.name
            providerType = config.type
            endpoint = config.endpoint
            defaultModelID = config.defaultModelID
            isEnabled = config.isEnabled
            pinnedModelIDs = config.pinnedModelIDs

            let credentialRef = container.normalizedCredentialRef(from: config)
            hasStoredCredential = container.hasProviderCredential(forRef: credentialRef)
        } else {
            providerName = ""
            providerType = .openAI
            endpoint = ""
            defaultModelID = ""
            pinnedModelIDs = []
            isEnabled = false
            hasStoredCredential = false
        }
        modelSearchText = ""
        prefersManualDefaultModelEntry = false
        resetEditState()
    }

    private func resetEditState() {
        apiKey = ""
        isAPIKeyRevealed = false
        showDeleteConfirmation = false
        saveMessage = ""
        saveFailed = false
        resetDraftCatalogState()
    }

    private func applyPostSave(providerID: String, keepOpen: Bool = false) {
        apiKey = ""
        isAPIKeyRevealed = false
        saveMessage = "Saved."
        saveFailed = false
        if keepOpen {
            editingProviderID = providerID
        } else {
            editingProviderID = nil
        }
    }

    private var apiKeyToSave: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateDefaultModel(_ modelID: String) -> Bool {
        guard !isEnabled || !modelID.isEmpty else {
            saveMessage = "Choose a default model from the catalog or enter one manually."
            saveFailed = true
            return false
        }
        return true
    }

    private func saveOpenAIProviderSettings(
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
            applyPostSave(providerID: providerID)
        } catch let error as OpenAISettingsSaveError {
            saveMessage = error.errorDescription ?? "Failed to save provider settings."
            saveFailed = true
        } catch {
            saveMessage = error.localizedDescription
            saveFailed = true
        }
    }

    private func saveCustomProviderSettings(
        providerID: String,
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
            guard var existing = container.settings.providerConfigurations.first(where: { $0.id == providerID }) else {
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

        let credentialRef = container.normalizedCredentialRef(from: config)
        let keyToSave = apiKeyToSave

        if !keyToSave.isEmpty {
            do {
                try container.saveProviderCredential(keyToSave, forRef: credentialRef)
            } catch {
                saveMessage = "Failed to save API key to Keychain."
                saveFailed = true
                return
            }
        }

        config.credentialRef = credentialRef
        container.saveProviderProfile(config)
        hasStoredCredential = container.hasProviderCredential(forRef: credentialRef)
        applyPostSave(providerID: config.id, keepOpen: isCreatingNew)

        if config.isEnabled, hasStoredCredential {
            container.refreshCatalog(forProviderID: config.id)
        }
    }

    private func saveSettings() {
        guard let providerID = editingProviderID else { return }

        let normalizedDefaultModelID = defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPinnedModelIDs = normalizedModelIDs(
            pinnedModelIDs + (normalizedDefaultModelID.isEmpty ? [] : [normalizedDefaultModelID])
        )

        guard validateDefaultModel(normalizedDefaultModelID) else { return }

        defaultModelID = normalizedDefaultModelID
        pinnedModelIDs = normalizedPinnedModelIDs

        if providerID == OpenAISettingsInput.providerID {
            saveOpenAIProviderSettings(
                providerID: providerID,
                normalizedDefaultModelID: normalizedDefaultModelID,
                normalizedPinnedModelIDs: normalizedPinnedModelIDs
            )
        } else {
            saveCustomProviderSettings(
                providerID: providerID,
                normalizedDefaultModelID: normalizedDefaultModelID,
                normalizedPinnedModelIDs: normalizedPinnedModelIDs
            )
        }
    }
}

// swiftlint:enable type_body_length function_body_length

// MARK: - ProviderListRowView

private struct ProviderListRowView: View {
    let provider: ProviderConfiguration
    let isDefault: Bool
    let subtitle: String
    let badgeText: String?
    let canSetDefault: Bool
    let icon: String
    let accent: Color
    let onTap: () -> Void
    let onSetDefault: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: HushSpacing.md) {
            Button(action: onTap) {
                HStack(spacing: HushSpacing.md) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(isHovered ? 0.20 : 0.12))
                            .frame(width: 36, height: 36)

                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(provider.name)
                            .font(HushTypography.body)
                            .foregroundStyle(HushColors.primaryText)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(HushTypography.caption)
                            .foregroundStyle(HushColors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(
                            HushColors.secondaryText.opacity(isHovered ? 1.0 : 0.6)
                        )
                }
            }
            .buttonStyle(.plain)

            if isDefault {
                Text("Default")
                    .font(HushTypography.caption)
                    .foregroundStyle(HushColors.accent)
                    .padding(.horizontal, HushSpacing.sm)
                    .padding(.vertical, 3)
                    .background(HushColors.accentMutedBackground, in: Capsule())
            } else if canSetDefault {
                Button("Make Default") {
                    onSetDefault()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if let badgeText {
                Text(badgeText)
                    .font(HushTypography.caption)
                    .foregroundStyle(HushColors.secondaryText)
                    .padding(.horizontal, HushSpacing.sm)
                    .padding(.vertical, 3)
                    .background(HushColors.softFill, in: Capsule())
            }
        }
        .padding(.horizontal, HushSpacing.lg)
        .padding(.vertical, HushSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                .fill(isHovered ? HushColors.hoverFill : HushColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                        .stroke(
                            isHovered ? HushColors.hoverStroke : HushColors.subtleStroke,
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .themeRefreshAware()
    }
}

#if DEBUG

    // MARK: - Previews

    #Preview("ProviderSettingsView — Empty State") {
        ProviderSettingsView()
            .environmentObject(AppContainer.makePreviewContainer())
    }

    #Preview("ProviderSettingsView — With Data") {
        let container = AppContainer.makePreviewContainer()
        let openAIConfig = ProviderConfiguration(
            id: "openai",
            name: "OpenAI",
            type: .openAI,
            endpoint: "https://api.openai.com/v1",
            apiKeyEnvironmentVariable: "OPENAI_API_KEY",
            defaultModelID: "gpt-4o",
            isEnabled: true
        )
        container.settings.providerConfigurations = [ProviderConfiguration.mockDefault(), openAIConfig]
        return ProviderSettingsView()
            .environmentObject(container)
    }

    #Preview("ProviderListRowView") {
        VStack(spacing: 8) {
            ProviderListRowView(
                provider: ProviderConfiguration(
                    id: "openai",
                    name: "OpenAI",
                    type: .openAI,
                    endpoint: "https://api.openai.com/v1",
                    apiKeyEnvironmentVariable: "",
                    defaultModelID: "gpt-4o",
                    isEnabled: true
                ),
                isDefault: true,
                subtitle: "gpt-4o",
                badgeText: nil,
                canSetDefault: true,
                icon: "brain",
                accent: .green,
                onTap: {},
                onSetDefault: {}
            )
            ProviderListRowView(
                provider: ProviderConfiguration(
                    id: "custom",
                    name: "Custom Provider",
                    type: .openAI,
                    endpoint: "https://api.example.com/v1",
                    apiKeyEnvironmentVariable: "",
                    defaultModelID: "model-1",
                    isEnabled: true
                ),
                isDefault: false,
                subtitle: "Choose a default model in the catalog",
                badgeText: "Pick Model",
                canSetDefault: false,
                icon: "brain",
                accent: .green,
                onTap: {},
                onSetDefault: {}
            )
        }
        .padding()
    }
#endif
