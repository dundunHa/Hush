import SwiftUI

struct QuickBarComposer: View {
    @EnvironmentObject private var container: AppContainer

    @State private var availableModels: [ModelDescriptor] = []
    @State private var catalogStateMessage: String?
    @State private var isModelHovered = false
    @FocusState private var isEditorFocused: Bool

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
                    .background(
                        Capsule(style: .continuous)
                            .fill(palette.quickBarControlFill)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(palette.quickBarSurfaceStroke.opacity(0.85), lineWidth: 0.5)
                            )
                    )
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
                    .background(sendButtonBackground, in: Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                palette.quickBarSurfaceStroke.opacity(
                                    canSendDraft || container.isQuickBarSending ? 0.12 : 0.06
                                ),
                                lineWidth: 0.5
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!container.isQuickBarSending && !canSendDraft)
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
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isModelHovered ? palette.quickBarControlFillHover : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isModelHovered ? palette.quickBarSurfaceStroke.opacity(0.82) : .clear,
                                lineWidth: 0.5
                            )
                    )
            )
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

    private var sendButtonBackground: Color {
        if container.isQuickBarSending {
            return palette.destructiveActionBackground.opacity(0.92)
        }
        if canSendDraft {
            return palette.quickBarButtonFill
        }
        return palette.quickBarDisabledButtonFill
    }

    private var sendButtonForeground: Color {
        if container.isQuickBarSending {
            return palette.destructiveActionForeground
        }
        return canSendDraft ? palette.quickBarButtonForeground : palette.quickBarDisabledButtonForeground
    }

    private var composerSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return shape
            .fill(palette.quickBarSurface)
            .overlay(
                shape
                    .stroke(
                        palette.quickBarSurfaceStroke.opacity(0.92),
                        lineWidth: 0.5
                    )
            )
            .shadow(
                color: palette.splitPaneShadow.opacity(0.08),
                radius: 8,
                x: 0,
                y: 2
            )
    }

    private var providerEmptySurface: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return shape
            .fill(palette.quickBarSurface)
            .overlay(
                shape
                    .stroke(
                        palette.quickBarSurfaceStroke.opacity(0.92),
                        lineWidth: 0.5
                    )
            )
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
