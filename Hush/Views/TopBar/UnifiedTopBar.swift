import SwiftUI

struct SplitTopBar: View {
    @Environment(\.hushTheme) private var theme
    @Environment(\.hushThemePalette) private var palette
    @Binding var showSidebar: Bool
    let isSettingsMode: Bool

    private let barHeight: CGFloat = HushSpacing.topBarHeight
    private var rightPaneCornerRadius: CGFloat {
        (showSidebar && !isSettingsMode) ? min(HushSpacing.splitPaneCornerRadius, barHeight / 2) : 0
    }

    private var showsSplit: Bool {
        showSidebar || isSettingsMode
    }

    private var splitRevealWidth: CGFloat {
        (showSidebar && !isSettingsMode) ? rightPaneCornerRadius + 1 : 0
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: showsSplit ? HushSpacing.sidebarWidth : 0, height: barHeight)

            let shape = UnevenRoundedRectangle(
                topLeadingRadius: rightPaneCornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )

            Group {
                if !isSettingsMode {
                    ChatTopBar(showSidebar: $showSidebar)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: barHeight)
            .background {
                WorkspaceChromeBackground(theme: theme, palette: palette)
            }
            .clipShape(shape)
            .overlay {
                if showSidebar && !isSettingsMode {
                    LeadingPaneBorder(
                        topRadius: rightPaneCornerRadius,
                        bottomRadius: 0,
                        color: palette.splitPaneEdgeStroke
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
        }
        .frame(height: barHeight)
        .background(alignment: .leading) {
            SplitPaneSidebarSurface(
                theme: theme,
                palette: palette,
                sidebarWidth: showsSplit ? HushSpacing.sidebarWidth : 0,
                revealWidth: splitRevealWidth
            )
        }
        .overlay(alignment: .topLeading) {
            if !isSettingsMode {
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        showSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Toggle Sidebar")
                .padding(.leading, HushSpacing.trafficLightInset)
                .frame(height: 28)
            }
        }
        .background(WindowDragArea())
    }
}

struct ChatTopBar: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.hushThemePalette) private var palette
    @Binding var showSidebar: Bool

    var body: some View {
        HStack(alignment: .center, spacing: HushSpacing.md) {
            Text(activeThreadTitle)
                .font(HushTypography.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(titleColor)

            Spacer(minLength: 0)
        }
        .padding(.leading, showSidebar ? 18 : HushSpacing.trafficLightInset + 28)
        .padding(.trailing, 18)
    }

    private var activeConversationID: String? {
        container.activeConversationId
    }

    private var activeThread: ConversationSidebarThread? {
        guard let activeConversationID else { return nil }
        return container.sidebarThreads.first { $0.id == activeConversationID }
    }

    private var activeThreadTitle: String {
        activeThread?.title ?? ConversationSidebarTitleFormatter.placeholderTitle
    }

    private var titleColor: Color {
        if container.activeConversationLoadError != nil {
            return palette.errorText
        }
        if let activeConversationID, container.runningConversationIds.contains(activeConversationID) {
            return palette.primaryText
        }
        return palette.secondaryText
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = DraggableView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}

    final class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            true
        }
    }
}
