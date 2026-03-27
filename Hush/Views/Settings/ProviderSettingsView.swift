import AppKit
import SwiftUI

struct ProviderSettingsView: View {
    @EnvironmentObject var container: AppContainer
    @Environment(\.hushThemePalette) var palette

    @State var selectedTarget: ProviderEditorTarget?
    @State var editorBaseline: ProviderEditorBaseline?
    @State var pendingSelectionRequest: ProviderEditorSelectionRequest?

    @State var providerName: String = ""
    @State var providerType: ProviderType = .openAI
    @State var endpoint: String = OpenAIProvider.defaultEndpoint
    @State var defaultModelID: String = ""
    @State var pinnedModelIDs: [String] = []
    @State var isEnabled: Bool = false
    @State var apiKey: String = ""
    @State var isAPIKeyRevealed: Bool = false
    @State var hasStoredCredential: Bool = false
    @State var saveMessage: String = ""
    @State var saveFailed: Bool = false
    @State var showDeleteConfirmation: Bool = false
    @State var showDiscardChangesConfirmation: Bool = false
    @State var setAsDefault: Bool = false
    @State var modelSearchText: String = ""
    @State var draftCatalogModels: [ModelDescriptor] = []
    @State var draftCatalogError: String?
    @State var draftCatalogSignature: ProviderCatalogDraftSignature?
    @State var isDraftCatalogRefreshing: Bool = false
    @State var isAdvancedSectionExpanded: Bool = false

    var isCreatingNew: Bool {
        selectedTarget == .new
    }

    var selectedProviderID: String? {
        selectedTarget?.providerID
    }

    var providerIDs: [String] {
        providers.map(\.id)
    }

    var providers: [ProviderConfiguration] {
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

    func providerIcon(for type: ProviderType) -> String {
        switch type {
        case .openAI: "brain"
        #if DEBUG
            case .mock: "ladybug"
        #endif
        }
    }

    func providerAccent(for type: ProviderType) -> Color {
        switch type {
        case .openAI: .green
        #if DEBUG
            case .mock: .gray
        #endif
        }
    }

    func defaultEndpointPlaceholder(for type: ProviderType) -> String {
        switch type {
        case .openAI:
            OpenAIProvider.defaultEndpoint
        #if DEBUG
            case .mock:
                "local://mock-provider"
        #endif
        }
    }

    func defaultNewProviderName(for type: ProviderType) -> String {
        switch type {
        case .openAI:
            "OpenAI Compatible"
        #if DEBUG
            case .mock:
                "Local Mock"
        #endif
        }
    }

    func normalizedDefaultModel(for provider: ProviderConfiguration) -> String {
        provider.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func providerHasCredential(_ provider: ProviderConfiguration) -> Bool {
        provider.hasPersistedAPIKey
    }

    func canSetProviderAsDefault(_ provider: ProviderConfiguration) -> Bool {
        provider.isEnabled && providerHasCredential(provider) && !normalizedDefaultModel(for: provider).isEmpty
    }

    func providerStatusText(_ provider: ProviderConfiguration) -> String {
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

    func providerBadgeText(_ provider: ProviderConfiguration) -> String? {
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

    var isBuiltInProvider: Bool {
        selectedProviderID == OpenAISettingsInput.providerID
    }

    var apiKeyToSave: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Selection State

    var preferredInitialTarget: ProviderEditorTarget? {
        if providers.contains(where: { $0.id == container.settings.selectedProviderID }) {
            return .existing(container.settings.selectedProviderID)
        }
        if let provider = providers.first {
            return .existing(provider.id)
        }
        return nil
    }

    func makeSelectionRequest(
        target: ProviderEditorTarget,
        reloadIfSame: Bool = false
    ) -> ProviderEditorSelectionRequest {
        ProviderEditorSelectionRequest(target: target, reloadIfSame: reloadIfSame)
    }

    // MARK: - Provider List

    var providerListPanel: some View {
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
}

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
