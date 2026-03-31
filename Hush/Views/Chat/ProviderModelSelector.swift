import SwiftUI

struct ProviderModelSelector<ProviderLabel: View, ModelLabel: View>: View {
    let surfaceStyle: ConversationSurfaceStyle
    let providers: [ProviderConfiguration]
    let models: [ModelDescriptor]
    let selectedProviderID: String
    let selectedProviderName: String
    let selectedModelID: String
    let selectedModelDisplayName: String
    let showsProviderMenu: Bool
    let providerHelpText: String?
    let modelHelpText: String?
    let onSelectProvider: (ProviderConfiguration) -> Void
    let onSelectModel: (ModelDescriptor) -> Void
    let providerLabel: (String, Bool) -> ProviderLabel
    let modelLabel: (String, Bool) -> ModelLabel

    @State private var isProviderHovered = false
    @State private var isModelHovered = false

    var body: some View {
        Group {
            if showsProviderMenu {
                providerMenu
            }
            modelMenu
        }
    }

    private var providerMenu: some View {
        let menu = Menu {
            ForEach(providers) { provider in
                Button {
                    onSelectProvider(provider)
                } label: {
                    HStack(spacing: HushSpacing.sm) {
                        if provider.id == selectedProviderID {
                            Image(systemName: "checkmark")
                        }
                        Text(provider.name)
                    }
                }
            }
        } label: {
            providerLabel(selectedProviderName, isProviderHovered)
        }
        .buttonStyle(.plain)
        .onHover { isProviderHovered = $0 }

        return styledMenu(menu)
            .help(providerHelpText ?? selectedProviderName)
    }

    private var modelMenu: some View {
        let menu = Menu {
            ForEach(models) { model in
                Button {
                    onSelectModel(model)
                } label: {
                    HStack(spacing: HushSpacing.sm) {
                        if model.id == selectedModelID {
                            Image(systemName: "checkmark")
                        }
                        Text(model.displayName)
                    }
                }
            }
        } label: {
            modelLabel(selectedModelDisplayName, isModelHovered)
        }
        .buttonStyle(.plain)
        .onHover { isModelHovered = $0 }

        return styledMenu(menu)
            .help(modelHelpText ?? selectedModelDisplayName)
    }

    @ViewBuilder
    private func styledMenu<Content: View>(_ content: Content) -> some View {
        switch surfaceStyle {
        case .main:
            content
        case .quickBar:
            content.menuStyle(.borderlessButton)
        }
    }
}
