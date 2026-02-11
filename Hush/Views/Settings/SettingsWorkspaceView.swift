import SwiftUI

struct SettingsWorkspaceView: View {
    @Binding var showSettings: Bool

    @State private var selectedTab: SettingsTab = .general

    private enum SettingsTab: String, CaseIterable {
        case general
        case provider
        case agent
        case prompts
        case data
        case archived
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()
                .overlay(HushColors.separator)

            switch selectedTab {
            case .general:
                GeneralSettingsView()
            case .provider:
                ProviderSettingsView()
            case .agent:
                AgentSettingsView()
            case .prompts:
                PromptLibraryView()
            case .data:
                DataSettingsView()
            case .archived:
                ArchivedThreadsSettingsView()
            }
        }
        .background(HushColors.rootBackground)
    }

    // MARK: - Sidebar

    @State private var isBackHovered: Bool = false

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Button {
                showSettings = false
            } label: {
                Label("Back to app", systemImage: "arrow.left")
                    .font(HushTypography.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HushSpacing.sm)
                    .padding(.vertical, HushSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(isBackHovered ? 0.06 : 0))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(
                                        isBackHovered ? Color.white.opacity(0.12) : .clear,
                                        lineWidth: 1
                                    )
                            )
                            .animation(.easeInOut(duration: 0.15), value: isBackHovered)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onHover { hovering in
                isBackHovered = hovering
            }

            SettingsSidebarItem(
                icon: "gearshape",
                label: "General",
                isSelected: selectedTab == .general
            ) {
                selectedTab = .general
            }

            SettingsSidebarItem(
                icon: "server.rack",
                label: "Provider",
                isSelected: selectedTab == .provider
            ) {
                selectedTab = .provider
            }

            SettingsSidebarItem(
                icon: "person.badge.key",
                label: "AI Agent",
                isSelected: selectedTab == .agent
            ) {
                selectedTab = .agent
            }

            SettingsSidebarItem(
                icon: "text.quote",
                label: "Prompt Library",
                isSelected: selectedTab == .prompts
            ) {
                selectedTab = .prompts
            }

            SettingsSidebarItem(
                icon: "externaldrive",
                label: "Data",
                isSelected: selectedTab == .data
            ) {
                selectedTab = .data
            }

            SettingsSidebarItem(
                icon: "archivebox",
                label: "Archived",
                isSelected: selectedTab == .archived
            ) {
                selectedTab = .archived
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, HushSpacing.md)
        .padding(.vertical, HushSpacing.lg)
        .frame(width: HushSpacing.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
    }
}

// MARK: - SettingsSidebarItem

private struct SettingsSidebarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: HushSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20)

                Text(label)
                    .font(HushTypography.body)
                    .lineLimit(1)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, HushSpacing.md)
            .padding(.vertical, HushSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.10 : (isHovered ? 0.06 : 0)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(
                                isSelected ? HushColors.subtleStroke : (isHovered ? Color.white.opacity(0.12) : .clear),
                                lineWidth: 1
                            )
                    )
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Previews

#if DEBUG

    #Preview("SettingsWorkspaceView — Empty State") {
        let container = AppContainer.makePreviewContainer()
        return SettingsWorkspaceView(showSettings: .constant(true))
            .environmentObject(container)
            .frame(width: 800, height: 560)
    }

    #Preview("SettingsWorkspaceView — With Data") {
        let container = AppContainer.makePreviewContainerWithData()
        return SettingsWorkspaceView(showSettings: .constant(true))
            .environmentObject(container)
            .frame(width: 800, height: 560)
    }

    #Preview("SettingsSidebarItem") {
        VStack(spacing: 8) {
            SettingsSidebarItem(
                icon: "server.rack",
                label: "Provider",
                isSelected: true
            ) {}

            SettingsSidebarItem(
                icon: "person.badge.key",
                label: "AI Agent",
                isSelected: false
            ) {}
        }
        .padding()
        .frame(width: 200)
        .background(HushColors.sidebarBackground)
    }

#endif
