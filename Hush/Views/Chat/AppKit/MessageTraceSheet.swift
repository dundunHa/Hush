import AppKit
import SwiftUI

@MainActor
enum MessageTraceSheetPresenter {
    static func present(
        message: ChatMessage,
        rawDebugInfoJSON: String,
        theme: AppTheme,
        from parentWindow: NSWindow?
    ) {
        guard let parentWindow else { return }
        guard parentWindow.attachedSheet == nil else { return }

        let snapshot = MessageTraceSheetSnapshot(
            message: message,
            rawDebugInfoJSON: rawDebugInfoJSON
        )
        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 720),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        sheetWindow.isReleasedWhenClosed = false
        sheetWindow.titleVisibility = .hidden
        sheetWindow.titlebarAppearsTransparent = true
        sheetWindow.standardWindowButton(.zoomButton)?.isHidden = true
        sheetWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true

        let closeSheet = { [weak parentWindow, weak sheetWindow] in
            guard let sheetWindow else { return }
            if let parentWindow {
                parentWindow.endSheet(sheetWindow)
            } else {
                sheetWindow.close()
            }
        }

        sheetWindow.contentViewController = NSHostingController(
            rootView: MessageTraceSheetView(
                snapshot: snapshot,
                theme: theme,
                onClose: closeSheet
            )
        )
        parentWindow.beginSheet(sheetWindow)
    }
}

private struct MessageTraceSheetSnapshot {
    let message: ChatMessage
    let rawDebugInfoJSON: String
    let parsedDebugInfo: MessageDebugInfo?

    init(message: ChatMessage, rawDebugInfoJSON: String) {
        self.message = message
        self.rawDebugInfoJSON = rawDebugInfoJSON
        parsedDebugInfo = MessageDebugInfo.decode(from: rawDebugInfoJSON)
    }

    var title: String {
        switch message.role {
        case .assistant:
            return "Assistant Request Trace"
        case .user:
            return "User Request Trace"
        case .tool:
            return "Tool Request Trace"
        case .system:
            return "System Request Trace"
        }
    }

    var sortedEvents: [MessageTraceEvent] {
        (parsedDebugInfo?.traceEvents ?? []).sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    var summaryRows: [(String, String)] {
        guard let parsedDebugInfo else { return [] }

        return [
            ("Request ID", parsedDebugInfo.requestID),
            ("Provider", parsedDebugInfo.providerID),
            ("Model", parsedDebugInfo.modelID),
            ("Kind", parsedDebugInfo.requestKind),
            ("Endpoint", parsedDebugInfo.endpoint),
            ("Request URL", parsedDebugInfo.requestURL),
            ("HTTP Method", parsedDebugInfo.httpMethod),
            ("Status", parsedDebugInfo.responseStatusCode.map(String.init)),
            ("Route", parsedDebugInfo.routeDecision),
            ("Provider Error", parsedDebugInfo.providerError)
        ].compactMap { title, value in
            guard let value, !value.isEmpty else { return nil }
            return (title, value)
        }
    }
}

private struct MessageTraceSheetView: View {
    let snapshot: MessageTraceSheetSnapshot
    let theme: AppTheme
    let onClose: () -> Void

