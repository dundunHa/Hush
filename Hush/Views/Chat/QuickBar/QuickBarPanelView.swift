import SwiftUI

struct QuickBarPanelView: View {
    @EnvironmentObject private var container: AppContainer

    private var palette: HushThemePalette {
        HushColors.palette(for: container.settings.theme)
    }

    var body: some View {
        Group {
            if container.quickBarState.isExpanded {
                expandedBody
            } else {
                compactBody
            }
        }
    }

    private var compactBody: some View {
        QuickBarComposer()
            .environmentObject(container)
            .padding(.horizontal, HushSpacing.sm)
            .padding(.vertical, HushSpacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var expandedBody: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: HushSpacing.md) {
                handle

                QuickConversationSurface(
                    conversationId: container.quickBarState.conversationId,
                    messages: container.quickBarState.messages,
                    isSending: container.isQuickBarSending,
                    generation: container.quickBarState.generation
                )
                .environmentObject(container)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(transcriptSurface)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))

                QuickBarComposer()
                    .environmentObject(container)
            }
            .padding(.horizontal, HushSpacing.lg + 2)
            .padding(.top, HushSpacing.sm + 2)
            .padding(.bottom, HushSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            controls
                .padding(.top, HushSpacing.md)
                .padding(.trailing, HushSpacing.md)
        }
        .background(backgroundShell)
    }

    private var handle: some View {
        Capsule(style: .continuous)
            .fill(handleColor)
            .frame(width: 132, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: HushSpacing.sm) {
            if container.isQuickBarSending {
                Circle()
                    .fill(palette.quickBarControlForeground.opacity(0.88))
                    .frame(width: 7, height: 7)
            }

            Menu {
                Button("New Chat") {
                    container.resetQuickBarConversation()
                }
                .disabled(container.isQuickBarSending)

                if !container.quickBarState.messages.isEmpty {
                    Button("Open in Main Chat") {
                        container.continueQuickBarInMainChat()
                    }
                    .disabled(container.isQuickBarSending)
                }
            } label: {
                toolbarOrb(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)

            Button {
                container.closeQuickBar()
            } label: {
                toolbarOrb(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("w", modifiers: [.option])
        }
    }

    private var transcriptSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        return shape
            .fill(palette.quickBarSurface.opacity(0.92))
            .overlay(
                shape
                    .stroke(palette.quickBarSurfaceStroke.opacity(0.88), lineWidth: 0.5)
            )
    }

    private var backgroundShell: some View {
        let shape = RoundedRectangle(cornerRadius: 38, style: .continuous)

        return shape
            .fill(palette.quickBarSurface)
            .overlay(
                shape
                    .stroke(palette.quickBarSurfaceStroke.opacity(0.88), lineWidth: 0.5)
            )
            .shadow(
                color: palette.splitPaneShadow.opacity(0.08),
                radius: 8,
                x: 0,
                y: 2
            )
    }

    private var handleColor: Color {
        palette.quickBarSurfaceStroke.opacity(0.96)
    }

    private func toolbarOrb(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(palette.quickBarControlMuted)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(palette.quickBarControlFill)
                    .overlay(
                        Circle()
                            .stroke(palette.quickBarSurfaceStroke.opacity(0.82), lineWidth: 0.5)
                    )
            )
    }
}
