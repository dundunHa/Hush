import AppKit
import SwiftUI

// swiftlint:disable type_body_length function_body_length file_length

struct ProviderSettingsView: View {
    @EnvironmentObject private var container: AppContainer

    @State private var editingProviderID: String?
    @State private var providerName: String = ""
    @State private var providerType: ProviderType = .custom
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
    @State private var isDefaultProvider: Bool = false

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
    }

    // MARK: - Helpers

    private func providerIcon(for type: ProviderType) -> String {
        switch type {
        case .openAI: "brain"
        case .anthropic: "sparkle"
        case .ollama: "desktopcomputer"
        case .custom: "server.rack"
        #if DEBUG
            case .mock: "ladybug"
        #endif
        }
    }

    private func providerAccent(for type: ProviderType) -> Color {
        switch type {
        case .openAI: .green
        case .anthropic: .orange
        case .ollama: .blue
        case .custom: .purple
        #if DEBUG
            case .mock: .gray
        #endif
        }
    }

    private var selectableProviderTypes: [ProviderType] {
        #if DEBUG
            ProviderType.allCases.filter { $0 != .mock }
        #else
            ProviderType.allCases
        #endif
    }

    private func defaultEndpointPlaceholder(for type: ProviderType) -> String {
        switch type {
        case .openAI:
            OpenAIProvider.defaultEndpoint
        case .anthropic:
            "https://api.anthropic.com/v1"
        case .ollama:
            "http://localhost:11434/v1"
        case .custom:
            "https://api.example.com/v1"
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
        case .anthropic:
            "Anthropic"
        case .ollama:
            "Ollama"
        case .custom:
            "Custom Provider"
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

                    Menu {
                        Button {
                            openProviderSettings(providerID: OpenAISettingsInput.providerID)
                        } label: {
                            Label("OpenAI", systemImage: providerIcon(for: .openAI))
                        }

                        Divider()

                        Button {
                            startNewProviderDraft(type: .custom)
                        } label: {
                            Label("Custom", systemImage: providerIcon(for: .custom))
                        }

                        Button {
                            startNewProviderDraft(type: .ollama)
                        } label: {
                            Label("Ollama", systemImage: providerIcon(for: .ollama))
                        }

                        Button {
                            startNewProviderDraft(type: .anthropic)
                        } label: {
                            Label("Anthropic", systemImage: providerIcon(for: .anthropic))
                        }
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

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
            icon: providerIcon(for: provider.type),
            accent: providerAccent(for: provider.type)
        ) {
            openProviderSettings(providerID: provider.id)
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
                type: .custom,
                endpoint: "",
                apiKeyEnvironmentVariable: "",
                defaultModelID: "",
                isEnabled: false
            )

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                providerHeader(config)
                connectionSection(config)

                if !isCreatingNew {
                    catalogRefreshSection(providerID: providerID)
                }

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

            if isCreatingNew {
                Picker("", selection: $providerType) {
                    ForEach(selectableProviderTypes) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 180)
            } else {
                Text(config.type.displayName)
                    .font(HushTypography.caption)
                    .foregroundStyle(HushColors.secondaryText)
                    .padding(.horizontal, HushSpacing.sm)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
    }

    private func connectionSection(_ config: ProviderConfiguration) -> some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Connection")
                .font(HushTypography.heading)
                .foregroundStyle(HushColors.secondaryText)

            Toggle("Enabled", isOn: $isEnabled)

            Toggle("Set as Default Provider", isOn: $isDefaultProvider)
                .disabled(!isEnabled)
                .onChange(of: isEnabled) { _, newValue in
                    if !newValue, isDefaultProvider {
                        isDefaultProvider = false
                    }
                }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Endpoint")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(HushColors.secondaryText)
                TextField(defaultEndpointPlaceholder(for: config.type), text: $endpoint)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Default Model")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(HushColors.secondaryText)
                TextField("model-id", text: $defaultModelID)
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
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }

    // MARK: - Catalog Refresh

    private func catalogRefreshSection(providerID: String) -> some View {
        let hasPersistedProfile = container.settings.providerConfigurations.contains(where: { $0.id == providerID })
        let allModels = container.cachedModels(forProviderID: providerID)
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
        let isRefreshing = container.catalogRefreshingProviderIDs.contains(providerID)

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
                    container.refreshCatalog(forProviderID: providerID)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing || !hasPersistedProfile)
            }

            if allModels.isEmpty {
                HStack(spacing: HushSpacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(HushColors.secondaryText)
                    Text(isRefreshing ? "Fetching models…" : (hasPersistedProfile ? "No models cached. Tap Refresh to fetch." : "Save this provider to enable model refresh."))
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
                                        togglePinnedModel(model.id)
                                    } label: {
                                        Image(systemName: isPinned ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isPinned ? HushColors.successText : HushColors.secondaryText)
                                            .frame(width: 20)
                                    }
                                    .buttonStyle(.plain)
                                    .help(isPinned ? "Unpin" : "Pin")

                                    Text(model.id)
                                        .font(HushTypography.body)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(model.modelType.rawValue)
                                        .font(HushTypography.caption)
                                        .foregroundStyle(HushColors.secondaryText)
                                        .padding(.horizontal, HushSpacing.sm)
                                        .padding(.vertical, 2)
                                        .background(Color.white.opacity(0.08), in: Capsule())

                                    Button {
                                        setDefaultModel(model.id)
                                    } label: {
                                        Image(systemName: isDefault ? "star.fill" : "star")
                                            .foregroundStyle(isDefault ? Color.yellow.opacity(0.9) : HushColors.secondaryText)
                                    }
                                    .buttonStyle(.plain)
                                    .help(isDefault ? "Default model" : "Set as default model")
                                }
                                .padding(.horizontal, HushSpacing.sm)
                                .padding(.vertical, HushSpacing.xs)

                                if model.id != filtered.last?.id {
                                    Divider()
                                        .foregroundStyle(HushColors.subtleStroke)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)

                    Text("\(allModels.count) models · \(pinnedModelIDs.count) pinned")
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

    private func loadDefaultsForNewProvider(type: ProviderType) {
        providerType = type
        providerName = defaultNewProviderName(for: type)
        endpoint = defaultEndpointPlaceholder(for: type)
        defaultModelID = ""
        pinnedModelIDs = []
        isEnabled = true
        isDefaultProvider = false
        hasStoredCredential = false
        modelSearchText = ""
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
            providerType = .custom
            endpoint = ""
            defaultModelID = ""
            pinnedModelIDs = []
            isEnabled = false
            hasStoredCredential = false
        }
        isDefaultProvider = container.settings.selectedProviderID == providerID
        modelSearchText = ""
        resetEditState()
    }

    private func resetEditState() {
        apiKey = ""
        isAPIKeyRevealed = false
        showDeleteConfirmation = false
        saveMessage = ""
        saveFailed = false
    }

    private func reconcileDefaultProvider(for providerID: String) {
        if isDefaultProvider, isEnabled {
            container.setDefaultProvider(id: providerID)
        } else if container.settings.selectedProviderID == providerID {
            container.selectDeterministicFallback()
        }
    }

    private func applyPostSave(providerID: String, keepOpen: Bool = false) {
        apiKey = ""
        isAPIKeyRevealed = false
        saveMessage = "Saved."
        saveFailed = false
        reconcileDefaultProvider(for: providerID)
        if keepOpen {
            editingProviderID = providerID
        } else {
            editingProviderID = nil
        }
    }

    private var apiKeyToSave: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveSettings() {
        guard let providerID = editingProviderID else { return }

        let normalizedDefaultModelID = defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPinnedModelIDs = normalizedModelIDs(
            pinnedModelIDs + (normalizedDefaultModelID.isEmpty ? [] : [normalizedDefaultModelID])
        )

        defaultModelID = normalizedDefaultModelID
        pinnedModelIDs = normalizedPinnedModelIDs

        if providerID == OpenAISettingsInput.providerID {
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
        } else {
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
    }
}

