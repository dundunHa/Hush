import SwiftUI

struct QuickBarComposer: View {
    @EnvironmentObject private var container: AppContainer

    private let glassNamespace: Namespace.ID?
    private let prefersNativeGlass: Bool

    @State private var availableModels: [ModelDescriptor] = []
    @State private var catalogStateMessage: String?
    @State private var isModelHovered = false
    @State private var isOpenSettingsHovered = false
    @State private var isSendHovered = false
    @FocusState private var isEditorFocused: Bool

    init(
        glassNamespace: Namespace.ID? = nil,
        prefersNativeGlass: Bool = false
    ) {
        self.glassNamespace = glassNamespace
        self.prefersNativeGlass = prefersNativeGlass
    }

    private var palette: HushThemePalette {
        HushColors.palette(for: container.settings.theme)
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
                VStack(alignment: .leading, spacing: 0) {
                    editorSurface
                    bottomBar
                }
                .padding(.horizontal, HushSpacing.md)
                .padding(.top, HushSpacing.sm + 2)
                .padding(.bottom, HushSpacing.sm)
                .background(composerSurface)
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
                HStack(spacing: HushSpacing.md) {
                    Text("Add a provider in Settings to use Quick Bar.")
                        .font(HushTypography.caption)
                        .foregroundStyle(palette.quickBarSecondaryText)

                    Spacer(minLength: 0)

                    Button("Open Settings") {
                        NotificationCenter.default.post(name: .hushOpenSettings, object: nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.quickBarControlForeground)
                    .padding(.horizontal, HushSpacing.md)
                    .padding(.vertical, HushSpacing.xs + 2)
                    .background {
                        controlGlassSurface(
                            shape: Capsule(style: .continuous),
                            isHovered: isOpenSettingsHovered,
                            registration: QuickBarNativeGlassRegistration(
                                id: .openSettingsControl,
                                transition: .matchedGeometry
                            )
                        )
                    }
                    .onHover { isOpenSettingsHovered = $0 }
                }
                .padding(.horizontal, HushSpacing.md)
                .padding(.vertical, HushSpacing.sm)
                .background(providerEmptySurface)
            }
        }
    }

    private var editorSurface: some View {
        ZStack(alignment: .topLeading) {
            if container.quickBarState.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Ask anything")
                    .font(HushTypography.scaled(17, weight: .medium))
                    .foregroundStyle(palette.quickBarTertiaryText)
                    .padding(.horizontal, HushSpacing.md)
                    .padding(.top, HushSpacing.xs + 2)
                    .allowsHitTesting(false)
            }

            TextEditor(text: draftBinding)
                .focused($isEditorFocused)
                .font(HushTypography.scaled(16))
                .foregroundStyle(palette.quickBarPrimaryText)
                .frame(minHeight: 52, maxHeight: 88)
                .scrollIndicators(.never, axes: .vertical)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, HushSpacing.sm)
                .padding(.vertical, HushSpacing.xs)
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
    }

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: HushSpacing.sm) {
            modelMenu

            if let catalogStateMessage, !catalogStateMessage.isEmpty {
                Text(catalogStateMessage)
                    .font(HushTypography.caption)
                    .foregroundStyle(palette.destructiveActionBackground.opacity(0.86))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                if container.isQuickBarSending {
                    container.stopQuickBarRequest()
                } else {
                    _ = container.quickBarSubmit()
                }
            } label: {
                Image(systemName: container.isQuickBarSending ? "stop.fill" : "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(sendButtonForeground)
                    .frame(width: 42, height: 42)
                    .background {
                        sendButtonSurface
                    }
            }
            .buttonStyle(.plain)
            .disabled(!container.isQuickBarSending && !canSendDraft)
            .onHover { isSendHovered = $0 }
            .accessibilityLabel(container.isQuickBarSending ? "Stop generation" : "Send message")
        }
        .frame(minHeight: 42)
        .padding(.leading, HushSpacing.xs)
        .padding(.top, HushSpacing.xs)
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
            HStack(spacing: HushSpacing.xs + 1) {
                Text(selectedModelDisplayName)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(HushTypography.scaled(14, weight: .semibold))
            .foregroundStyle(palette.quickBarControlForeground)
            .padding(.horizontal, HushSpacing.sm)
            .padding(.vertical, HushSpacing.xs + 2)
            .background {
                controlGlassSurface(
                    shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    isHovered: isModelHovered,
                    registration: QuickBarNativeGlassRegistration(
                        id: .modelControl,
                        transition: .matchedGeometry
                    )
                )
            }
        }
        .buttonStyle(.plain)
        .onHover { isModelHovered = $0 }
    }

    private var modelsForMenu: [ModelDescriptor] {
        let models = availableModels.isEmpty ? fallbackModels() : availableModels
        let filtered = models.filter {
            $0.capabilities.contains(.text) || $0.supportedOutputs.contains(.text)
        }
        return filtered.isEmpty ? fallbackModels() : filtered
    }

    private var selectedModelDisplayName: String {
        modelsForMenu.first(where: { $0.id == container.quickBarState.selectedModelID })?.displayName
            ?? container.quickBarState.selectedModelID
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

    @ViewBuilder
    private var sendButtonSurface: some View {
        if container.isQuickBarSending && !usesNativeGlass {
            Circle()
                .fill(palette.destructiveActionBackground.opacity(0.58))
                .overlay(
                    Circle()
                        .stroke(palette.destructiveActionForeground.opacity(0.20), lineWidth: 0.5)
                )
        } else {
            actionGlassSurface(
                shape: Circle(),
                isHovered: isSendHovered,
                isEnabled: canSendDraft,
                isSending: container.isQuickBarSending,
                registration: QuickBarNativeGlassRegistration(
                    id: .sendAction,
                    transition: .matchedGeometry
                )
            )
        }
    }

    private var composerSurface: some View {
        QuickBarLiquidGlassSurface(
            shape: RoundedRectangle(cornerRadius: 28, style: .continuous),
            baseTint: palette.quickBarSurface,
            highlightTint: palette.quickBarSurfaceStroke,
            shadowColor: palette.splitPaneShadow,
            style: .composerShell(isExpanded: container.quickBarState.isExpanded)
        )
    }

    private var providerEmptySurface: some View {
        QuickBarLiquidGlassSurface(
            shape: RoundedRectangle(cornerRadius: 28, style: .continuous),
            baseTint: palette.quickBarSurface,
            highlightTint: palette.quickBarSurfaceStroke,
            shadowColor: palette.splitPaneShadow,
            style: .composerShell(isExpanded: false)
        )
    }

    private func controlGlassSurface<S: InsettableShape>(
        shape: S,
        isHovered: Bool,
        registration: QuickBarNativeGlassRegistration
    ) -> some View {
        QuickBarGlassSurface(
            shape: shape,
            registration: registration,
            namespace: activeGlassNamespace,
            nativeStyle: nativeControlStyle(isHovered: isHovered),
            fallbackBaseTint: isHovered ? palette.quickBarControlFillHover : palette.quickBarControlFill,
            fallbackHighlightTint: palette.quickBarSurfaceStroke,
            fallbackShadowColor: palette.splitPaneShadow,
            fallbackStyle: .control(isHovered: isHovered)
        )
    }

    private func actionGlassSurface<S: InsettableShape>(
        shape: S,
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool,
        registration: QuickBarNativeGlassRegistration
    ) -> some View {
        QuickBarGlassSurface(
            shape: shape,
            registration: registration,
            namespace: activeGlassNamespace,
            nativeStyle: nativeActionStyle(
                isHovered: isHovered,
                isEnabled: isEnabled,
                isSending: isSending
            ),
            fallbackBaseTint: fallbackActionBaseTint(
                isEnabled: isEnabled,
                isSending: isSending
            ),
            fallbackHighlightTint: fallbackActionHighlightTint(
                isEnabled: isEnabled,
                isSending: isSending
            ),
            fallbackShadowColor: palette.splitPaneShadow,
            fallbackStyle: fallbackActionStyle(
                isHovered: isHovered,
                isEnabled: isEnabled,
                isSending: isSending
            )
        )
    }

    private var usesNativeGlass: Bool {
        if #available(macOS 26.0, *) {
            return prefersNativeGlass && glassNamespace != nil
        }
        return false
    }

    private var activeGlassNamespace: Namespace.ID? {
        usesNativeGlass ? glassNamespace : nil
    }

    private func nativeControlStyle(isHovered: Bool) -> QuickBarNativeGlassStyle {
        let tint: Color? = if isHovered {
            palette.quickBarControlFillHover.opacity(
                container.settings.theme.usesDarkAppearance ? 0.22 : 0.12
            )
        } else {
            nil
        }

        return QuickBarNativeGlassStyle(
            tint: tint,
            isInteractive: true,
            strokeColor: palette.quickBarSurfaceStroke.opacity(isHovered ? 0.26 : 0.18),
            shadowColor: palette.splitPaneShadow,
            shadowOpacity: 0.04,
            shadowRadius: 5,
            shadowYOffset: 1
        )
    }

    private func nativeActionStyle(
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool
    ) -> QuickBarNativeGlassStyle {
        let tint: Color? = if isSending {
            palette.destructiveActionBackground.opacity(
                container.settings.theme.usesDarkAppearance
                    ? (isHovered ? 0.26 : 0.20)
                    : (isHovered ? 0.18 : 0.14)
            )
        } else if isEnabled {
            palette.quickBarButtonFill.opacity(
                container.settings.theme.usesDarkAppearance
                    ? (isHovered ? 0.24 : 0.18)
                    : (isHovered ? 0.18 : 0.14)
            )
        } else {
            nil
        }

        let stroke: Color = if isSending {
            palette.destructiveActionBackground.opacity(isHovered ? 0.36 : 0.28)
        } else if isEnabled {
            palette.quickBarButtonFill.opacity(isHovered ? 0.32 : 0.24)
        } else {
            palette.quickBarSurfaceStroke.opacity(0.16)
        }

        return QuickBarNativeGlassStyle(
            tint: tint,
            isInteractive: true,
            strokeColor: stroke,
            shadowColor: palette.splitPaneShadow,
            shadowOpacity: 0.05,
            shadowRadius: 5,
            shadowYOffset: 1
        )
    }

    private func fallbackActionBaseTint(
        isEnabled: Bool,
        isSending: Bool
    ) -> Color {
        if isSending {
            return palette.destructiveActionBackground
        }
        return isEnabled ? palette.quickBarButtonFill : palette.quickBarDisabledButtonFill
    }

    private func fallbackActionHighlightTint(
        isEnabled: Bool,
        isSending: Bool
    ) -> Color {
        if isSending {
            return palette.destructiveActionForeground
        }
        return isEnabled ? palette.quickBarButtonFill : palette.quickBarSurfaceStroke
    }

    private func fallbackActionStyle(
        isHovered: Bool,
        isEnabled: Bool,
        isSending: Bool
    ) -> QuickBarLiquidGlassStyle {
        if isSending {
            return .actionButton(isHovered: isHovered)
        }
        return .actionButton(isHovered: isHovered && isEnabled)
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
