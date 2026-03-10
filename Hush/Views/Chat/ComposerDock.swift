import SwiftUI

struct ComposerDock: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.hushThemePalette) private var palette
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
                            .foregroundStyle(palette.controlForegroundMuted)
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
                            .foregroundStyle(palette.controlForegroundMuted)
                            .frame(width: 25, height: 25)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voice input")

                    sendOrStopButton
                }

                if let catalogStateMessage, !catalogStateMessage.isEmpty {
                    Text(catalogStateMessage)
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.errorText)
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
                            palette.composerShellTop,
                            palette.composerShellBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(palette.composerShellStroke, lineWidth: 1)
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
            .foregroundStyle(palette.primaryText)
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
                    container.settings.parameters.reasoningEffort = strength.reasoningEffort
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
            HStack(spacing: HushSpacing.sm) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(configButtonIconForeground)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(configButtonIconFill)
                            .overlay(
                                Circle()
                                    .stroke(configButtonIconStroke, lineWidth: 1)
                            )
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text("Chat Options")
                        .font(HushTypography.captionBold)
                        .foregroundStyle(palette.controlForeground)
                        .lineLimit(1)

                    Text(chatOptionsSummary)
                        .font(HushTypography.caption)
                        .monospacedDigit()
                        .foregroundStyle(palette.controlForegroundMuted)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.controlForegroundMuted)
            }
            .padding(.leading, HushSpacing.xs)
            .padding(.trailing, HushSpacing.sm)
            .padding(.vertical, HushSpacing.xs + 2)
            .background(
                Capsule(style: .continuous)
                    .fill(configButtonFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(configButtonStroke, lineWidth: 1)
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isConfigHovered = $0 }
        .popover(isPresented: $showConfigPopover, arrowEdge: .top) {
            ChatConfigPopover(parameters: $container.settings.parameters)
        }
        .accessibilityLabel("Chat configuration")
        .accessibilityValue(chatOptionsSummary)
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
        .font(HushTypography.scaled(14, weight: .medium))
        .foregroundStyle(palette.controlForeground)
        .padding(.horizontal, HushSpacing.sm)
        .padding(.vertical, HushSpacing.xs + 2)
        .background(
            Capsule()
                .fill(isHovered ? palette.hoverFill : .clear)
                .overlay(Capsule().stroke(isHovered ? palette.hoverStroke : .clear, lineWidth: 1))
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
        ThinkingStrength.from(reasoningEffort: container.settings.parameters.reasoningEffort)
    }

    private var chatOptionsSummary: String {
        "\(contextLimitSummary) ctx · T \(temperatureSummary) · \(compactTokenCount(maxTokensSummary)) tok"
    }

    private var contextLimitSummary: Int {
        container.settings.parameters.contextMessageLimit ?? ModelParameters.standard.contextMessageLimit ?? 10
    }

    private var temperatureSummary: String {
        String(format: "%.2f", container.settings.parameters.temperature)
    }

    private var maxTokensSummary: Int {
        container.settings.parameters.maxTokens
    }

    private var configButtonFill: Color {
        if showConfigPopover {
            return palette.selectionFill
        }
        if isConfigHovered {
            return palette.hoverFill
        }
        return palette.softFill
    }

    private var configButtonStroke: Color {
        if showConfigPopover {
            return palette.selectionStroke
        }
        if isConfigHovered {
            return palette.hoverStroke
        }
        return palette.subtleStroke
    }

    private var configButtonIconFill: Color {
        if showConfigPopover {
            return palette.accentMutedBackground
        }
        if isConfigHovered {
            return palette.hoverFill
        }
        return palette.softFillStrong
    }

    private var configButtonIconStroke: Color {
        if showConfigPopover {
            return palette.accentMutedStroke
        }
        if isConfigHovered {
            return palette.hoverStroke
        }
        return palette.subtleStroke
    }

    private var configButtonIconForeground: Color {
        if showConfigPopover {
            return palette.controlForeground
        }
        if isConfigHovered {
            return palette.controlForeground
        }
        return palette.controlForegroundMuted
    }

    private func compactTokenCount(_ value: Int) -> String {
        guard value >= 1000 else { return "\(value)" }
        return String(format: "%.1fK", Double(value) / 1000)
    }

    private var sendButtonBackground: Color {
        if container.isActiveConversationSending {
            return palette.destructiveActionBackground
        }
        if canSendDraft {
            return palette.primaryActionBackground
        }
        return palette.disabledActionBackground
    }

    private var sendButtonForeground: Color {
        if container.isActiveConversationSending {
            return palette.destructiveActionForeground
        }
        if canSendDraft {
            return palette.primaryActionForeground
        }
        return palette.disabledActionForeground
    }

    // MARK: - No Provider Empty State

    private var noProviderConfiguredView: some View {
        HStack(alignment: .center, spacing: HushSpacing.sm) {
            Image(systemName: "bolt.horizontal")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(palette.tertiaryText)

            Text("Add a provider to start chatting")
                .font(HushTypography.body)
                .foregroundStyle(palette.secondaryText)

            Spacer(minLength: 0)

            Button {
                NotificationCenter.default.post(name: .hushOpenSettings, object: nil)
            } label: {
                Label("Open Settings", systemImage: "gearshape")
                    .font(HushTypography.body)
                    .foregroundStyle(isOpenSettingsHovered ? palette.controlForeground : palette.controlForegroundMuted)
                    .padding(.horizontal, HushSpacing.md)
                    .padding(.vertical, HushSpacing.xs + 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isOpenSettingsHovered ? palette.softFillStrong : palette.softFill)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(
                                        isOpenSettingsHovered ? palette.hoverStroke : palette.subtleStroke,
                                        lineWidth: 1
                                    )
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

    var id: String {
        rawValue
    }

    var reasoningEffort: ModelReasoningEffort? {
        switch self {
        case .default:
            return nil
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }

    static func from(reasoningEffort: ModelReasoningEffort?) -> ThinkingStrength {
        switch reasoningEffort {
        case nil:
            return .default
        case .some(.none), .some(.minimal), .some(.low):
            return .low
        case .some(.medium):
            return .medium
        case .some(.high), .some(.xhigh):
            return .high
        }
    }
}