// swiftlint:enable type_body_length function_body_length

// MARK: - ProviderListRowView

private struct ProviderListRowView: View {
    let provider: ProviderConfiguration
    let isDefault: Bool
    let icon: String
    let accent: Color
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
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

                Text(provider.name)
                    .font(HushTypography.body)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                if isDefault {
                    Text("Default")
                        .font(HushTypography.caption)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }

                if provider.isEnabled {
                    Text("Enabled")
                        .font(HushTypography.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15), in: Capsule())
                } else {
                    Text("Disabled")
                        .font(HushTypography.caption)
                        .foregroundStyle(HushColors.secondaryText)
                        .padding(.horizontal, HushSpacing.sm)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        HushColors.secondaryText.opacity(isHovered ? 1.0 : 0.6)
                    )
            }
            .padding(.horizontal, HushSpacing.lg)
            .padding(.vertical, HushSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.06) : HushColors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                            .stroke(
                                isHovered ? Color.white.opacity(0.16) : HushColors.subtleStroke,
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
                icon: "brain",
                accent: .green,
                onTap: {}
            )
            ProviderListRowView(
                provider: ProviderConfiguration(
                    id: "custom",
                    name: "Custom Provider",
                    type: .custom,
                    endpoint: "https://api.example.com/v1",
                    apiKeyEnvironmentVariable: "",
                    defaultModelID: "model-1",
                    isEnabled: true
                ),
                isDefault: false,
                icon: "server.rack",
                accent: .purple,
                onTap: {}
            )
        }
        .padding()
    }
#endif
