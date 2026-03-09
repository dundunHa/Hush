import SwiftUI

struct SplitTopBar: View {
    @Binding var showSidebar: Bool
    let isSettingsMode: Bool

    private let barHeight: CGFloat = HushSpacing.topBarHeight
    private var rightPaneCornerRadius: CGFloat {
        (showSidebar && !isSettingsMode) ? min(HushSpacing.splitPaneCornerRadius, barHeight / 2) : 0
    }

    private var showsSplit: Bool {
        showSidebar || isSettingsMode
    }

    var body: some View {
        HStack(spacing: 0) {
            splitBackground
                .frame(width: showsSplit ? HushSpacing.sidebarWidth : 0, height: barHeight)

            ZStack {
                Rectangle()
                    .fill(
                        (showSidebar && !isSettingsMode)
                            ? HushColors.sidebarBackground : HushColors.rootBackground
                    )

                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: rightPaneCornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0,
                    style: .continuous
                )

                if showSidebar && !isSettingsMode {
                    shape
                        .fill(HushColors.rootBackground)
                        .shadow(
                            color: HushColors.splitPaneShadow,
                            radius: HushSpacing.splitPaneShadowRadius,
                            x: HushSpacing.splitPaneShadowX,
                            y: 0
                        )
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: rightPaneCornerRadius + (HushSpacing.splitPaneShadowRadius * 2))
                        }
                }

                Group {
                    if !isSettingsMode {
                        ChatTopBar(showSidebar: $showSidebar)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: barHeight)
                .background(HushColors.rootBackground)
                .clipShape(shape)
                .overlay {
                    if showSidebar && !isSettingsMode {
                        shape
                            .strokeBorder(HushColors.splitPaneEdgeStroke, lineWidth: 1)
                            .mask(
                                ZStack(alignment: .topLeading) {
                                    Rectangle()
                                        .frame(width: 2)

                                    Rectangle()
                                        .frame(width: rightPaneCornerRadius + 2)
                                        .padding(.bottom, 1)
                                }
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: barHeight)
        }
        .frame(height: barHeight)
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
        .themeRefreshAware()
    }

    private var splitBackground: some View {
        Rectangle()
            .fill(HushColors.sidebarBackground)
    }
}

struct ChatTopBar: View {
    @EnvironmentObject private var container: AppContainer
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
            return HushColors.errorText
        }
        if let activeConversationID, container.runningConversationIds.contains(activeConversationID) {
            return HushColors.primaryText
        }
        return HushColors.secondaryText
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
