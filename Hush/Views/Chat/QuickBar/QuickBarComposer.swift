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
    @State private var isOpenSettingsHovered = false
    @State private var isSendHovered = false
    @FocusState private var isEditorFocused: Bool

    private var modelService: ComposerModelService {
        ComposerModelService(container: container, surfaceStyle: .quickBar)
    }

    init(layoutStyle: QuickBarComposerLayoutStyle = .compact) {
        self.layoutStyle = layoutStyle
    }

    private var palette: HushThemePalette {
        HushColors.palette(for: container.settings.theme)
    }

    private var metrics: QuickBarComposerLayoutMetrics {
        QuickBarComposerLayoutMetrics.for(layoutStyle: layoutStyle)
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
            ProviderModelSelector(
                surfaceStyle: .quickBar,
                providers: modelService.enabledProviders,
                models: modelsForMenu,
                selectedProviderID: container.quickBarState.providerID,
                selectedProviderName: modelService.selectedProviderName,
                selectedModelID: container.quickBarState.selectedModelID,
                selectedModelDisplayName: modelService.selectedModelDisplayName(models: modelsForMenu),
                showsProviderMenu: true,
                providerHelpText: modelService.selectedProviderName,
                modelHelpText: modelService.selectedModelDisplayName(models: modelsForMenu),
                onSelectProvider: { provider in
                    container.selectQuickBarProvider(id: provider.id)
                },
                onSelectModel: { model in
                    container.selectQuickBarModel(id: model.id)
                },
                providerLabel: { title, isHovered in
                    selectorLabel(
                        iconName: "server.rack",
                        text: title,
                        fontSize: metrics.providerLabelFontSize,
                        isHovered: isHovered
                    )
                },
                modelLabel: { title, isHovered in
                    selectorLabel(
                        iconName: "sparkles",
                        text: title,
                        fontSize: metrics.modelLabelFontSize,
                        isHovered: isHovered
                    )
                }
            )

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

    private func selectorLabel(
        iconName: String,
        text: String,
        fontSize: CGFloat,
        isHovered: Bool
    ) -> some View {
        HStack(spacing: HushSpacing.xs + 2) {
            Image(systemName: iconName)
                .font(.system(size: metrics.modelIconSize, weight: .semibold))
            Text(text)
                .font(HushTypography.scaled(fontSize, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: metrics.modelChevronSize, weight: .semibold))
        }
        .foregroundStyle(palette.quickBarControlForeground)
        .frame(minHeight: metrics.capsuleVisualHeight)
        .padding(.horizontal, metrics.capsuleHorizontalPadding)
        .background {
            controlCapsuleSurface(isHovered: isHovered)
        }
        .frame(minHeight: metrics.controlHitSize)
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
        modelService.modelsForMenu(availableModels: availableModels)
    }

    private var canSendDraft: Bool {
        modelService.canSendDraft(draft: container.quickBarState.draft)
    }

    private var sendButtonForeground: Color {
        if container.isQuickBarSending {
            return palette.destructiveActionForeground
        }
        return canSendDraft ? palette.quickBarButtonForeground : palette.quickBarDisabledButtonForeground
    }

    private var shellSurface: some View {
        QuickBarComposerVisuals.shellSurface(
            isExpandedLayout: isExpandedLayout,
            metrics: metrics,
            palette: palette,
            usesDarkAppearance: container.settings.theme.usesDarkAppearance
        )
    }

    private func controlCapsuleSurface(isHovered: Bool) -> some View {
        QuickBarComposerVisuals.controlCapsuleSurface(
            isHovered: isHovered,
            isExpandedLayout: isExpandedLayout,
            palette: palette,
            usesDarkAppearance: container.settings.theme.usesDarkAppearance
        )
    }

    private var sendButtonSurface: some View {
        QuickBarComposerVisuals.sendButtonSurface(
            .init(
                isHovered: isSendHovered,
                isEnabled: canSendDraft,
                isSending: container.isQuickBarSending,
                isExpandedLayout: isExpandedLayout,
                palette: palette,
                usesDarkAppearance: container.settings.theme.usesDarkAppearance
            )
        )
    }

    @MainActor
    private func refreshAvailableModels() async {
        let result = await modelService.refreshAvailableModels()
        availableModels = result.models
        catalogStateMessage = result.catalogStateMessage
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
