import SwiftUI

struct SplitTopBar: View {
    @Binding var showSidebar: Bool
    let isSettingsMode: Bool

    private let barHeight: CGFloat = HushSpacing.topBarHeight

    var body: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: showSidebar || isSettingsMode ? HushSpacing.sidebarWidth : 0, height: barHeight)
                .background(.ultraThinMaterial)

            Rectangle()
                .fill(HushColors.separator)
                .frame(width: 1)
                .opacity(showSidebar || isSettingsMode ? 1 : 0)

            if !isSettingsMode {
                ChatTopBar(showSidebar: $showSidebar)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: barHeight)
                    .background(HushColors.rootBackground)
            } else {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight)
                    .background(HushColors.rootBackground)
            }
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