    private var palette: HushThemePalette {
        HushColors.palette(for: theme)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .overlay(palette.separator)
            ScrollView {
                VStack(alignment: .leading, spacing: HushSpacing.lg) {
                    summaryCard
                    if snapshot.sortedEvents.isEmpty {
                        emptyTimelineCard
                    } else {
                        ForEach(snapshot.sortedEvents) { event in
                            eventCard(event)
                        }
                    }
                    rawJSONCard
                }
                .padding(HushSpacing.lg)
            }
            Divider()
                .overlay(palette.separator)
            footer
        }
        .frame(minWidth: 860, minHeight: 720)
        .background(palette.rootBackground)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: HushSpacing.xs) {
                Text(snapshot.title)
                    .font(HushTypography.pageTitle)
                    .foregroundStyle(palette.primaryText)
                Text(Self.timestampFormatter.string(from: snapshot.message.createdAt))
                    .font(HushTypography.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()

            Button("Close", action: onClose)
                .buttonStyle(.plain)
                .padding(.horizontal, HushSpacing.md)
                .padding(.vertical, HushSpacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.softFillStrong)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(palette.subtleStroke, lineWidth: 1)
                        )
                )
                .foregroundStyle(palette.primaryText)
        }
        .padding(HushSpacing.lg)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            Text("Summary")
                .font(HushTypography.heading)
                .foregroundStyle(palette.primaryText)

            if snapshot.summaryRows.isEmpty {
                Text("This message only has raw trace JSON.")
                    .font(HushTypography.body)
                    .foregroundStyle(palette.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: HushSpacing.sm) {
                    ForEach(Array(snapshot.summaryRows.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.0)
                                .font(HushTypography.captionBold)
                                .foregroundStyle(palette.secondaryText)
                            SelectableTraceText(text: row.1, palette: palette)
                        }
                    }
                }
            }
        }
        .padding(HushSpacing.lg)
        .background(cardBackground)
    }

    private var emptyTimelineCard: some View {
        VStack(alignment: .leading, spacing: HushSpacing.sm) {
            Text("Timeline")
                .font(HushTypography.heading)
                .foregroundStyle(palette.primaryText)
            Text("No structured timeline events were recorded for this message.")
                .font(HushTypography.body)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(HushSpacing.lg)
        .background(cardBackground)
    }

    private func eventCard(_ event: MessageTraceEvent) -> some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(event.title)
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text(Self.eventTimeFormatter.string(from: event.timestamp))
                    .font(HushTypography.caption)
                    .foregroundStyle(palette.tertiaryText)
            }

            Text(event.category.rawValue.uppercased())
                .font(HushTypography.captionBold)
                .foregroundStyle(eventBadgeColor(event.category))
                .padding(.horizontal, HushSpacing.sm)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(palette.softFillStrong)
                )

            if let summary = event.summary, !summary.isEmpty {
                Text(summary)
                    .font(HushTypography.body)
                    .foregroundStyle(palette.secondaryText)
            }

            if !event.sections.isEmpty {
                VStack(alignment: .leading, spacing: HushSpacing.md) {
                    ForEach(Array(event.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: HushSpacing.xs) {
                            Text(section.title)
                                .font(HushTypography.captionBold)
                                .foregroundStyle(palette.secondaryText)
                            SelectableTraceText(text: section.content, palette: palette, isMonospaced: true)
                        }
                    }
                }
            }
        }
        .padding(HushSpacing.lg)
        .background(cardBackground)
    }

    private var rawJSONCard: some View {
        VStack(alignment: .leading, spacing: HushSpacing.md) {
            HStack {
                Text("Raw JSON")
                    .font(HushTypography.heading)
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Button("Copy JSON") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(snapshot.rawDebugInfoJSON, forType: .string)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
            }

            SelectableTraceText(
                text: snapshot.rawDebugInfoJSON,
                palette: palette,
                isMonospaced: true
            )
        }
        .padding(HushSpacing.lg)
        .background(cardBackground)
    }

    private var footer: some View {
        HStack {
            Text("Trace is stored on the message and updates with the request lifecycle.")
                .font(HushTypography.caption)
                .foregroundStyle(palette.tertiaryText)
            Spacer()
        }
        .padding(.horizontal, HushSpacing.lg)
        .padding(.vertical, HushSpacing.md)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.subtleStroke, lineWidth: 1)
            )
    }

    private func eventBadgeColor(_ category: MessageTraceEventCategory) -> Color {
        switch category {
        case .request:
            return palette.accent
        case .response:
            return palette.successText
        case .stream:
            return palette.badgeUnread
        case .error:
            return palette.errorText
        case .lifecycle:
            return palette.secondaryText
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

private struct SelectableTraceText: View {
    let text: String
    let palette: HushThemePalette
    var isMonospaced: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(isMonospaced ? HushTypography.monospaced(13) : HushTypography.body)
                .foregroundStyle(palette.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(HushSpacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.softFillStrong)
                )
        }
    }
}
