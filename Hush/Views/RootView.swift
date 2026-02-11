import SwiftUI
import Foundation

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var showSettings: Bool = false
    @State private var selectedTopicMessageID: UUID?

    var body: some View {
        NavigationSplitView {
            ConversationSidebarView(selectedTopicMessageID: $selectedTopicMessageID)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
        } detail: {
            ChatDetailPane(
                showSettings: $showSettings,
                selectedTopicMessageID: $selectedTopicMessageID
            )
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(preferredScheme(forTheme: container.settings.theme))
        .sheet(isPresented: $container.showQuickBar) {
            QuickBarView()
                .frame(minWidth: 520, minHeight: 180)
        }
        .sheet(isPresented: $showSettings) {
            SettingsModalView()
                .frame(minWidth: 760, minHeight: 500)
        }
    }

    private func preferredScheme(forTheme theme: AppTheme) -> ColorScheme {
        switch theme {
        case .dark:
            return .dark
        }
    }
}

private enum DarkPalette {
    static let rootBackground = Color(red: 0.08, green: 0.09, blue: 0.11)
    static let sidebarBackground = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let cardBackground = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let composerBackground = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let composerEditorBackground = Color.black.opacity(0.24)
    static let separator = Color.white.opacity(0.10)
    static let subtleStroke = Color.white.opacity(0.12)
    static let secondaryText = Color.white.opacity(0.62)
}

private struct ConversationSidebarView: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var selectedTopicMessageID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Chats")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(conversationTopics.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            List(selection: $selectedTopicMessageID) {
                Section("History") {
                    if conversationTopics.isEmpty {
                        Text("No conversation yet")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(conversationTopics) { topic in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(topic.title)
                                    .lineLimit(1)
                                Text(topic.createdAt, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(Optional(topic.id))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(DarkPalette.sidebarBackground)
    }

    private var conversationTopics: [ConversationTopic] {
        container.messages
            .filter { $0.role == .user }
            .reversed()
            .map { message in
                ConversationTopic(
                    id: message.id,
                    title: topicTitle(from: message.content),
                    createdAt: message.createdAt
                )
            }
    }

    private func topicTitle(from content: String) -> String {
        let firstNonEmptyLine = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "Untitled"

        let maxLength = 44
        if firstNonEmptyLine.count <= maxLength {
            return firstNonEmptyLine
        }
        return String(firstNonEmptyLine.prefix(maxLength)) + "…"
    }
}

private struct ConversationTopic: Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date
}

private struct ChatDetailPane: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var showSettings: Bool
    @Binding var selectedTopicMessageID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            ChatTopBar(showSettings: $showSettings)

            Divider()
                .overlay(DarkPalette.separator)

            ChatScrollStage(selectedTopicMessageID: $selectedTopicMessageID)

            Divider()
                .overlay(DarkPalette.separator)

            ComposerDock()
        }
        .background(DarkPalette.rootBackground.ignoresSafeArea())
    }
}

private struct ChatTopBar: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var showSettings: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hush")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(container.statusMessage)
                    .font(.caption)
                    .foregroundStyle(DarkPalette.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button("Quick Bar") {
                    container.toggleQuickBar()
                }
                .help("Command + Option + K")

                if container.isSending {
                    Button("Stop") {
                        container.stopActiveRequest()
                    }
                    .tint(.red)
                }

                Button("Clear Chat") {
                    container.resetConversation()
                }

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

private struct ChatScrollStage: View {
    @EnvironmentObject private var container: AppContainer
    @Binding var selectedTopicMessageID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(container.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if container.isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Generating response...")
                                    .foregroundStyle(.secondary)
                                if !container.pendingQueue.isEmpty {
                                    Text("\(container.pendingQueue.count) queued")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 14)
            }
            .onChange(of: container.messages.count) { _, _ in
                if let lastID = container.messages.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: selectedTopicMessageID) { _, newValue in
                guard let topicID = newValue else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(topicID, anchor: .top)
                }
            }
        }
    }
}

private struct ComposerDock: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextEditor(text: $container.draft)
                .font(.body)
                .frame(minHeight: 78, maxHeight: 140)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DarkPalette.composerEditorBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DarkPalette.subtleStroke, lineWidth: 1)
                )

            if container.isSending {
                Button {
                    container.stopActiveRequest()
                } label: {
                    Text("Stop")
                        .fontWeight(.semibold)
                        .frame(width: 84)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            Button {
                container.sendDraft()
            } label: {
                Text("Send")
                    .fontWeight(.semibold)
                    .frame(width: 84)
            }
            .buttonStyle(.borderedProminent)
            .disabled(container.isSending && container.isQueueFull)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DarkPalette.composerBackground)
    }
}

private struct SettingsModalView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker(
                        "Theme",
                        selection: Binding(
                            get: { container.settings.theme },
                            set: { container.settings.theme = $0 }
                        )
                    ) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }

                    Text("Dark is currently the only implemented theme.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Provider") {
                    Text("Provider configuration UI will be implemented in a later phase.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role.rawValue.capitalized)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DarkPalette.secondaryText)

            Text(message.content)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: alignment)
        .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(bubbleStroke, lineWidth: 1)
        )
    }

    private var alignment: Alignment {
        switch message.role {
        case .user:
            return .trailing
        default:
            return .leading
        }
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.30)
        case .assistant:
            return DarkPalette.cardBackground
        case .tool:
            return Color.orange.opacity(0.20)
        case .system:
            return Color.gray.opacity(0.24)
        }
    }

    private var bubbleStroke: Color {
        switch message.role {
        case .user:
            return Color.blue.opacity(0.46)
        case .assistant:
            return DarkPalette.subtleStroke
        case .tool:
            return Color.orange.opacity(0.32)
        case .system:
            return Color.white.opacity(0.16)
        }
    }
}
