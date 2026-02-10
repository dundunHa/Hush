import Foundation
import SwiftUI
import HushCore
import HushProviders
import HushSettings

@MainActor
final class AppContainer: ObservableObject {

    // MARK: - Published State

    @Published var settings: AppSettings {
        didSet {
            persistSettingsIfNeeded(previous: oldValue)
        }
    }
    @Published var messages: [ChatMessage]
    @Published var draft: String = ""
    @Published var showQuickBar: Bool = false
    @Published var statusMessage: String = "Ready"

    // MARK: - Request Lifecycle State

    @Published private(set) var activeRequest: ActiveRequestState?
    @Published private(set) var pendingQueue: [QueueItemSnapshot] = []

    // MARK: - Computed

    var isSending: Bool { activeRequest != nil }
    var isQueueFull: Bool { pendingQueue.count >= RuntimeConstants.pendingQueueCapacity }

    // MARK: - Internal

    private let settingsStore: JSONSettingsStore
    private(set) var registry: ProviderRegistry
    private var activeStreamTask: Task<Void, Never>?

    // MARK: - Debounce State

    private var debounceTask: Task<Void, Never>?
    private(set) var isDirty: Bool = false

    // MARK: - Testing Overrides

    var preflightTimeoutOverride: Duration?
    var generationTimeoutOverride: Duration?

    // MARK: - Init

    private init(
        settings: AppSettings,
        settingsStore: JSONSettingsStore,
        registry: ProviderRegistry
    ) {
        self.settings = settings
        self.settingsStore = settingsStore
        self.registry = registry
        self.messages = []
    }

    static func bootstrap() -> AppContainer {
        let settingsStore = JSONSettingsStore.defaultStore()
        let loadedSettings = (try? settingsStore.load()) ?? .default

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        return AppContainer(
            settings: loadedSettings,
            settingsStore: settingsStore,
            registry: registry
        )
    }

