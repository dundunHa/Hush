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

enum ProviderCatalogSelectionLogic {
    static func filteredModels(
        _ models: [ModelDescriptor],
        searchText: String
    ) -> [ModelDescriptor] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return models }
        return models.filter { model in
            model.id.localizedCaseInsensitiveContains(trimmedSearch)
                || model.displayName.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    static func selectedCatalogModelIDs(
        from storedModelIDs: [String],
        catalogModels: [ModelDescriptor]
    ) -> [String] {
        let storedSelection = Set(normalizedModelIDs(storedModelIDs))
        return catalogModels.map(\.id).filter(storedSelection.contains)
    }

    static func selectingAllFilteredModels(
        currentSelection: [String],
        filteredModelIDs: [String]
    ) -> [String] {
        normalizedModelIDs(currentSelection + filteredModelIDs)
    }

    static func clearingCatalogSelection(
        currentSelection: [String],
        catalogModelIDs: [String]
    ) -> [String] {
        let catalogModelSet = Set(catalogModelIDs)
        return normalizedModelIDs(currentSelection.filter { !catalogModelSet.contains($0) })
    }

    static func defaultModelAfterCatalogSelectionChange(
        currentDefaultModelID: String,
        selectedCatalogModelIDs: [String],
        catalogModelIDs: [String]
    ) -> String {
        let normalizedDefault = currentDefaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDefault.isEmpty else { return "" }

        let catalogModelSet = Set(catalogModelIDs)
        guard catalogModelSet.contains(normalizedDefault) else {
            return normalizedDefault
        }

        return selectedCatalogModelIDs.contains(normalizedDefault) ? normalizedDefault : ""
    }

    static func isManualDefaultModelID(
        _ modelID: String,
        catalogModelIDs: [String]
    ) -> Bool {
        let normalizedDefault = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDefault.isEmpty else { return false }
        return !Set(catalogModelIDs).contains(normalizedDefault)
    }

    static func normalizedModelIDs(_ modelIDs: [String]) -> [String] {
        var uniqueIDs: [String] = []
        for rawID in modelIDs {
            let trimmed = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !uniqueIDs.contains(trimmed) else { continue }
            uniqueIDs.append(trimmed)
        }
        return uniqueIDs
    }
}

private enum ProviderEditorTarget: Equatable {
    case existing(String)
    case new

    var providerID: String? {
        switch self {
        case let .existing(providerID):
            return providerID
        case .new:
            return nil
        }
    }
}

private struct ProviderEditorSelectionRequest: Equatable {
    let target: ProviderEditorTarget
    let reloadIfSame: Bool
}

private struct ProviderEditorSnapshot: Equatable {
    let name: String
    let type: ProviderType
    let endpoint: String
    let defaultModelID: String
    let pinnedModelIDs: [String]
    let isEnabled: Bool
    let hasStoredCredential: Bool
}

private struct ProviderEditorBaseline: Equatable {
    let target: ProviderEditorTarget
    let name: String
    let type: ProviderType
    let endpoint: String
    let defaultModelID: String
    let pinnedModelIDs: [String]
    let isEnabled: Bool
    let hasStoredCredential: Bool
}

private enum ProviderSettingsLayout {
    static let wideThreshold: CGFloat = 980
    static let listPaneMinWidth: CGFloat = 320
    static let listPaneMaxWidth: CGFloat = 380
    static let listPaneWidthFraction: CGFloat = 0.28
    static let compactListMaxHeight: CGFloat = 280
    static let paneCornerRadius: CGFloat = 22
}

