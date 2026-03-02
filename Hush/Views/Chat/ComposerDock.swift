import SwiftUI

struct ComposerDock: View {
    @EnvironmentObject private var container: AppContainer
    @State private var draft: String = ""
    @State private var availableModels: [ModelDescriptor] = []
    @State private var catalogStateMessage: String?
    @State private var isModelHovered = false
    @State private var isStrengthHovered = false
    @State private var isConfigHovered = false
    @State private var showConfigPopover = false
    @State private var isOpenSettingsHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            if container.hasConfiguredProvider {
                composerEditor

                HStack(alignment: .center, spacing: HushSpacing.sm) {
                    Button {} label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.white.opacity(0.70))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add context")

                    modelMenu
                    thinkingStrengthMenu
                    configButton

                    Spacer(minLength: 0)

                    Button {} label: {
                        Image(systemName: "mic")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                            .frame(width: 25, height: 25)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voice input")

                    sendOrStopButton
                }

                if let catalogStateMessage, !catalogStateMessage.isEmpty {
                    Text(catalogStateMessage)
                        .font(HushTypography.caption)
                        .foregroundStyle(HushColors.errorText)
                }
            } else {
                noProviderConfiguredView
            }
        }
        .padding(.horizontal, HushSpacing.xl)
        .padding(.vertical, HushSpacing.md)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.17, blue: 0.21),
                            Color(red: 0.13, green: 0.14, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 1)
                )
        }
        .frame(maxWidth: HushSpacing.chatContentMaxWidth)
        .padding(.horizontal, HushSpacing.xl)
        .padding(.top, HushSpacing.sm)
        .padding(.bottom, HushSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .center)
        .task(id: container.settings.selectedProviderID) {
            guard container.hasConfiguredProvider else { return }
            await refreshAvailableModels()
        }
    }

    private var composerEditor: some View {
        TextEditor(text: $draft)
            .font(HushTypography.body)
            .foregroundStyle(.primary)
            .frame(minHeight: 28, maxHeight: 44)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.shift) {
                    return .ignored
                }
                if canSendDraft {
                    sendAndClearDraft()
                }
                return .handled
            }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(modelsForMenu) { model in
                Button {
                    container.settings.selectedModelID = model.id
                } label: {
                    HStack(spacing: HushSpacing.sm) {
                        if model.id == container.settings.selectedModelID {
                            Image(systemName: "checkmark")
                        }
                        Text(model.displayName)
                    }
                }
            }
        } label: {
            selectorLabel(title: selectedModelDisplayName, isHovered: isModelHovered)
        }
        .buttonStyle(.plain)
        .onHover { isModelHovered = $0 }
    }

    private var thinkingStrengthMenu: some View {
        Menu {
            ForEach(ThinkingStrength.allCases) { strength in
                Button {
                    container.settings.parameters = strength.parameters(preserving: container.settings.parameters)
                } label: {
                    HStack(spacing: HushSpacing.sm) {
                        if strength == selectedThinkingStrength {
                            Image(systemName: "checkmark")
                        }
                        Text(strength.rawValue)
                    }
                }
            }
        } label: {
            selectorLabel(title: selectedThinkingStrength.rawValue, isHovered: isStrengthHovered)
        }
        .buttonStyle(.plain)
        .onHover { isStrengthHovered = $0 }
    }

    private var configButton: some View {
        Button {
            showConfigPopover.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(isConfigHovered ? 0.74 : 0.58))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isConfigHovered ? 0.06 : 0))
                        .overlay(Circle().stroke(Color.white.opacity(isConfigHovered ? 0.12 : 0), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .onHover { isConfigHovered = $0 }
        .popover(isPresented: $showConfigPopover, arrowEdge: .top) {
            ChatConfigPopover(parameters: $container.settings.parameters)
        }
        .accessibilityLabel("Chat configuration")
    }

    private var sendOrStopButton: some View {
        Button {
            if container.isActiveConversationSending {
                container.stopActiveRequest()
            } else {
                sendAndClearDraft()
            }
        } label: {
            Image(systemName: container.isActiveConversationSending ? "stop.fill" : "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(sendButtonForeground)
                .frame(width: 25, height: 25)
                .background(sendButtonBackground, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!container.isActiveConversationSending && !canSendDraft)
        .accessibilityLabel(container.isActiveConversationSending ? "Stop generation" : "Send message")
    }

    private func selectorLabel(title: String, isHovered: Bool) -> some View {
        HStack(spacing: HushSpacing.xs) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .font(Font.body.weight(.medium))
        .foregroundStyle(.white.opacity(0.74))
        .padding(.horizontal, HushSpacing.sm)
        .padding(.vertical, HushSpacing.xs + 2)
        .background(
            Capsule()
                .fill(Color.white.opacity(isHovered ? 0.06 : 0))
                .overlay(Capsule().stroke(Color.white.opacity(isHovered ? 0.12 : 0), lineWidth: 1))
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var canSendDraft: Bool {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedDraft.isEmpty && !container.isQueueFull && container.hasConfiguredProvider
    }

    private func sendAndClearDraft() {
        guard canSendDraft else { return }
        let text = draft
        draft = ""
        container.sendDraft(text)
    }

    private var modelsForMenu: [ModelDescriptor] {
        if availableModels.isEmpty {
            return fallbackModels()
        }
        let pinnedIDs = container.settings.providerConfigurations
            .first(where: { $0.id == container.settings.selectedProviderID })?
            .pinnedModelIDs ?? []
        if pinnedIDs.isEmpty {
            return availableModels
        }
        let pinned = availableModels.filter { pinnedIDs.contains($0.id) }
        return pinned.isEmpty ? availableModels : pinned
    }

    private var selectedModelDisplayName: String {
        modelsForMenu.first(where: { $0.id == container.settings.selectedModelID })?.displayName
            ?? container.settings.selectedModelID
    }

    private var selectedThinkingStrength: ThinkingStrength {
        ThinkingStrength.from(parameters: container.settings.parameters)
    }

    private var sendButtonBackground: Color {
        if container.isActiveConversationSending {
            return Color.red.opacity(0.85)
        }
        if canSendDraft {
            return Color.white.opacity(0.88)
        }
        return Color.white.opacity(0.22)
    }

    private var sendButtonForeground: Color {
        if container.isActiveConversationSending {
            return .white
        }
        if canSendDraft {
            return Color.black.opacity(0.85)
        }
        return Color.black.opacity(0.38)
    }

    // MARK: - No Provider Empty State

    private var noProviderConfiguredView: some View {
        HStack(alignment: .center, spacing: HushSpacing.sm) {
            Image(systemName: "bolt.horizontal")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.44))

            Text("Add a provider to start chatting")
                .font(HushTypography.body)
                .foregroundStyle(HushColors.secondaryText)

            Spacer(minLength: 0)

            Button {
                NotificationCenter.default.post(name: .hushOpenSettings, object: nil)
            } label: {
                Label("Open Settings", systemImage: "gearshape")
                    .font(HushTypography.body)
                    .foregroundStyle(Color.white.opacity(isOpenSettingsHovered ? 0.88 : 0.74))
                    .padding(.horizontal, HushSpacing.md)
                    .padding(.vertical, HushSpacing.xs + 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(isOpenSettingsHovered ? 0.08 : 0.04))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(isOpenSettingsHovered ? 0.16 : 0.10), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .onHover { isOpenSettingsHovered = $0 }
            .accessibilityLabel("Open Settings")
        }
    }

    // MARK: - Model Refresh

    @MainActor
    private func refreshAvailableModels() async {
        let providerID = container.settings.selectedProviderID
        catalogStateMessage = nil

        guard !providerID.isEmpty else {
            availableModels = []
            return
        }

        let (models, _, error) = await container.availableModels(forProviderID: providerID)

        if models.isEmpty {
            availableModels = fallbackModels()
            if let error {
                catalogStateMessage = error
            }
        } else {
            availableModels = models
        }

        if !availableModels.contains(where: { $0.id == container.settings.selectedModelID }),
           let firstModel = availableModels.first
        {
            container.settings.selectedModelID = firstModel.id
        }
    }

    private func fallbackModels() -> [ModelDescriptor] {
        let providerDefaultModel = container.settings.providerConfigurations
            .first(where: { $0.id == container.settings.selectedProviderID })?
            .defaultModelID

        var uniqueIDs: [String] = []
        for id in [container.settings.selectedModelID, providerDefaultModel].compactMap({ $0 }) {
            guard !id.isEmpty, !uniqueIDs.contains(id) else { continue }
            uniqueIDs.append(id)
        }

        return uniqueIDs.map {
            ModelDescriptor(id: $0, displayName: $0, capabilities: [.text])
        }
    }
}

extension Notification.Name {
    static let hushOpenSettings = Notification.Name("hushOpenSettings")
}

private enum ThinkingStrength: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case extraHigh = "Extra High"

    var id: String {
        rawValue
    }

    func parameters(preserving existing: ModelParameters) -> ModelParameters {
        switch self {
        case .default:
            var params = existing
            params.useModelDefaults = true
            return params
        case .low, .medium, .high, .extraHigh:
            let (temp, topP, maxTokens) = switch self {
            case .low: (0.30, 0.80, 512)
            case .medium: (0.50, 0.90, 768)
            case .high: (0.70, 1.00, 1024)
            case .extraHigh: (0.90, 1.00, 1536)
            case .default: (0.0, 0.0, 0) // unreachable
            }
            return ModelParameters(
                temperature: temp,
                topP: topP,
                topK: existing.topK,
                maxTokens: maxTokens,
                presencePenalty: 0,
                frequencyPenalty: 0,
                contextMessageLimit: existing.contextMessageLimit
            )
        }
    }

    var parameters: ModelParameters {
        parameters(preserving: .standard)
    }

    static func from(parameters: ModelParameters) -> ThinkingStrength {
        if parameters.useModelDefaults { return .default }
        let presets: [ThinkingStrength] = [.low, .medium, .high, .extraHigh]
        return presets.min {
            abs($0.parameters.temperature - parameters.temperature)
                < abs($1.parameters.temperature - parameters.temperature)
        } ?? .high
    }
}
