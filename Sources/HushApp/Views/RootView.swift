import SwiftUI
import HushCore

struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView()
        } detail: {
            ChatWorkspaceView()
        }
        .navigationSplitViewStyle(.balanced)
        .background(backgroundGradient)
        .sheet(isPresented: $container.showQuickBar) {
            QuickBarView()
                .environmentObject(container)
                .frame(minWidth: 520, minHeight: 180)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
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
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.96, green: 0.98, blue: 1.0),
                Color(red: 0.90, green: 0.95, blue: 0.98)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct SettingsSidebarView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Configuration")
                    .font(.title2.bold())
                    .padding(.bottom, 4)

                sectionCard(title: "Provider") {
                    Picker("Selected", selection: $container.settings.selectedProviderID) {
                        ForEach(container.settings.providerConfigurations.filter(\.isEnabled)) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)

                    if let selectedIndex = selectedProviderIndex {
                        TextField("Provider Name", text: $container.settings.providerConfigurations[selectedIndex].name)
                        TextField("Endpoint", text: $container.settings.providerConfigurations[selectedIndex].endpoint)
                        TextField(
                            "API Key Env",
                            text: $container.settings.providerConfigurations[selectedIndex].apiKeyEnvironmentVariable
                        )
                    }

                    HStack {
                        Button("Add Placeholder") {
                            container.addPlaceholderProvider()
                        }
                        Button("Remove Selected") {
                            container.removeProvider(id: container.settings.selectedProviderID)
                        }
                        .disabled(container.settings.providerConfigurations.count <= 1)
                    }
                }

                sectionCard(title: "Model") {
                    TextField("Model ID", text: $container.settings.selectedModelID)
                }

                sectionCard(title: "Parameters") {
                    parameterRow("Temperature", value: $container.settings.parameters.temperature, range: 0...2, step: 0.05)
                    parameterRow("Top P", value: $container.settings.parameters.topP, range: 0...1, step: 0.05)

                    HStack {
                        Text("Max Tokens")
                        Spacer()
                        Stepper(
                            "\(container.settings.parameters.maxTokens)",
                            value: $container.settings.parameters.maxTokens,
                            in: 64...16384,
                            step: 64
                        )
                    }
                }

                sectionCard(title: "Quick Bar") {
                    Text("Shortcut: \(container.settings.quickBar.modifiers.joined(separator: "+"))+\(container.settings.quickBar.key)")
                        .font(.footnote)
                    Text("Status: \(container.statusMessage)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .navigationTitle("Hush")
    }

    private var selectedProviderIndex: Int? {
        container.settings.providerConfigurations.firstIndex { $0.id == container.settings.selectedProviderID }
    }

    @ViewBuilder
    private func sectionCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func parameterRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

private struct ChatWorkspaceView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
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
                    .padding(16)
                }
                .onChange(of: container.messages.count) { _, _ in
                    if let lastID = container.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextEditor(text: $container.draft)
                    .font(.body)
                    .frame(minHeight: 70, maxHeight: 130)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                if container.isSending {
                    Button {
                        container.stopActiveRequest()
                    } label: {
                        Text("Stop")
                            .fontWeight(.semibold)
                            .frame(width: 80)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Button {
                    container.sendDraft()
                } label: {
                    Text("Send")
                        .fontWeight(.semibold)
                        .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .disabled(container.isSending && container.isQueueFull)
            }
            .padding(16)
            .background(.regularMaterial)
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message.content)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: alignment)
        .background(color.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
    }

    private var alignment: Alignment {
        switch message.role {
        case .user:
            .trailing
        default:
            .leading
        }
    }

    private var color: Color {
        switch message.role {
        case .system:
            .gray
        case .user:
            .blue
        case .assistant:
            .green
        case .tool:
            .orange
        }
    }
}

