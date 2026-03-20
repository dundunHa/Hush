import SwiftUI

private struct ComposerDockHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = HushSpacing.xl + HushSpacing.sm

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ChatDetailPane: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.hushThemePalette) private var palette
    @State private var isConfigDrawerPresented = false
    @State private var composerDockHeight: CGFloat = HushSpacing.xl + HushSpacing.sm

    private enum SwitchOverlayDebug {
        static var isEnabled: Bool {
            #if DEBUG
                guard let raw = ProcessInfo.processInfo.environment["HUSH_SWITCH_DEBUG"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                else {
                    return false
                }
                return raw == "1" || raw == "true" || raw == "yes"
            #else
                return false
            #endif
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            conversationLayer
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ComposerDock(isConfigDrawerPresented: $isConfigDrawerPresented)
                .background(composerDockHeightReader)
                .zIndex(3)
        }
        .onPreferenceChange(ComposerDockHeightPreferenceKey.self) { newHeight in
            let normalizedHeight = max(HushSpacing.xl + HushSpacing.sm, ceil(newHeight))
            guard abs(composerDockHeight - normalizedHeight) > 0.5 else { return }
            composerDockHeight = normalizedHeight
        }
        .animation(.spring(response: 0.24, dampingFraction: 0.9), value: isConfigDrawerPresented)
    }

    private var conversationLayer: some View {
        ZStack(alignment: .trailing) {
            HotScenePoolRepresentable(bottomReservedHeight: composerDockHeight)
                .environmentObject(container)
                .frame(maxHeight: .infinity)
                .clipped()

            if container.isActiveConversationLoading, container.messages.isEmpty {
                loadingOverlay
            } else if let error = container.activeConversationLoadError {
                errorOverlay(message: error)
            }

            if isConfigDrawerPresented {
                drawerDismissLayer
                    .zIndex(1)
            }

            if SwitchOverlayDebug.isEnabled {
                switchDebugOverlay
            }

            if isConfigDrawerPresented {
                configDrawer
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
        }
    }

    private var composerDockHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: ComposerDockHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private var switchDebugOverlay: some View {
        Text(
            "conversation=\(container.activeConversationId ?? "nil") " +
                "messages=\(container.messages.count) " +
                "loading=\(container.isActiveConversationLoading)"
        )
        .font(HushTypography.monospaced(11, weight: .semibold))
        .foregroundStyle(palette.debugOverlayForeground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.debugOverlayBackground, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 10)
        .padding(.trailing, 12)
        .allowsHitTesting(false)
    }

    private var drawerDismissLayer: some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                isConfigDrawerPresented = false
            }
    }

    private var configDrawer: some View {
        ChatConfigDrawer(
            parameters: $container.settings.parameters,
            onClose: {
                isConfigDrawerPresented = false
            }
        )
        .padding(.vertical, HushSpacing.lg)
        .padding(.trailing, HushSpacing.lg)
    }

    private var loadingOverlay: some View {
        VStack(spacing: HushSpacing.sm) {
            ProgressView()
                .controlSize(.small)

            Text("Loading thread...")
                .font(HushTypography.caption)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.horizontal, HushSpacing.xl)
        .padding(.vertical, HushSpacing.lg)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.subtleStroke, lineWidth: 1)
        )
    }

    private func errorOverlay(message: String) -> some View {
        VStack(spacing: HushSpacing.sm) {
            Text("Failed to load thread")
                .font(HushTypography.captionBold)
                .foregroundStyle(palette.errorText)

            Text(message)
                .font(HushTypography.caption)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(6)

            Button {
                container.retryActiveConversationLoad()
            } label: {
                Text("Retry")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(palette.primaryActionForeground)
                    .padding(.horizontal, HushSpacing.lg)
                    .padding(.vertical, HushSpacing.sm)
                    .background(palette.primaryActionBackground, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(palette.accentMutedStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, HushSpacing.xl)
        .padding(.vertical, HushSpacing.lg)
        .background(palette.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.subtleStroke, lineWidth: 1)
        )
    }
}

#if DEBUG

    // MARK: - Previews

    #Preview("ChatDetailPane — Empty State") {
        ChatDetailPane()
            .environmentObject(AppContainer.makePreviewContainer())
    }

    #Preview("ChatDetailPane — With Messages") {
        ChatDetailPane()
            .environmentObject(
                AppContainer.makePreviewContainer(
                    messages: [
                        ChatMessage(role: .user, content: "Hello, how can you help me today?"),
                        ChatMessage(
                            role: .assistant,
                            content: "I'm here to help! I can assist with coding, writing, analysis, and many other tasks."
                        )
                    ]
                )
            )
    }
#endif
