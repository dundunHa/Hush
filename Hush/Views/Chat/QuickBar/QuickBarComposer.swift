import SwiftUI

enum QuickBarComposerLayoutStyle: Sendable {
    case compact
    case expanded
}

struct QuickBarComposer: View {
    @EnvironmentObject private var container: AppContainer

    private let layoutStyle: QuickBarComposerLayoutStyle

    @State private var availableModels: [ModelDescriptor] = []
    @State private var catalogStateMessage: String?
    @State private var isProviderHovered = false
    @State private var isModelHovered = false
    @State private var isOpenSettingsHovered = false
    @State private var isSendHovered = false
    @FocusState private var isEditorFocused: Bool

    init(layoutStyle: QuickBarComposerLayoutStyle = .compact) {
        self.layoutStyle = layoutStyle
    }

    private var palette: HushThemePalette {
        HushColors.palette(for: container.settings.theme)
    }

    private var metrics: QuickBarComposerLayoutMetrics {
        switch layoutStyle {
        case .compact:
            return QuickBarComposerLayoutMetrics(
                shellCornerRadius: 34,
                shellHorizontalInset: 18,
                shellTopInset: 16,
                shellBottomInset: 14,
                editorMinHeight: 78,
                editorMaxHeight: 116,
                editorHorizontalPadding: 0,
                editorVerticalPadding: 2,
                placeholderHorizontalInset: 6,
                placeholderTopInset: 6,
                placeholderFontSize: 17,
                editorSurfaceHorizontalInset: 0,
                editorSurfaceVerticalInset: 0,
                toolbarTopPadding: 8,
                toolbarHorizontalInset: 0,
                toolbarBottomPadding: 0,
                toolbarMinHeight: 52,
                toolbarSpacing: 10,
                controlHitSize: 44,
                providerLabelFontSize: 16,
                modelIconSize: 15,
                modelLabelFontSize: 16,
                modelChevronSize: 11,
                capsuleHorizontalPadding: 14,
                capsuleVisualHeight: 36,
                sendButtonHitSize: 44,
                sendButtonVisualSize: 40,
                sendIconSize: 17
            )
        case .expanded:
            return QuickBarComposerLayoutMetrics(
                shellCornerRadius: 18,
                shellHorizontalInset: 0,
                shellTopInset: 2,
                shellBottomInset: 0,
                editorMinHeight: 46,
                editorMaxHeight: 64,
                editorHorizontalPadding: 2,
                editorVerticalPadding: 0,
                placeholderHorizontalInset: 4,
                placeholderTopInset: 1,
                placeholderFontSize: 15,
                editorSurfaceHorizontalInset: 3,
                editorSurfaceVerticalInset: 2,
                toolbarTopPadding: 2,
                toolbarHorizontalInset: 3,
                toolbarBottomPadding: 1,
                toolbarMinHeight: 34,
                toolbarSpacing: 6,
                controlHitSize: 36,
                providerLabelFontSize: 13,
                modelIconSize: 14,
                modelLabelFontSize: 13,
                modelChevronSize: 10,
                capsuleHorizontalPadding: 10,
                capsuleVisualHeight: 26,
                sendButtonHitSize: 36,
                sendButtonVisualSize: 30,
                sendIconSize: 15
            )
        }
    }

