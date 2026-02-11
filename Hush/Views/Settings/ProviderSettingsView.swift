import AppKit
import SwiftUI

// swiftlint:disable type_body_length function_body_length file_length

struct ProviderSettingsView: View {
    @EnvironmentObject private var container: AppContainer

    @State private var editingProviderID: String?
    @State private var providerName: String = ""
    @State private var endpoint: String = OpenAIProvider.defaultEndpoint
    @State private var defaultModelID: String = ""
    @State private var isEnabled: Bool = false
    @State private var apiKey: String = ""
    @State private var originalAPIKey: String = ""
    @State private var isAPIKeyRevealed: Bool = false
    @State private var saveMessage: String = ""
    @State private var saveFailed: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var modelSearchText: String = ""
    @State private var isDefaultProvider: Bool = false

    private var isCreatingNew: Bool {
        editingProviderID == "__new__"
    }

    private var providers: [ProviderConfiguration] {
        #if DEBUG
            container.settings.providerConfigurations.filter { $0.type != .mock }
        #else
            container.settings.providerConfigurations
        #endif
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

    // MARK: - Provider List

    private var providerListPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HushSpacing.lg) {
                HStack {
                    Text("Providers")
                        .font(HushTypography.pageTitle)
                    Spacer()

                    Button {
                        loadDefaultsForNewProvider()
                        editingProviderID = "__new__"
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
            loadSnapshotForProvider(provider.id)
            editingProviderID = provider.id
        }
    }

    // MARK: - Provider Detail Sheet

    private func providerDetailSheet(providerID: String) -> some View {
        let config: ProviderConfiguration = isCreatingNew
            ? ProviderConfiguration(
                id: "__new__",
                name: providerName,
                type: .custom,
                endpoint: endpoint,
                apiKeyEnvironmentVariable: "HUSH_API_KEY",
                defaultModelID: defaultModelID,
                isEnabled: isEnabled
            )
            : container.settings.providerConfigurations.first(where: { $0.id == providerID })
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

            TextField("Provider Name", text: $providerName)
                .font(HushTypography.pageTitle)
                .textFieldStyle(.plain)

            Text(config.type.displayName)
                .font(HushTypography.caption)
                .foregroundStyle(HushColors.secondaryText)
                .padding(.horizontal, HushSpacing.sm)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08), in: Capsule())
        }
    }

    private func connectionSection(_: ProviderConfiguration) -> some View {
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
                TextField("https://api.openai.com/v1", text: $endpoint)
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
        let config = container.settings.providerConfigurations.first(where: { $0.id == providerID })
        let pinnedIDs = config?.pinnedModelIDs ?? []
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
                .disabled(isRefreshing)
            }

            if allModels.isEmpty {
                HStack(spacing: HushSpacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(HushColors.secondaryText)
                    Text(isRefreshing ? "Fetching models…" : "No models cached. Tap Refresh to fetch.")
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
                                let isPinned = pinnedIDs.contains(model.id)
                                Button {
                                    togglePinnedModel(model.id, providerID: providerID)
                                } label: {
                                    HStack(spacing: HushSpacing.md) {
                                        Image(systemName: isPinned ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(isPinned ? HushColors.successText : HushColors.secondaryText)
                                            .frame(width: 20)

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
                                    }
                                    .padding(.horizontal, HushSpacing.sm)
                                    .padding(.vertical, HushSpacing.xs)
                                }
                                .buttonStyle(.plain)

                                if model.id != filtered.last?.id {
                                    Divider()
                                        .foregroundStyle(HushColors.subtleStroke)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)

                    Text("\(allModels.count) models · \(pinnedIDs.count) pinned")
                        .font(HushTypography.footnote)
                        .foregroundStyle(HushColors.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Default Model")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(HushColors.secondaryText)

                Picker("", selection: $defaultModelID) {
                    Text("None").tag("")
                    ForEach(pinnedIDs, id: \.self) { modelID in
                        Text(modelID).tag(modelID)
                    }
                }
                .labelsHidden()
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: HushColors.cardBackground,
            stroke: HushColors.subtleStroke
        )
    }

    private func togglePinnedModel(_ modelID: String, providerID: String) {
        guard var config = container.settings.providerConfigurations.first(where: { $0.id == providerID }) else { return }
        if config.pinnedModelIDs.contains(modelID) {
            config.pinnedModelIDs.removeAll { $0 == modelID }
        } else {
            config.pinnedModelIDs.append(modelID)
        }
        container.saveProviderProfile(config)
    }

    // MARK: - Action Bar

    private func actionBar(_ config: ProviderConfiguration) -> some View {
        HStack {
            if config.type == .custom {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Provider", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .alert(Text("Delete \(config.name)?"), isPresented: $showDeleteConfirmation) {
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

    private func loadDefaultsForNewProvider() {
        providerName = "Custom Provider"
        endpoint = "https://api.example.com/v1"
        defaultModelID = ""
        isEnabled = true
        isDefaultProvider = false
        resetEditState(credential: "")
    }

    private func loadSnapshotForProvider(_ providerID: String) {
        var credentialRef = ""
        if providerID == OpenAISettingsInput.providerID {
            let snapshot = container.openAISettingsSnapshot()
            providerName = container.settings.providerConfigurations.first(where: { $0.id == providerID })?.name ?? ""
            endpoint = snapshot.endpoint
            defaultModelID = snapshot.defaultModelID
            isEnabled = snapshot.isEnabled
            credentialRef = providerID
        } else if let config = container.settings.providerConfigurations.first(where: { $0.id == providerID }) {
            providerName = config.name
            endpoint = config.endpoint
            defaultModelID = config.defaultModelID
            isEnabled = config.isEnabled
            credentialRef = container.normalizedCredentialRef(from: config)
        }
        isDefaultProvider = container.settings.selectedProviderID == providerID
        let credential = container.readProviderCredential(forRef: credentialRef) ?? ""
        resetEditState(credential: credential)
    }

    private func resetEditState(credential: String) {
        apiKey = credential
        originalAPIKey = credential
        isAPIKeyRevealed = false
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
        saveFailed = false
        reconcileDefaultProvider(for: providerID)
        if keepOpen {
            editingProviderID = providerID
        } else {
            editingProviderID = nil
        }
    }

    private var changedAPIKey: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == originalAPIKey ? "" : trimmed
    }

    private func saveSettings() {
        guard let providerID = editingProviderID else { return }

        if providerID == OpenAISettingsInput.providerID {
            do {
                _ = try container.saveOpenAISettings(
                    OpenAISettingsInput(
                        endpoint: endpoint,
                        defaultModelID: defaultModelID,
                        isEnabled: isEnabled,
                        apiKey: changedAPIKey
                    )
                )
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
                    type: .custom,
                    endpoint: endpoint,
                    apiKeyEnvironmentVariable: "HUSH_API_KEY",
                    defaultModelID: defaultModelID,
                    isEnabled: isEnabled
                )
            } else {
                guard var existing = container.settings.providerConfigurations.first(where: { $0.id == providerID }) else {
                    saveMessage = "Provider not found."
                    saveFailed = true
                    return
                }
                existing.name = providerName
                existing.endpoint = endpoint
                existing.defaultModelID = defaultModelID
                existing.isEnabled = isEnabled
                config = existing
            }

            let credentialRef = container.normalizedCredentialRef(from: config)
            let keyToSave = changedAPIKey

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
            applyPostSave(providerID: config.id, keepOpen: isCreatingNew)
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