    /// Testing-only initializer for injecting dependencies.
    static func forTesting(
        settings: AppSettings = .default,
        settingsStore: JSONSettingsStore? = nil,
        registry: ProviderRegistry = ProviderRegistry()
    ) -> AppContainer {
        let store = settingsStore ?? JSONSettingsStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent("settings.json")
        )
        return AppContainer(
            settings: settings,
            settingsStore: store,
            registry: registry
        )
    }

    // MARK: - UI Actions

    func toggleQuickBar() {
        showQuickBar.toggle()
    }

    func addPlaceholderProvider() {
        let id = "custom-\(UUID().uuidString.prefix(8))"
        let configuration = ProviderConfiguration(
            id: String(id),
            name: "Custom Provider",
            type: .custom,
            endpoint: "https://api.example.com/v1/chat/completions",
            apiKeyEnvironmentVariable: "HUSH_API_KEY",
            defaultModelID: "model-id",
            isEnabled: true
        )
        settings.providerConfigurations.append(configuration)
    }

    func removeProvider(id: String) {
        settings.providerConfigurations.removeAll { $0.id == id }

        if !settings.providerConfigurations.contains(where: { $0.id == settings.selectedProviderID }) {
            settings.selectedProviderID = settings.providerConfigurations.first?.id ?? "mock"
        }
    }

    // MARK: - Send Pipeline

    func sendDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Queue-full atomic rejection: no user message, no queue append
        if activeRequest != nil && pendingQueue.count >= RuntimeConstants.pendingQueueCapacity {
            statusMessage = "Queue full – request rejected (max \(RuntimeConstants.pendingQueueCapacity))"
            return
        }

        // Append user message to transcript
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)
        draft = ""

        // Capture snapshot at submission time
        let snapshot = QueueItemSnapshot(
            prompt: trimmed,
            providerID: settings.selectedProviderID,
            modelID: settings.selectedModelID,
            parameters: settings.parameters,
            userMessageID: userMessage.id
        )

        if activeRequest == nil {
            startRequest(snapshot)
        } else {
            pendingQueue.append(snapshot)
            statusMessage = "Queued (\(pendingQueue.count)/\(RuntimeConstants.pendingQueueCapacity))"
        }
    }

    func quickBarSubmit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = trimmed
        sendDraft()
    }

    func stopActiveRequest() {
        guard activeRequest != nil else {
            statusMessage = "No active request to stop"
            return
        }

        let hadContent = !(activeRequest?.accumulatedText.isEmpty ?? true)

        activeRequest?.status = .stopped

        // If no content was streamed, add an explicit stopped message
        if !hadContent {
            messages.append(ChatMessage(role: .assistant, content: "[Request stopped]"))
        }

        activeStreamTask?.cancel()
        activeStreamTask = nil
        activeRequest = nil
        statusMessage = "Request stopped"

        advanceQueue()
    }

    func resetConversation() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        activeRequest = nil
        pendingQueue.removeAll()
        messages.removeAll()
        statusMessage = "Conversation cleared"
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .background || phase == .inactive else { return }
        flushSettings()
    }

    // MARK: - Request Execution

    private func startRequest(_ snapshot: QueueItemSnapshot) {
        activeRequest = ActiveRequestState(requestID: snapshot.id)
        statusMessage = "Processing..."

        activeStreamTask = Task {
            await executeRequest(snapshot)
        }
    }

    private func executeRequest(_ snapshot: QueueItemSnapshot) async {
        let requestID = snapshot.id

        // --- 3.1 Strict Provider Resolution ---

        guard let config = settings.providerConfigurations.first(where: { $0.id == snapshot.providerID }) else {
            failActiveRequest(
                requestID: requestID,
                error: .providerMissing(providerID: snapshot.providerID)
            )
            return
        }

        guard config.isEnabled else {
            failActiveRequest(
                requestID: requestID,
                error: .providerDisabled(providerID: snapshot.providerID)
            )
            return
        }

        guard let provider = registry.provider(for: snapshot.providerID) else {
            failActiveRequest(
                requestID: requestID,
                error: .providerNotRegistered(providerID: snapshot.providerID)
            )
            return
        }

        // --- 3.2 / 3.3 / 3.5 Preflight Model Validation with Timeout ---

        let preflightTimeout = preflightTimeoutOverride ?? RuntimeConstants.preflightTimeout
        do {
            try await preflightModelValidation(
                provider: provider,
                modelID: snapshot.modelID,
                providerID: snapshot.providerID,
                timeout: preflightTimeout
            )
        } catch let error as RequestError {
            failActiveRequest(requestID: requestID, error: error)
            return
        } catch is CancellationError {
            return
        } catch {
            failActiveRequest(
                requestID: requestID,
                error: .remoteError(provider: snapshot.providerID, message: error.localizedDescription)
            )
            return
        }

        // Preflight passed — begin streaming
        guard activeRequest?.requestID == requestID else { return }
        activeRequest?.status = .streaming

        let contextMessages = messagesForExecution(userMessageID: snapshot.userMessageID)

        // --- 3.4 Generation with Timeout ---

        let stream = provider.sendStreaming(
            messages: contextMessages,
            modelID: snapshot.modelID,
            parameters: snapshot.parameters,
            requestID: requestID
        )

        await consumeStream(stream, requestID: requestID, providerID: snapshot.providerID)
    }

    private nonisolated func preflightModelValidation(
        provider: any LLMProvider,
        modelID: String,
        providerID: String,
        timeout: Duration
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let models = try await provider.availableModels()
                guard models.contains(where: { $0.id == modelID }) else {
                    throw RequestError.modelInvalid(modelID: modelID, providerID: providerID)
                }
            }
            group.addTask { [timeout] in
                try await Task.sleep(for: timeout)
                let (sec, atto) = timeout.components
                let totalSeconds = Double(sec) + Double(atto) * 1e-18
                throw RequestError.preflightTimeout(seconds: totalSeconds)
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private func consumeStream(
        _ stream: AsyncThrowingStream<StreamEvent, Error>,
        requestID: RequestID,
        providerID: String
    ) async {
        // Start generation timeout watcher
        let genTimeout = generationTimeoutOverride ?? RuntimeConstants.generationTimeout
        let timeoutTask = Task { [genTimeout] in
            do {
                try await Task.sleep(for: genTimeout)
                guard self.activeRequest?.requestID == requestID,
                      !(self.activeRequest?.isTerminal ?? true) else { return }
                let (sec, atto) = genTimeout.components
                let totalSeconds = Double(sec) + Double(atto) * 1e-18
                self.failActiveRequest(
                    requestID: requestID,
                    error: .generationTimeout(seconds: totalSeconds)
                )
            } catch {
                // Cancelled — timeout was not needed
            }
        }
        defer { timeoutTask.cancel() }

        do {
            for try await event in stream {
                guard activeRequest?.requestID == requestID,
                      !(activeRequest?.isTerminal ?? true) else { break }

                switch event {
                case .started(let rid):
                    guard rid == requestID else { continue }
                case .delta(let rid, let text):
                    guard rid == requestID else { continue }
                    handleDelta(requestID: requestID, text: text)
                case .completed(let rid):
                    guard rid == requestID else { continue }
                    completeActiveRequest(requestID: requestID)
                    return
                case .failed(let rid, let error):
                    guard rid == requestID else { continue }
                    failActiveRequest(requestID: requestID, error: error)
                    return
                }
            }
            // Stream ended naturally without explicit terminal event
            if activeRequest?.requestID == requestID,
               !(activeRequest?.isTerminal ?? true) {
                completeActiveRequest(requestID: requestID)
            }
        } catch is CancellationError {
            // Stop or timeout already handled
        } catch {
            if activeRequest?.requestID == requestID,
               !(activeRequest?.isTerminal ?? true) {
                failActiveRequest(
                    requestID: requestID,
                    error: .remoteError(provider: providerID, message: error.localizedDescription)
                )
            }
        }
    }

    // MARK: - State Handlers

    private func handleDelta(requestID: RequestID, text: String) {
        guard activeRequest?.requestID == requestID else { return }

        activeRequest?.accumulatedText += text
        let accumulated = activeRequest?.accumulatedText ?? ""

        if let msgID = activeRequest?.assistantMessageID,
           let index = messages.lastIndex(where: { $0.id == msgID }) {
            let existing = messages[index]
            messages[index] = ChatMessage(
                id: existing.id,
                role: .assistant,
                content: accumulated,
                createdAt: existing.createdAt
            )
        } else {
            let newMessage = ChatMessage(role: .assistant, content: accumulated)
            activeRequest?.assistantMessageID = newMessage.id
            messages.append(newMessage)
        }
    }

    private func completeActiveRequest(requestID: RequestID) {
        guard activeRequest?.requestID == requestID,
              !(activeRequest?.isTerminal ?? true) else { return }

        activeRequest?.status = .completed
        statusMessage = "Response complete"

        activeStreamTask = nil
        activeRequest = nil

        advanceQueue()
    }

    private func failActiveRequest(requestID: RequestID, error: RequestError) {
        guard activeRequest?.requestID == requestID,
              !(activeRequest?.isTerminal ?? true) else { return }

        activeRequest?.status = .failed(error)

        let errorDescription = error.errorDescription ?? "Unknown error"

        // If no content was accumulated, append an explicit failure message
        if activeRequest?.accumulatedText.isEmpty ?? true {
            messages.append(ChatMessage(
                role: .assistant,
                content: "Error: \(errorDescription)"
            ))
        }

        statusMessage = errorDescription

        activeStreamTask?.cancel()
        activeStreamTask = nil
        activeRequest = nil

        advanceQueue()
    }

    // MARK: - Queue Management

    private func advanceQueue() {
        guard !pendingQueue.isEmpty else { return }
        let next = pendingQueue.removeFirst()
        startRequest(next)
    }

    private func messagesForExecution(userMessageID: UUID) -> [ChatMessage] {
        guard let index = messages.firstIndex(where: { $0.id == userMessageID }) else {
            return messages
        }
        return Array(messages[...index])
    }

    // MARK: - Settings Persistence (Debounced)

    private func persistSettingsIfNeeded(previous: AppSettings) {
        guard previous != settings else { return }
        isDirty = true
        scheduleDebouncedSave()
    }

    private func scheduleDebouncedSave() {
        debounceTask?.cancel()
        debounceTask = Task {
            do {
                try await Task.sleep(for: RuntimeConstants.settingsDebounceInterval)
                self.performSave()
            } catch {
                // Cancelled — a newer debounce or flush superseded this one
            }
        }
    }

    private func performSave() {
        guard isDirty else { return }
        do {
            try settingsStore.save(settings)
            isDirty = false
        } catch {
            // Keep dirty for retry on next debounce cycle or flush
            statusMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }

    /// Force-save pending settings immediately. Call at lifecycle boundaries
    /// (app background/inactive scene phase transitions).
    func flushSettings() {
        debounceTask?.cancel()
        debounceTask = nil
        performSave()
    }
}
