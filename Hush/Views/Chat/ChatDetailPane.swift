import SwiftUI

struct ChatDetailPane: View {
    @EnvironmentObject private var container: AppContainer

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
        ZStack {
            VStack(spacing: 0) {
                HotScenePoolRepresentable()
                    .environmentObject(container)
                    .frame(maxHeight: .infinity)
                    .clipped()

                ComposerDock()
            }

            if container.isActiveConversationLoading, container.messages.isEmpty {
                loadingOverlay
            } else if let error = container.activeConversationLoadError {
                errorOverlay(message: error)
            }

            if SwitchOverlayDebug.isEnabled {
                switchDebugOverlay
            }
        }
    }

    private var switchDebugOverlay: some View {
        Text(
            "conversation=\(container.activeConversationId ?? "nil") " +
                "messages=\(container.messages.count) " +
                "loading=\(container.isActiveConversationLoading)"
        )
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.55), in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.top, 10)
        .padding(.trailing, 12)
        .allowsHitTesting(false)
    }

    private var loadingOverlay: some View {
        VStack(spacing: HushSpacing.sm) {
            ProgressView()
                .controlSize(.small)

            Text("Loading thread...")
                .font(HushTypography.caption)
                .foregroundStyle(HushColors.secondaryText)
        }
        .padding(.horizontal, HushSpacing.xl)
        .padding(.vertical, HushSpacing.lg)
        .background(HushColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HushColors.subtleStroke, lineWidth: 1)
        )
    }

    private func errorOverlay(message: String) -> some View {
        VStack(spacing: HushSpacing.sm) {
            Text("Failed to load thread")
                .font(HushTypography.captionBold)
                .foregroundStyle(HushColors.errorText)

            Text(message)
                .font(HushTypography.caption)
                .foregroundStyle(HushColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(6)

            Button {
                container.retryActiveConversationLoad()
            } label: {
                Text("Retry")
                    .font(HushTypography.captionBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, HushSpacing.lg)
                    .padding(.vertical, HushSpacing.sm)
                    .background(Color.cyan.opacity(0.18), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, HushSpacing.xl)
        .padding(.vertical, HushSpacing.lg)
        .background(HushColors.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(HushColors.subtleStroke, lineWidth: 1)
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