    private var isExpandedLayout: Bool {
        layoutStyle == .expanded
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { container.quickBarState.draft },
            set: { container.updateQuickBarDraft($0) }
        )
    }

    var body: some View {
        Group {
            if container.hasConfiguredProvider {
                composerShell
                    .task(id: container.quickBarState.providerID) {
                        await refreshAvailableModels()
                    }
                    .task(id: container.showQuickBar) {
                        focusEditorIfNeeded()
                    }
                    .onChange(of: container.showQuickBar) { _, _ in
                        focusEditorIfNeeded()
                    }
            } else {
                providerEmptyState
            }
        }
    }

    private var composerShell: some View {
        VStack(alignment: .leading, spacing: 0) {
            editorSurface
            bottomBar
        }
        .padding(.horizontal, metrics.shellHorizontalInset)
        .padding(.top, metrics.shellTopInset)
        .padding(.bottom, metrics.shellBottomInset)
        .background(shellSurface)
    }

    private var providerEmptyState: some View {
        HStack(spacing: HushSpacing.md) {
            Text("Add a provider in Settings to use Quick Bar.")
                .font(HushTypography.caption)
                .foregroundStyle(palette.quickBarSecondaryText.opacity(0.92))

            Spacer(minLength: 0)

            Button("Open Settings") {
                NotificationCenter.default.post(name: .hushOpenSettings, object: nil)
            }
            .buttonStyle(QuickBarScaleButtonStyle())
            .foregroundStyle(palette.quickBarControlForeground)
            .frame(minHeight: metrics.controlHitSize)
            .padding(.horizontal, metrics.capsuleHorizontalPadding)
            .background {
                controlCapsuleSurface(isHovered: isOpenSettingsHovered)
            }
            .onHover { isOpenSettingsHovered = $0 }
        }
        .padding(.horizontal, metrics.shellHorizontalInset)
        .padding(.vertical, metrics.shellTopInset)
        .background(shellSurface)
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            if container.quickBarState.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("有问题，尽管问")
                    .font(HushTypography.scaled(metrics.placeholderFontSize, weight: .medium))
                    .foregroundStyle(palette.quickBarTertiaryText.opacity(0.94))
                    .padding(.horizontal, metrics.placeholderHorizontalInset)
                    .padding(.top, metrics.placeholderTopInset)
                    .allowsHitTesting(false)
            }

            TextEditor(text: draftBinding)
                .focused($isEditorFocused)
                .font(HushTypography.scaled(isExpandedLayout ? 14 : 16))
                .foregroundStyle(palette.quickBarPrimaryText)
                .frame(minHeight: metrics.editorMinHeight, maxHeight: metrics.editorMaxHeight)
                .scrollIndicators(.never, axes: .vertical)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, metrics.editorHorizontalPadding)
                .padding(.vertical, metrics.editorVerticalPadding)
                .background(Color.clear)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) {
                        return .ignored
                    }
                    if container.quickBarSubmit() {
                        return .handled
                    }
                    return .ignored
                }
        }
        .padding(.horizontal, metrics.editorSurfaceHorizontalInset)
        .padding(.vertical, metrics.editorSurfaceVerticalInset)
        .background {
            if isExpandedLayout {
                QuickBarComposerExpandedEditorSurface(
                    palette: palette,
                    usesDarkAppearance: container.settings.theme.usesDarkAppearance,
                    cornerRadius: metrics.shellCornerRadius
                )
            }
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: metrics.toolbarSpacing) {
            providerMenu
            modelMenu

            if let catalogStateMessage, !catalogStateMessage.isEmpty {
                Text(catalogStateMessage)
                    .font(HushTypography.caption)
                    .foregroundStyle(palette.destructiveActionBackground.opacity(0.88))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            sendButton
        }
        .frame(minHeight: metrics.toolbarMinHeight)
        .padding(.top, metrics.toolbarTopPadding)
        .padding(.horizontal, metrics.toolbarHorizontalInset)
        .padding(.bottom, metrics.toolbarBottomPadding)
    }

    private var enabledProviders: [ProviderConfiguration] {
        container.settings.providerConfigurations.filter(\.isEnabled)
    }

    private var selectedProviderName: String {
        let name = enabledProviders.first(where: { $0.id == container.quickBarState.providerID })?.name
            ?? container.quickBarState.providerID
        return name.isEmpty ? "Provider" : name
    }

    private var providerMenu: some View {
        Menu {
            ForEach(enabledProviders) { provider in
                Button {
                    container.selectQuickBarProvider(id: provider.id)
                } label: {
                    HStack(spacing: HushSpacing.sm) {
                        if provider.id == container.quickBarState.providerID {
                            Image(systemName: "checkmark")
                        }
                        Text(provider.name)
                    }
                }
            }
        } label: {
            HStack(spacing: HushSpacing.xs + 2) {
                Image(systemName: "server.rack")
                    .font(.system(size: metrics.modelIconSize, weight: .semibold))
                Text(selectedProviderName)
                    .font(HushTypography.scaled(metrics.providerLabelFontSize, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: metrics.modelChevronSize, weight: .semibold))
            }
            .foregroundStyle(palette.quickBarControlForeground)
            .frame(minHeight: metrics.capsuleVisualHeight)
            .padding(.horizontal, metrics.capsuleHorizontalPadding)
            .background {
                controlCapsuleSurface(isHovered: isProviderHovered)
            }
            .frame(minHeight: metrics.controlHitSize)
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .help(selectedProviderName)
        .onHover { isProviderHovered = $0 }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(modelsForMenu) { model in
                Button {
                    container.selectQuickBarModel(id: model.id)
                } label: {
                    HStack(spacing: HushSpacing.sm) {
                        if model.id == container.quickBarState.selectedModelID {
                            Image(systemName: "checkmark")
                        }
                        Text(model.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: HushSpacing.xs + 2) {
                Image(systemName: "sparkles")
                    .font(.system(size: metrics.modelIconSize, weight: .semibold))
                Text(selectedModelDisplayName)
                    .font(HushTypography.scaled(metrics.modelLabelFontSize, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: metrics.modelChevronSize, weight: .semibold))
            }
            .foregroundStyle(palette.quickBarControlForeground)
            .frame(minHeight: metrics.capsuleVisualHeight)
            .padding(.horizontal, metrics.capsuleHorizontalPadding)
            .background {
                controlCapsuleSurface(isHovered: isModelHovered)
            }
            .frame(minHeight: metrics.controlHitSize)
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .help(selectedModelDisplayName)
        .onHover { isModelHovered = $0 }
    }

    private var sendButton: some View {
        Button {
            if container.isQuickBarSending {
                container.stopQuickBarRequest()
            } else {
                _ = container.quickBarSubmit()
            }
        } label: {
            Image(systemName: container.isQuickBarSending ? "stop.fill" : "arrow.up")
                .font(.system(size: metrics.sendIconSize, weight: .semibold))
                .foregroundStyle(sendButtonForeground)
                .frame(width: metrics.sendButtonVisualSize, height: metrics.sendButtonVisualSize)
                .background {
                    sendButtonSurface
                }
                .frame(width: metrics.sendButtonHitSize, height: metrics.sendButtonHitSize)
        }
        .buttonStyle(QuickBarScaleButtonStyle())
        .disabled(!container.isQuickBarSending && !canSendDraft)
        .onHover { isSendHovered = $0 }
        .accessibilityLabel(container.isQuickBarSending ? "Stop generation" : "Send message")
    }

    private var modelsForMenu: [ModelDescriptor] {
        let models = availableModels.isEmpty ? fallbackModels() : availableModels
        let filtered = models.filter {
            $0.capabilities.contains(.text) || $0.supportedOutputs.contains(.text)
        }
        return filtered.isEmpty ? fallbackModels() : filtered
    }

    private var selectedModelDisplayName: String {
        let name = modelsForMenu.first(where: { $0.id == container.quickBarState.selectedModelID })?.displayName
            ?? container.quickBarState.selectedModelID
        return name.isEmpty ? "Model" : name
    }

    private var canSendDraft: Bool {
        !container.quickBarState.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !container.isQueueFull
            && container.hasConfiguredProvider
            && !container.quickBarState.selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sendButtonForeground: Color {
        if container.isQuickBarSending {
            return palette.destructiveActionForeground
        }
        return canSendDraft ? palette.quickBarButtonForeground : palette.quickBarDisabledButtonForeground
    }

    private var shellFill: Color {
        palette.quickBarSurface.opacity(container.settings.theme.usesDarkAppearance ? 0.92 : 0.975)
    }

    private var shellStroke: Color {
        palette.quickBarSurfaceStroke.opacity(container.settings.theme.usesDarkAppearance ? 0.22 : 0.48)
    }

    private var shellHighlight: LinearGradient {
        return LinearGradient(
            colors: [
                Color.white.opacity(container.settings.theme.usesDarkAppearance ? 0.08 : 0.38),
                .clear
            ],
            startPoint: .top,
            endPoint: .center
        )
    }

    @ViewBuilder
    private var shellSurface: some View {
        if isExpandedLayout {
            Color.clear
        } else {
            let shape = RoundedRectangle(cornerRadius: metrics.shellCornerRadius, style: .continuous)

            ZStack {
                QuickBarMinimalSurface(
                    shape: shape,
                    fill: shellFill,
                    stroke: shellStroke,
                    shadowColor: palette.splitPaneShadow,
                    shadowOpacity: container.settings.theme.usesDarkAppearance ? 0.18 : 0.10,
                    shadowRadius: 12,
                    shadowYOffset: 2
                )

                shape
                    .fill(shellHighlight)
                    .clipShape(shape)

                shape
                    .strokeBorder(
                        Color.white.opacity(
                            container.settings.theme.usesDarkAppearance ? 0.04 : 0.16
                        ),
                        lineWidth: 0.5
                    )
            }
        }
    }

    private func controlCapsuleSurface(isHovered: Bool) -> some View {
        QuickBarMinimalSurface(
            shape: Capsule(style: .continuous),
            fill: controlCapsuleFillColor(isHovered: isHovered),
            stroke: controlCapsuleStrokeColor(isHovered: isHovered),
            shadowColor: palette.splitPaneShadow,
            shadowOpacity: isExpandedLayout ? 0 : (isHovered ? 0.08 : 0.04),
            shadowRadius: isExpandedLayout ? 0 : 4,
            shadowYOffset: isExpandedLayout ? 0 : 1
        )
    }

    private var sendButtonSurface: some View {
        QuickBarMinimalSurface(
            shape: Circle(),
            fill: actionFillColor(
                isHovered: isSendHovered,
                isEnabled: canSendDraft,
                isSending: container.isQuickBarSending
            ),
            stroke: actionStrokeColor(
                isHovered: isSendHovered,
                isEnabled: canSendDraft,
                isSending: container.isQuickBarSending
            ),
            shadowColor: palette.splitPaneShadow,
            shadowOpacity: actionShadowOpacity(
                isHovered: isSendHovered,
                isEnabled: canSendDraft,
                isSending: container.isQuickBarSending
            ),
            shadowRadius: isSendHovered ? 8 : 6,
            shadowYOffset: 2
        )
    }

    private func controlCapsuleFillColor(isHovered: Bool) -> Color {
        if isExpandedLayout {
            return palette.quickBarControlFill.opacity(
                container.settings.theme.usesDarkAppearance
                    ? (isHovered ? 0.18 : 0.10)
                    : (isHovered ? 0.24 : 0.14)
            )
        }
        return palette.quickBarControlFill.opacity(
            container.settings.theme.usesDarkAppearance
                ? (isHovered ? 0.34 : 0.18)
                : (isHovered ? 0.56 : 0.34)
        )
    }

    private func controlCapsuleStrokeColor(isHovered: Bool) -> Color {
        if isExpandedLayout {
            return palette.quickBarSurfaceStroke.opacity(
                isHovered
                    ? (container.settings.theme.usesDarkAppearance ? 0.12 : 0.18)
                    : (container.settings.theme.usesDarkAppearance ? 0.08 : 0.12)
            )
        }
        return palette.quickBarSurfaceStroke.opacity(
            isHovered
                ? (container.settings.theme.usesDarkAppearance ? 0.24 : 0.34)
                : (container.settings.theme.usesDarkAppearance ? 0.16 : 0.24)
        )
    }

    private func actionFillColor(
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool
    ) -> Color {
        if isSending {
            return palette.destructiveActionBackground.opacity(
                container.settings.theme.usesDarkAppearance
                    ? (isHovered ? 0.96 : 0.88)
                    : (isHovered ? 1 : 0.94)
            )
        }

        if isEnabled {
            return palette.quickBarButtonFill.opacity(
                container.settings.theme.usesDarkAppearance
                    ? (isHovered ? 0.98 : 0.92)
                    : (isHovered ? 1 : 0.96)
            )
        }

        return palette.quickBarDisabledButtonFill.opacity(
            container.settings.theme.usesDarkAppearance ? 0.88 : 0.96
        )
    }

    private func actionStrokeColor(
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool
    ) -> Color {
        if isSending {
            return palette.destructiveActionForeground.opacity(isHovered ? 0.32 : 0.22)
        }

        if isEnabled {
            return palette.quickBarButtonFill.opacity(isHovered ? 0.58 : 0.40)
        }

        return palette.quickBarSurfaceStroke.opacity(0.18)
    }

    private func actionShadowOpacity(
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool
    ) -> Double {
        if isExpandedLayout {
            if isSending {
                return isHovered ? 0.12 : 0.08
            }

            if isEnabled {
                return isHovered ? 0.10 : 0.06
            }

            return 0.02
        }

        if isSending {
            return isHovered ? 0.18 : 0.12
        }

        if isEnabled {
            return isHovered ? 0.14 : 0.10
        }

        return 0.04
    }

    @MainActor
    private func refreshAvailableModels() async {
        let providerID = container.quickBarState.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerID.isEmpty else {
            availableModels = fallbackModels()
            catalogStateMessage = nil
            return
        }

        let (models, _, error) = await container.availableModels(forProviderID: providerID)
        let textModels = models.filter {
            $0.capabilities.contains(.text) || $0.supportedOutputs.contains(.text)
        }
        availableModels = textModels.isEmpty ? fallbackModels() : textModels
        catalogStateMessage = error

        if !availableModels.contains(where: { $0.id == container.quickBarState.selectedModelID }),
           let firstModel = availableModels.first
        {
            container.selectQuickBarModel(id: firstModel.id)
        }
    }

    private func fallbackModels() -> [ModelDescriptor] {
        let ids = [
            container.quickBarState.selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines),
            container.settings.selectedModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        var uniqueIDs: [String] = []
        for id in ids where !id.isEmpty && !uniqueIDs.contains(id) {
            uniqueIDs.append(id)
        }
        return uniqueIDs.map {
            ModelDescriptor(id: $0, displayName: $0, capabilities: [.text])
        }
    }

    private func focusEditorIfNeeded() {
        guard container.showQuickBar, container.hasConfiguredProvider else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isEditorFocused = true
        }
    }
}

struct QuickBarScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
