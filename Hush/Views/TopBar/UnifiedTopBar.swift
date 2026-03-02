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
            Color.clear
                .frame(width: showsSplit ? HushSpacing.sidebarWidth : 0, height: barHeight)
                .background(.ultraThinMaterial)

            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

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
                .background(HushColors.rootBackground)
                .clipShape(shape)
                .shadow(
                    color: HushColors.splitPaneShadow.opacity((showSidebar && !isSettingsMode) ? 1 : 0),
                    radius: HushSpacing.splitPaneShadowRadius,
                    x: HushSpacing.splitPaneShadowX,
                    y: 0
                )
                .overlay {
                    if showSidebar && !isSettingsMode {
                        shape
                            .strokeBorder(HushColors.splitPaneEdgeStroke, lineWidth: 1)
                            .mask(
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .frame(width: rightPaneCornerRadius + 2)
                                    Spacer(minLength: 0)
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
    }
}

struct ChatTopBar: View {
    @Binding var showSidebar: Bool

    var body: some View {
        HStack(alignment: .center, spacing: HushSpacing.md) {
            Spacer(minLength: 0)
        }
        .padding(.leading, showSidebar ? 18 : HushSpacing.trafficLightInset + 28)
        .padding(.trailing, 18)
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
