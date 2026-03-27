import SwiftUI

struct ComposerDock: View {
    @Binding var isConfigDrawerPresented: Bool
    @EnvironmentObject private var container: AppContainer
    @Environment(\.hushThemePalette) private var palette
    @State private var draft: String = ""
    @State private var availableModels: [ModelDescriptor] = []
    @State private var catalogStateMessage: String?
    @State private var isStrengthHovered = false
    @State private var isConfigHovered = false
    @State private var isOpenSettingsHovered = false

    private var modelService: ComposerModelService {
        ComposerModelService(container: container, surfaceStyle: .main)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HushSpacing.sm) {
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

                    ProviderModelSelector(
                        surfaceStyle: .main,
                        providers: modelService.enabledProviders,
                        models: modelsForMenu,
                        selectedProviderID: container.settings.selectedProviderID,
                        selectedProviderName: modelService.selectedProviderName,
                        selectedModelID: container.settings.selectedModelID,
                        selectedModelDisplayName: modelService.selectedModelDisplayName(models: modelsForMenu),
                        showsProviderMenu: modelService.enabledProviders.count > 1,
                        providerHelpText: modelService.selectedProviderName,
                        modelHelpText: modelService.selectedModelDisplayName(models: modelsForMenu),
                        onSelectProvider: { provider in
                            container.selectProvider(id: provider.id)
                        },
                        onSelectModel: { model in
                            container.settings.selectedModelID = model.id
                        },
                        providerLabel: { title, isHovered in
                            selectorLabel(title: title, isHovered: isHovered)
                        },
                        modelLabel: { title, isHovered in
                            selectorLabel(title: title, isHovered: isHovered)
                        }
                    )
                    thinkingStrengthMenu

                    Spacer(minLength: 0)

                    configButton

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
            let shell = RoundedRectangle(cornerRadius: 30, style: .continuous)

            shell
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
                    shell
                        .stroke(palette.composerShellStroke, lineWidth: 1)
                )
                .shadow(
                    color: palette.splitPaneShadow.opacity(0.10),
                    radius: 8,
                    x: 0,
                    y: 4
                )
        }
        .frame(maxWidth: HushSpacing.chatContentMaxWidth)
        .padding(.horizontal, HushSpacing.xl)
        .padding(.top, HushSpacing.xs)
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
            .frame(minHeight: 30, maxHeight: 44)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, HushSpacing.md)
            .padding(.vertical, HushSpacing.xs + 1)
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
            isConfigDrawerPresented.toggle()
        } label: {
            HStack(spacing: HushSpacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))

                Text("Tune")
                    .font(HushTypography.scaled(13, weight: .medium))
                    .lineLimit(1)

                if hasCustomizedOptions {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(configButtonForeground)
            .padding(.leading, HushSpacing.sm)
            .padding(.trailing, HushSpacing.sm)
            .padding(.vertical, HushSpacing.xs + 1)
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
        .help(chatOptionsSummary)
        .accessibilityLabel("Chat tuning")
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
        .padding(.vertical, HushSpacing.xs + 1)
        .background(
            Capsule()
                .fill(isHovered ? palette.softFillStrong : .clear)
                .overlay(Capsule().stroke(isHovered ? palette.subtleStroke : .clear, lineWidth: 1))
        )
        .animation(.easeInOut(duration: 0.18), value: isHovered)
    }

    private var canSendDraft: Bool {
        modelService.canSendDraft(draft: draft)
    }

    private func sendAndClearDraft() {
        guard canSendDraft else { return }
        let text = draft
        draft = ""
        container.sendDraft(text)
    }

    private var modelsForMenu: [ModelDescriptor] {
        modelService.modelsForMenu(availableModels: availableModels)
    }

    private var selectedThinkingStrength: ThinkingStrength {
        ThinkingStrength.from(reasoningEffort: container.settings.parameters.reasoningEffort)
    }

    private var chatOptionsSummary: String {
        let topK = container.settings.parameters.topK.map(String.init) ?? "off"
        let maxTokens = maxTokensSummary == 0 ? "unlimited" : compactTokenCount(maxTokensSummary)
        return "\(contextLimitSummary) context, temp \(temperatureSummary), " +
            "top p \(topPSummary), top k \(topK), max \(maxTokens) tokens"
    }

    private var contextLimitSummary: Int {
        container.settings.parameters.contextMessageLimit ?? ModelParameters.standard.contextMessageLimit ?? 10
    }

    private var temperatureSummary: String {
        String(format: "%.2f", container.settings.parameters.temperature)
    }

    private var topPSummary: String {
        String(format: "%.2f", container.settings.parameters.topP)
    }

    private var maxTokensSummary: Int {
        container.settings.parameters.maxTokens
    }

    private var hasCustomizedOptions: Bool {
        let standard = ModelParameters.standard
        let standardContextLimit = standard.contextMessageLimit ?? 10

        return contextLimitSummary != standardContextLimit ||
            container.settings.parameters.maxTokens != standard.maxTokens ||
            abs(container.settings.parameters.temperature - standard.temperature) > 0.001 ||
            abs(container.settings.parameters.topP - standard.topP) > 0.001 ||
            container.settings.parameters.topK != standard.topK
    }

    private var configButtonFill: Color {
        if isConfigDrawerPresented {
            return palette.selectionFill
        }
        if isConfigHovered {
            return palette.softFillStrong
        }
        return .clear
    }

    private var configButtonStroke: Color {
        if isConfigDrawerPresented {
            return palette.selectionStroke
        }
        if isConfigHovered {
            return palette.hoverStroke
        }
        return palette.subtleStroke
    }

    private var configButtonForeground: Color {
        if isConfigDrawerPresented || hasCustomizedOptions {
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
        let result = await modelService.refreshAvailableModels()
        availableModels = result.models
        catalogStateMessage = result.catalogStateMessage
    }
}