struct ProviderSettingsView: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.hushThemePalette) private var palette

    @State private var selectedTarget: ProviderEditorTarget?
    @State private var editorBaseline: ProviderEditorBaseline?
    @State private var pendingSelectionRequest: ProviderEditorSelectionRequest?

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
    @State private var showDiscardChangesConfirmation: Bool = false
    @State private var setAsDefault: Bool = false
    @State private var modelSearchText: String = ""
    @State private var draftCatalogModels: [ModelDescriptor] = []
    @State private var draftCatalogError: String?
    @State private var draftCatalogSignature: ProviderCatalogDraftSignature?
    @State private var isDraftCatalogRefreshing: Bool = false
    @State private var isAdvancedSectionExpanded: Bool = false

    private var isCreatingNew: Bool {
        selectedTarget == .new
    }

    private var selectedProviderID: String? {
        selectedTarget?.providerID
    }

    private var providerIDs: [String] {
        providers.map(\.id)
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
                    isEnabled: false
                ),
                at: 0
            )
        }

        return configurations
    }

    var body: some View {
        GeometryReader { proxy in
            let isWideLayout = proxy.size.width >= ProviderSettingsLayout.wideThreshold
            let listPaneWidth = min(
                max(
                    proxy.size.width * ProviderSettingsLayout.listPaneWidthFraction,
                    ProviderSettingsLayout.listPaneMinWidth
                ),
                ProviderSettingsLayout.listPaneMaxWidth
            )

            Group {
                if isWideLayout {
                    HStack(alignment: .top, spacing: HushSpacing.xl) {
                        providerListPanel
                            .frame(width: listPaneWidth)

                        detailPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    VStack(alignment: .leading, spacing: HushSpacing.lg) {
                        providerListPanel
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: ProviderSettingsLayout.compactListMaxHeight)

                        detailPane
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .padding(HushSpacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            ensureInitialSelection()
        }
        .onChange(of: providerIDs) { _, _ in
            reconcileSelectionAfterProviderListChange()
        }
        .alert("Discard unsaved changes?", isPresented: $showDiscardChangesConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingSelectionRequest = nil
            }
            Button("Discard Changes", role: .destructive) {
                discardUnsavedChangesAndContinue()
            }
        } message: {
            Text("Your current provider edits have not been saved.")
        }
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
        ProviderCatalogSelectionLogic.normalizedModelIDs(modelIDs)
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

    private func editorProviderID(for target: ProviderEditorTarget) -> String {
        switch target {
        case let .existing(providerID):
            return providerID
        case .new:
            return "__new__"
        }
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

    private var normalizedDraftDefaultModelID: String {
        defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func filteredCatalogModels(_ models: [ModelDescriptor]) -> [ModelDescriptor] {
        ProviderCatalogSelectionLogic.filteredModels(models, searchText: modelSearchText)
    }

    private func selectedCatalogModelIDs(for models: [ModelDescriptor]) -> [String] {
        ProviderCatalogSelectionLogic.selectedCatalogModelIDs(
            from: pinnedModelIDs,
            catalogModels: models
        )
    }

    private func catalogDefaultSelection(for models: [ModelDescriptor]) -> String {
        let selectedModelIDs = selectedCatalogModelIDs(for: models)
        return selectedModelIDs.contains(normalizedDraftDefaultModelID) ? normalizedDraftDefaultModelID : ""
    }

    private func isUsingManualDefaultModelID(for models: [ModelDescriptor]) -> Bool {
        ProviderCatalogSelectionLogic.isManualDefaultModelID(
            normalizedDraftDefaultModelID,
            catalogModelIDs: models.map(\.id)
        )
    }

    private func applyCatalogSelection(_ selectedModelIDs: [String], allModels: [ModelDescriptor]) {
        let normalizedSelection = normalizedModelIDs(selectedModelIDs)
        let reconciledDefaultModelID = ProviderCatalogSelectionLogic.defaultModelAfterCatalogSelectionChange(
            currentDefaultModelID: normalizedDraftDefaultModelID,
            selectedCatalogModelIDs: normalizedSelection,
            catalogModelIDs: allModels.map(\.id)
        )

        pinnedModelIDs = normalizedSelection
        defaultModelID = reconciledDefaultModelID
    }

    private func toggleSelectedCatalogModel(_ modelID: String, allModels: [ModelDescriptor]) {
        let currentSelection = selectedCatalogModelIDs(for: allModels)
        let nextSelection: [String]
        if currentSelection.contains(modelID) {
            nextSelection = currentSelection.filter { $0 != modelID }
        } else {
            nextSelection = currentSelection + [modelID]
        }
        applyCatalogSelection(nextSelection, allModels: allModels)
    }

    private func selectAllFilteredCatalogModels(
        filteredModels: [ModelDescriptor],
        allModels: [ModelDescriptor]
    ) {
        let nextSelection = ProviderCatalogSelectionLogic.selectingAllFilteredModels(
            currentSelection: selectedCatalogModelIDs(for: allModels),
            filteredModelIDs: filteredModels.map(\.id)
        )
        applyCatalogSelection(nextSelection, allModels: allModels)
    }

    private func clearSelectedCatalogModels(_ allModels: [ModelDescriptor]) {
        let nextSelection = ProviderCatalogSelectionLogic.clearingCatalogSelection(
            currentSelection: selectedCatalogModelIDs(for: allModels),
            catalogModelIDs: allModels.map(\.id)
        )
        applyCatalogSelection(nextSelection, allModels: allModels)
    }

    private func providerHasCredential(_ provider: ProviderConfiguration) -> Bool {
        provider.hasPersistedAPIKey
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

    private var preferredInitialTarget: ProviderEditorTarget? {
        if providers.contains(where: { $0.id == container.settings.selectedProviderID }) {
            return .existing(container.settings.selectedProviderID)
        }
        if let provider = providers.first {
            return .existing(provider.id)
        }
        return nil
    }

    private func makeSelectionRequest(
        target: ProviderEditorTarget,
        reloadIfSame: Bool = false
    ) -> ProviderEditorSelectionRequest {
        ProviderEditorSelectionRequest(target: target, reloadIfSame: reloadIfSame)
    }

    private func snapshotForTarget(_ target: ProviderEditorTarget) -> ProviderEditorSnapshot? {
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

    private func baseline(for snapshot: ProviderEditorSnapshot, target: ProviderEditorTarget) -> ProviderEditorBaseline {
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

    private func applySnapshot(
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

    private func forceApplySelection(
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

    private func requestSelection(_ request: ProviderEditorSelectionRequest) {
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

    private func ensureInitialSelection() {
        guard selectedTarget == nil else { return }
        guard let preferredInitialTarget else { return }
        forceApplySelection(makeSelectionRequest(target: preferredInitialTarget))
    }

    private func reconcileSelectionAfterProviderListChange() {
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

    private func clearSelection() {
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

    private var currentBaseline: ProviderEditorBaseline? {
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

    private var hasUnsavedChanges: Bool {
        guard let currentBaseline, let editorBaseline else { return false }
        guard currentBaseline == editorBaseline else { return true }
        return !apiKeyToSave.isEmpty || setAsDefault
    }

    private func discardUnsavedChangesAndContinue() {
        guard let pendingSelectionRequest else { return }
        forceApplySelection(pendingSelectionRequest)
        self.pendingSelectionRequest = nil
    }

    private func currentEditingConfiguration(for target: ProviderEditorTarget) -> ProviderConfiguration {
        switch target {
        case .new:
            return ProviderConfiguration(
                id: editorProviderID(for: target),
                name: providerName,
                type: providerType,
                endpoint: endpoint,
                apiKeyEnvironmentVariable: "HUSH_API_KEY",
                defaultModelID: defaultModelID,
                isEnabled: isEnabled,
                pinnedModelIDs: pinnedModelIDs
            )
        case let .existing(providerID):
            return providers.first(where: { $0.id == providerID })
                ?? ProviderConfiguration(
                    id: providerID,
                    name: providerName,
                    type: providerType,
                    endpoint: endpoint,
                    apiKeyEnvironmentVariable: "",
                    defaultModelID: defaultModelID,
                    isEnabled: isEnabled,
                    pinnedModelIDs: pinnedModelIDs
                )
        }
    }

    // MARK: - Layout

    private var providerListPanel: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            HStack {
                Text("Providers")
                    .font(HushTypography.pageTitle)

                Spacer()

                Button {
                    requestSelection(makeSelectionRequest(target: .new, reloadIfSame: true))
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Set the app default here after a provider has an API key and a default model.")
                .font(HushTypography.footnote)
                .foregroundStyle(palette.secondaryText)

            ScrollView {
                VStack(spacing: HushSpacing.sm) {
                    ForEach(providers) { provider in
                        providerListRow(provider)
                    }
                }
            }
        }
        .padding(HushSpacing.lg)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    private func providerListRow(_ provider: ProviderConfiguration) -> some View {
        ProviderListRowView(
            provider: provider,
            isSelected: selectedTarget == .existing(provider.id),
            isDefault: container.settings.selectedProviderID == provider.id,
            isBuiltIn: provider.id == OpenAISettingsInput.providerID,
            subtitle: providerStatusText(provider),
            badgeText: providerBadgeText(provider),
            canSetDefault: canSetProviderAsDefault(provider),
            icon: providerIcon(for: provider.type),
            accent: providerAccent(for: provider.type)
        ) {
            requestSelection(makeSelectionRequest(target: .existing(provider.id)))
        } onSetDefault: {
            container.setDefaultProvider(id: provider.id)
        }
    }

    private var detailPane: some View {
        Group {
            if let selectedTarget {
                providerDetailPane(target: selectedTarget)
            } else {
                emptyDetailPane
            }
        }
    }

    private var emptyDetailPane: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Select a provider")
                .font(HushTypography.heading)
                .foregroundStyle(palette.primaryText)

            Text("Choose a provider from the list or create a new one to configure credentials, models, and defaults.")
                .font(HushTypography.body)
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HushSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(detailPaneBackground)
    }

    private func providerDetailPane(target: ProviderEditorTarget) -> some View {
        let config = currentEditingConfiguration(for: target)
        let providerID = editorProviderID(for: target)

        return VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: HushSpacing.lg) {
                    providerHeader(config)
                    basicsSection(config)
                    modelsSection(providerID: providerID)
                    advancedSection
                }
                .padding(.horizontal, HushSpacing.xl)
            }
            .contentMargins(.vertical, 32)
            .scrollBounceBehavior(.basedOnSize)

            Divider()
                .foregroundStyle(palette.subtleStroke)

            VStack(spacing: HushSpacing.xs) {
                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(HushTypography.footnote)
                        .foregroundStyle(saveFailed ? palette.errorText : palette.successText)
                }

                actionBar(config)
            }
            .padding(.horizontal, HushSpacing.xl)
            .padding(.vertical, HushSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(detailPaneBackground)
        .alert(Text(deleteConfirmationTitle), isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteCurrentProvider()
            }
        } message: {
            Text("This provider and its cached models will be removed.")
        }
    }

    private var detailPaneBackground: some View {
        RoundedRectangle(cornerRadius: ProviderSettingsLayout.paneCornerRadius, style: .continuous)
            .fill(palette.rootBackground)
            .overlay(
                RoundedRectangle(cornerRadius: ProviderSettingsLayout.paneCornerRadius, style: .continuous)
                    .stroke(palette.subtleStroke, lineWidth: 1)
            )
    }

    private var isBuiltInProvider: Bool {
        selectedProviderID == OpenAISettingsInput.providerID
    }

    private func providerHeader(_ config: ProviderConfiguration) -> some View {
        HStack(alignment: .center, spacing: HushSpacing.md) {
            Image(systemName: providerIcon(for: config.type))
                .font(.system(size: 22))
                .foregroundStyle(providerAccent(for: config.type))

            VStack(alignment: .leading, spacing: 6) {
                Text(isBuiltInProvider ? "OpenAI" : (providerName.isEmpty ? "New Provider" : providerName))
                    .font(HushTypography.pageTitle)

                HStack(spacing: HushSpacing.xs) {
                    if isBuiltInProvider {
                        Label("Built-in", systemImage: "lock.fill")
                            .font(HushTypography.caption)
                            .foregroundStyle(palette.secondaryText)
                    }

                    if isCurrentDefault {
                        Text("Default")
                            .font(HushTypography.caption)
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, HushSpacing.sm)
                            .padding(.vertical, 3)
                            .background(palette.accentMutedBackground, in: Capsule())
                    }
                }
            }

            Spacer()
        }
    }

    private func basicsSection(_ config: ProviderConfiguration) -> some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            HStack(alignment: .center) {
                Text("Basics")
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.secondaryText)

                Spacer()

                Toggle("Enabled", isOn: $isEnabled)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Title")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                if isBuiltInProvider {
                    Text(config.name)
                        .font(HushTypography.body)
                        .foregroundStyle(palette.primaryText)
                        .padding(.horizontal, HushSpacing.md)
                        .padding(.vertical, HushSpacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(palette.softFill)
                        )
                } else {
                    TextField("Provider name", text: $providerName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("Endpoint")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                TextField(defaultEndpointPlaceholder(for: config.type), text: $endpoint)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text("API Key")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

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
                            .foregroundStyle(palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .help(isAPIKeyRevealed ? "Hide" : "Reveal")
                }

                if hasStoredCredential, apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Saved locally. Leave blank to keep the existing key.")
                        .font(HushTypography.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    // MARK: - Models

    private func modelsSection(providerID: String) -> some View {
        let hasPersistedProfile = persistedConfig(for: providerID) != nil
        let allModels = visibleCatalogModels(for: providerID)
        let filteredModels = filteredCatalogModels(allModels)
        let selectedModelIDs = selectedCatalogModelIDs(for: allModels)
        let isRefreshing = isCatalogRefreshing(for: providerID)
        let refreshError = visibleCatalogRefreshError(for: providerID)
        let isDraftSource = shouldDisplayDraftCatalog()
        let hasFilteredModels = !filteredModels.isEmpty
        let areAllFilteredModelsSelected = !filteredModels.isEmpty
            && Set(filteredModels.map(\.id)).isSubset(of: Set(selectedModelIDs))
        let defaultModelSelection = catalogDefaultSelection(for: allModels)
        let usingManualDefaultModelID = isUsingManualDefaultModelID(for: allModels)
        let selectedSummary = "\(selectedModelIDs.count) selected / \(allModels.count) available"

        return VStack(alignment: .leading, spacing: HushSpacing.md) {
            HStack {
                Text("Models")
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.secondaryText)

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

            VStack(alignment: .leading, spacing: HushSpacing.sm) {
                HStack {
                    Text("Default Model")
                        .font(HushTypography.captionBold)
                        .foregroundStyle(palette.secondaryText)

                    Spacer()

                    Text(selectedSummary)
                        .font(HushTypography.footnote)
                        .foregroundStyle(palette.secondaryText)
                }

                Picker(
                    selectedModelIDs.isEmpty
                        ? "Select models below first"
                        : "Choose a default model",
                    selection: Binding(
                        get: { defaultModelSelection },
                        set: { defaultModelID = $0 }
                    )
                ) {
                    Text(selectedModelIDs.isEmpty ? "Select models below first" : "Choose a default model")
                        .tag("")

                    ForEach(selectedModelIDs, id: \.self) { modelID in
                        Text(modelID).tag(modelID)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(selectedModelIDs.isEmpty)

                if defaultModelSelection.isEmpty, !normalizedDraftDefaultModelID.isEmpty, usingManualDefaultModelID {
                    HStack(spacing: HushSpacing.xs) {
                        Image(systemName: "number.square")
                            .foregroundStyle(palette.secondaryText)
                        Text("Manual default model ID: \(normalizedDraftDefaultModelID)")
                            .font(HushTypography.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                } else if normalizedDraftDefaultModelID.isEmpty {
                    HStack(spacing: HushSpacing.xs) {
                        Image(systemName: isEnabled ? "exclamationmark.triangle.fill" : "info.circle")
                            .foregroundStyle(isEnabled ? palette.errorText : palette.secondaryText)
                        Text(
                            isEnabled
                                ? "Enabled providers need a default model."
                                : "Pick a default model from the selected models or enter one manually in Advanced."
                        )
                        .font(HushTypography.footnote)
                        .foregroundStyle(isEnabled ? palette.errorText : palette.secondaryText)
                    }
                } else {
                    HStack(spacing: HushSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.successText)
                        Text("Default model: \(normalizedDraftDefaultModelID)")
                            .font(HushTypography.footnote)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
            }

            if let refreshError {
                HStack(spacing: HushSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.errorText)
                    Text(refreshError)
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.errorText)
                }
                .padding(.vertical, HushSpacing.xs)
            }

            VStack(alignment: .leading, spacing: HushSpacing.sm) {
                Text("Model Catalog")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.secondaryText)

                TextField("Search models...", text: $modelSearchText)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: HushSpacing.sm) {
                    Button(modelSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Select All" : "Select All Filtered") {
                        selectAllFilteredCatalogModels(filteredModels: filteredModels, allModels: allModels)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!hasFilteredModels || areAllFilteredModelsSelected)

                    Button("Clear Selection") {
                        clearSelectedCatalogModels(allModels)
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedModelIDs.isEmpty)
                }
            }

            if allModels.isEmpty {
                HStack(spacing: HushSpacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(palette.secondaryText)
                    Text(
                        isRefreshing
                            ? "Fetching models..."
                            : (isDraftSource
                                ? "No models returned for the current draft. Adjust the basics and refresh again."
                                : (hasPersistedProfile
                                    ? "No models cached. Tap Refresh to fetch."
                                    : "Refresh to fetch models for this draft before saving."))
                    )
                    .font(HushTypography.caption)
                    .foregroundStyle(palette.secondaryText)
                }
                .padding(.vertical, HushSpacing.sm)
            } else {
                VStack(alignment: .leading, spacing: HushSpacing.xs) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredModels) { model in
                                let isSelected = selectedModelIDs.contains(model.id)

                                HStack(spacing: HushSpacing.md) {
                                    Button {
                                        toggleSelectedCatalogModel(model.id, allModels: allModels)
                                    } label: {
                                        HStack(spacing: HushSpacing.md) {
                                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(isSelected ? palette.successText : palette.secondaryText)
                                                .frame(width: 20)

                                            Text(model.id)
                                                .font(HushTypography.body)
                                                .foregroundStyle(palette.primaryText)
                                                .lineLimit(1)

                                            Spacer()

                                            if model.modelType != .unknown {
                                                Text(model.modelType.rawValue)
                                                    .font(HushTypography.caption)
                                                    .foregroundStyle(palette.secondaryText)
                                                    .padding(.horizontal, HushSpacing.sm)
                                                    .padding(.vertical, 2)
                                                    .background(palette.softFillStrong, in: Capsule())
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .help(isSelected ? "Remove from selected models" : "Add to selected models")
                                }
                                .padding(.horizontal, HushSpacing.sm)
                                .padding(.vertical, HushSpacing.xs)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? palette.selectionFill : .clear)
                                )

                                if model.id != filteredModels.last?.id {
                                    Divider()
                                        .foregroundStyle(palette.subtleStroke)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 280)

                    if filteredModels.isEmpty {
                        Text("No models match the current search.")
                            .font(HushTypography.footnote)
                            .foregroundStyle(palette.secondaryText)
                            .padding(.vertical, HushSpacing.xs)
                    }

                    Text("\(selectedModelIDs.count) selected models · search does not change saved selection")
                        .font(HushTypography.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $isAdvancedSectionExpanded) {
            VStack(alignment: .leading, spacing: HushSpacing.md) {
                VStack(alignment: .leading, spacing: HushSpacing.xs) {
                    Text("Manual Model ID")
                        .font(HushTypography.captionBold)
                        .foregroundStyle(palette.secondaryText)

                    TextField("model-id", text: $defaultModelID)
                        .textFieldStyle(.roundedBorder)

                    Text("Use this only when the provider does not expose the default model in the catalog. Typing here overrides the catalog picker.")
                        .font(HushTypography.footnote)
                        .foregroundStyle(palette.secondaryText)
                }
            }
            .padding(.top, HushSpacing.md)
        } label: {
            HStack {
                Text("Advanced")
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.secondaryText)

                Spacer()

                if isUsingManualDefaultModelID(for: visibleCatalogModels(for: editorProviderID(for: selectedTarget ?? .new))) {
                    Text("Manual Default")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
        .padding(HushSpacing.lg)
        .cardStyle(
            background: palette.cardBackground,
            stroke: palette.subtleStroke
        )
    }

    // MARK: - Action Bar

    private var isCurrentDefault: Bool {
        guard let providerID = selectedProviderID else { return false }
        return container.settings.selectedProviderID == providerID
    }

    private var canBeDefault: Bool {
        isEnabled && !defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var deleteConfirmationTitle: String {
        if providerName.isEmpty, let selectedProviderID {
            return "Delete \(selectedProviderID)?"
        }
        return "Delete \(providerName.isEmpty ? "Provider" : providerName)?"
    }

    private func actionBar(_: ProviderConfiguration) -> some View {
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

    // MARK: - Load / Save

    private func triggerRefreshFromForm(providerID: String) {
        if usesDraftRefresh(for: providerID) {
            let draftInput = ProviderCatalogDraftInput(
                providerID: providerID,
                type: providerType,
                endpoint: endpoint,
                apiKey: apiKeyToSave,
                persistedAPIKey: persistedConfig(for: providerID)?.apiKey
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
                }
            }
            return
        }

        resetDraftCatalogState()
        container.refreshCatalog(forProviderID: providerID)
    }

    private func resetEditState(preserveFeedback: Bool = false) {
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

    private func completeSave(selecting target: ProviderEditorTarget) {
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

    private func nextTargetAfterDeleting(providerID: String) -> ProviderEditorTarget? {
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

    private func deleteCurrentProvider() {
        guard let providerID = selectedProviderID, providerID != OpenAISettingsInput.providerID else { return }

        let nextTarget = nextTargetAfterDeleting(providerID: providerID)
        container.removeProviderProfile(id: providerID)

        if let nextTarget {
            forceApplySelection(makeSelectionRequest(target: nextTarget))
        } else {
            clearSelection()
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
            completeSave(selecting: .existing(providerID))
        } catch let error as OpenAISettingsSaveError {
            saveMessage = error.errorDescription ?? "Failed to save provider settings."
            saveFailed = true
        } catch {
            saveMessage = error.localizedDescription
            saveFailed = true
        }
    }

    private func saveCustomProviderSettings(
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

    private func saveSettings() {
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
}

// swiftlint:enable type_body_length function_body_length

// MARK: - ProviderListRowView

private struct ProviderListRowView: View {
    @Environment(\.hushThemePalette) private var palette
    let provider: ProviderConfiguration
    let isSelected: Bool
    let isDefault: Bool
    let isBuiltIn: Bool
    let subtitle: String
    let badgeText: String?
    let canSetDefault: Bool
    let icon: String
    let accent: Color
    let onTap: () -> Void
    let onSetDefault: () -> Void

    @State private var isHovered: Bool = false

    private var backgroundFill: Color {
        if isSelected {
            return palette.selectionFill
        }
        if isHovered {
            return palette.hoverFill
        }
        return palette.cardBackground
    }

    private var borderColor: Color {
        if isSelected {
            return palette.selectionStroke
        }
        if isHovered {
            return palette.hoverStroke
        }
        return palette.subtleStroke
    }

    @ViewBuilder
    private var builtInMarker: some View {
        if isBuiltIn {
            Image(systemName: "lock.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.secondaryText)
                .padding(6)
                .background(palette.softFill, in: Circle())
                .help("Built-in provider")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        if isDefault {
            Text("Default")
                .font(HushTypography.caption)
                .foregroundStyle(palette.accent)
                .padding(.horizontal, HushSpacing.sm)
                .padding(.vertical, 3)
                .background(palette.accentMutedBackground, in: Capsule())
        } else if canSetDefault {
            Button("Set Default") {
                onSetDefault()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        } else if let badgeText {
            Text(badgeText)
                .font(HushTypography.caption)
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, HushSpacing.sm)
                .padding(.vertical, 3)
                .background(palette.softFill, in: Capsule())
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: HushSpacing.md) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(isSelected ? 0.22 : (isHovered ? 0.20 : 0.12)))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: HushSpacing.xs) {
                    HStack(spacing: HushSpacing.xs) {
                        Text(provider.name)
                            .font(HushTypography.body)
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        builtInMarker

                        Spacer(minLength: 0)
                    }

                    Text(subtitle)
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    statusRow
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, HushSpacing.lg)
            .padding(.vertical, HushSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                    .fill(backgroundFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: HushSpacing.cardCornerRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .frame(width: 960, height: 640)
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
                isSelected: true,
                isDefault: true,
                isBuiltIn: true,
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
                isSelected: false,
                isDefault: false,
                isBuiltIn: false,
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
