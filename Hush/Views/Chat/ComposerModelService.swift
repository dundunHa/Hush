import Foundation

@MainActor
struct ComposerModelService {
    struct RefreshResult: Sendable {
        let models: [ModelDescriptor]
        let catalogStateMessage: String?
    }

    private let container: AppContainer
    private let surfaceStyle: ConversationSurfaceStyle

    init(container: AppContainer, surfaceStyle: ConversationSurfaceStyle) {
        self.container = container
        self.surfaceStyle = surfaceStyle
    }

    var enabledProviders: [ProviderConfiguration] {
        container.settings.providerConfigurations.filter(\.isEnabled)
    }

    var selectedProviderName: String {
        let displayName = enabledProviders.first(where: { $0.id == selectedProviderID })?.name ?? selectedProviderID
        if surfaceStyle == .quickBar {
            return displayName.isEmpty ? "Provider" : displayName
        }
        return displayName
    }

    func selectedModelDisplayName(models: [ModelDescriptor]) -> String {
        let displayName = models.first(where: { $0.id == selectedModelID })?.displayName ?? selectedModelID
        if surfaceStyle == .quickBar {
            return displayName.isEmpty ? "Model" : displayName
        }
        return displayName
    }

    func canSendDraft(draft: String) -> Bool {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty, !container.isQueueFull, container.hasConfiguredProvider else {
            return false
        }

        if surfaceStyle == .quickBar {
            return !selectedModelID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
        }

        return true
    }

    func modelsForMenu(availableModels: [ModelDescriptor]) -> [ModelDescriptor] {
        switch surfaceStyle {
        case .main:
            mainChatModelsForMenu(availableModels: availableModels)
        case .quickBar:
            quickBarModelsForMenu(availableModels: availableModels)
        }
    }

    func refreshAvailableModels() async -> RefreshResult {
        switch surfaceStyle {
        case .main:
            await refreshMainChatModels()
        case .quickBar:
            await refreshQuickBarModels()
        }
    }

    func fallbackModels() -> [ModelDescriptor] {
        var uniqueIDs: [String] = []
        for id in fallbackCandidateModelIDs() {
            guard !id.isEmpty, !uniqueIDs.contains(id) else { continue }
            uniqueIDs.append(id)
        }

        return uniqueIDs.map {
            ModelDescriptor(id: $0, displayName: $0, capabilities: [.text])
        }
    }

    private var selectedProviderID: String {
        switch surfaceStyle {
        case .main:
            container.settings.selectedProviderID
        case .quickBar:
            container.quickBarState.providerID
        }
    }

    private var selectedModelID: String {
        switch surfaceStyle {
        case .main:
            container.settings.selectedModelID
        case .quickBar:
            container.quickBarState.selectedModelID
        }
    }

    private var activeProviderConfiguration: ProviderConfiguration? {
        container.settings.providerConfigurations.first(where: { $0.id == selectedProviderID })
    }

    private func fallbackCandidateModelIDs() -> [String] {
        switch surfaceStyle {
        case .main:
            let providerDefaultModelID = activeProviderConfiguration?.defaultModelID ?? ""
            return [container.settings.selectedModelID, providerDefaultModelID]
        case .quickBar:
            return [
                container.quickBarState.selectedModelID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
                container.settings.selectedModelID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            ]
        }
    }

    private func updateSelectedModel(id: String) {
        switch surfaceStyle {
        case .main:
            container.settings.selectedModelID = id
        case .quickBar:
            container.selectQuickBarModel(id: id)
        }
    }

    private func mainChatModelsForMenu(availableModels: [ModelDescriptor]) -> [ModelDescriptor] {
        let baseModels = availableModels.isEmpty ? fallbackModels() : availableModels
        let pinnedIDs = activeProviderConfiguration?.pinnedModelIDs ?? []
        guard !pinnedIDs.isEmpty else { return baseModels }

        let pinnedModels = baseModels.filter { pinnedIDs.contains($0.id) }
        return pinnedModels.isEmpty ? baseModels : pinnedModels
    }

    private func quickBarModelsForMenu(availableModels: [ModelDescriptor]) -> [ModelDescriptor] {
        let baseModels = availableModels.isEmpty ? fallbackModels() : availableModels
        let textModels = baseModels.filter(isTextModel)
        return textModels.isEmpty ? fallbackModels() : textModels
    }

    private func isTextModel(_ model: ModelDescriptor) -> Bool {
        model.capabilities.contains(.text) || model.supportedOutputs.contains(.text)
    }

    private func refreshMainChatModels() async -> RefreshResult {
        let providerID = container.settings.selectedProviderID
        guard !providerID.isEmpty else {
            return RefreshResult(models: [], catalogStateMessage: nil)
        }

        let (models, _, error) = await container.availableModels(forProviderID: providerID)
        let resolvedModels: [ModelDescriptor]
        let message: String?

        if models.isEmpty {
            resolvedModels = fallbackModels()
            message = error
        } else {
            resolvedModels = models
            message = nil
        }

        if !resolvedModels.contains(where: { $0.id == container.settings.selectedModelID }),
           let firstModel = resolvedModels.first
        {
            updateSelectedModel(id: firstModel.id)
        }

        return RefreshResult(models: resolvedModels, catalogStateMessage: message)
    }

    private func refreshQuickBarModels() async -> RefreshResult {
        let providerID = container.quickBarState.providerID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !providerID.isEmpty else {
            return RefreshResult(models: fallbackModels(), catalogStateMessage: nil)
        }

        let (models, _, error) = await container.availableModels(forProviderID: providerID)
        let textModels = models.filter(isTextModel)
        let resolvedModels = textModels.isEmpty ? fallbackModels() : textModels

        if !resolvedModels.contains(where: { $0.id == container.quickBarState.selectedModelID }),
           let firstModel = resolvedModels.first
        {
            updateSelectedModel(id: firstModel.id)
        }

        return RefreshResult(models: resolvedModels, catalogStateMessage: error)
    }
}
