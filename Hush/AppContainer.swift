import AppKit
import Combine
import Foundation
import os
import SwiftUI

// swiftlint:disable file_length type_body_length

struct OpenAISettingsSnapshot: Equatable {
    var endpoint: String
    var defaultModelID: String
    var isEnabled: Bool
    var hasCredential: Bool
}

struct OpenAISettingsInput: Equatable {
    static let providerID = "openai"

    var endpoint: String
    var defaultModelID: String
    var isEnabled: Bool
    var apiKey: String
}

struct ProviderCatalogDraftInput: Equatable {
    var providerID: String
    var type: ProviderType
    var endpoint: String
    var apiKey: String
    var credentialRef: String?
}

enum OpenAISettingsSaveError: Error, Equatable {
    case defaultModelRequired
    case credentialRequired
    case keychainWriteFailed
}

extension OpenAISettingsSaveError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .defaultModelRequired:
            return "Default Model is required."
        case .credentialRequired:
            return "OpenAI is enabled but no API key is available. Enter an API key or keep it disabled."
        case .keychainWriteFailed:
            return "Failed to save API key to Keychain."
        }
    }
}

struct DataStats {
    let databaseSizeBytes: UInt64
    let conversationCount: Int
    let messageCount: Int
}

private struct ConversationPageSnapshot {
    let messages: [ChatMessage]
    let hasMoreOlderMessages: Bool
    let oldestLoadedOrderIndex: Int?
}

private struct ConversationMessageStats {
    let messageCount: Int
    let assistantCount: Int
    let longAssistantCount: Int
    let totalChars: Int
}

private struct ConversationSwitchTrace {
    let generation: UInt64
    let conversationId: String
    let startedAt: Date
    var snapshotAppliedAt: Date?
    var layoutReadyAt: Date?
    var didLogRichRenderReady: Bool
    var didLogPresentedRendered: Bool
    var didLogRenderCacheHitRate: Bool
}

private enum ConversationSwitchDebug {
    private static let logger = Logger(subsystem: "com.hush.app", category: "SwitchRender")

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

    static func log(_ message: String) {
        guard isEnabled else { return }
        logger.debug("\(message, privacy: .public)")
        #if DEBUG
            print("[SwitchDebug] \(message)")
        #endif
    }
}

private func makeConversationMessageStats(_ messages: [ChatMessage]) -> ConversationMessageStats {
    var assistantCount = 0
    var longAssistantCount = 0
    var totalChars = 0

    for message in messages {
        totalChars += message.content.count
        guard message.role == .assistant else { continue }
        assistantCount += 1
        if message.content.count > RenderConstants.progressiveRenderThresholdChars {
            longAssistantCount += 1
        }
    }

    return ConversationMessageStats(
        messageCount: messages.count,
        assistantCount: assistantCount,
        longAssistantCount: longAssistantCount,
        totalChars: totalChars
    )
}

@MainActor
final class AppContainer: ObservableObject {
    // MARK: - Published State

    @Published var settings: AppSettings {
        didSet {
            if oldValue.theme != settings.theme {
                HushColors.apply(theme: settings.theme)
            }
            persistSettingsIfNeeded(previous: oldValue)
            if oldValue.maxConcurrentRequests != settings.maxConcurrentRequests {
                requestCoordinator?.updateMaxConcurrent(settings.maxConcurrentRequests)
            }
        }
    }

    @Published var messages: [ChatMessage]
    @Published var sidebarThreads: [ConversationSidebarThread]
    @Published private(set) var isLoadingOlderMessages: Bool
    @Published private(set) var hasMoreOlderMessages: Bool
    @Published private(set) var isLoadingMoreSidebarThreads: Bool
    @Published private(set) var hasMoreSidebarThreads: Bool
    @Published private(set) var isActiveConversationLoading: Bool = false
    @Published private(set) var activeConversationLoadError: String?

    @Published var showQuickBar: Bool = false
    @Published var statusMessage: String = "Ready"

    // MARK: - Request Lifecycle State (managed by RequestCoordinator)

    var requestStates: [RequestID: ActiveRequestState] = [:]
    @Published private(set) var runningConversationIds: Set<String> = []
    @Published private(set) var queuedConversationCounts: [String: Int] = [:]
    @Published private(set) var unreadCompletions: Set<String> = []
    @Published var catalogRefreshingProviderIDs: Set<String> = []
    @Published var catalogRefreshErrors: [String: String] = [:]

    // MARK: - Message Buckets

    private var messagesByConversationId: [String: [ChatMessage]] = [:]
    private weak var hotScenePool: HotScenePool?

    // MARK: - Computed

    var isSending: Bool {
        !runningConversationIds.isEmpty
    }

    var isActiveConversationSending: Bool {
        guard let activeId = activeConversationId else { return false }
        return runningConversationIds.contains(activeId)
    }

    var isQueueFull: Bool {
        requestCoordinator?.isQueueFull ?? false
    }

    var hasConfiguredProvider: Bool {
        settings.providerConfigurations.contains(where: \.isEnabled)
    }

    var activeRequest: ActiveRequestState? {
        guard let activeId = activeConversationId else { return nil }
        return requestCoordinator?.runningRequest(forConversation: activeId)
    }

    var pendingQueue: [QueueItemSnapshot] {
        requestCoordinator?.schedulerState.activeQueue ?? []
    }

    // MARK: - Internal

    private let preferencesRepository: GRDBAppPreferencesRepository?
    private let credentialStore: any KeychainCredentialStore
    private(set) var registry: ProviderRegistry
    private(set) var requestCoordinator: RequestCoordinator!
    let messageRenderRuntime: MessageRenderRuntime

    // MARK: - Catalog

    private(set) var catalogRepository: (any ProviderCatalogRepository)?
    private(set) var catalogRefreshService: CatalogRefreshService?

    // MARK: - Provider Configuration Storage

    private(set) var providerConfigRepository: (any ProviderConfigurationRepository)?

    // MARK: - Agent Preset Storage

    private(set) var agentPresetRepository: (any AgentPresetRepository)?

    // MARK: - Prompt Template Storage

    private(set) var promptTemplateRepository: (any PromptTemplateRepository)?

    // MARK: - Persistence

    private let persistence: ChatPersistenceCoordinator?
    @Published private(set) var activeConversationId: String?
    @Published private(set) var activeConversationRenderGeneration: UInt64 = 0

    // MARK: - Debounce State

    private var debounceTask: Task<Void, Never>?
    private(set) var isDirty: Bool = false
    private var conversationLoadTask: Task<Void, Never>?
    private var conversationLoadGeneration: UInt64 = 0
    private var oldestLoadedOrderIndex: Int?
    private var sidebarThreadsCursor: SidebarThreadsCursor?
    private var sidebarThreadsLoadGeneration: UInt64 = 0
    private var conversationPageCache: [String: ConversationPageSnapshot] = [:]
    private var conversationPageCacheOrder: [String] = []
    private let conversationPageCacheCapacity = 8
    private var startupPrewarmTask: Task<Void, Never>?
    private var switchAwayPrewarmTask: Task<Void, Never>?
    private var idlePrewarmTask: Task<Void, Never>?
    private var activeConversationSwitchTrace: ConversationSwitchTrace?

    // MARK: - Testing Overrides (forwarded to coordinator)

    var preflightTimeoutOverride: Duration? {
        get { requestCoordinator?.preflightTimeoutOverride }
        set { requestCoordinator?.preflightTimeoutOverride = newValue }
    }

    var generationTimeoutOverride: Duration? {
        get { requestCoordinator?.generationTimeoutOverride }
        set { requestCoordinator?.generationTimeoutOverride = newValue }
    }

    var streamingPresentationPolicyOverride: StreamingPresentationPolicy? {
        get { requestCoordinator?.streamingPresentationPolicyOverride }
        set { requestCoordinator?.streamingPresentationPolicyOverride = newValue }
    }

    // MARK: - Message Bucket Interface

    func registerHotScenePool(_ pool: HotScenePool?) {
        hotScenePool = pool
    }

    func messagesForConversation(_ conversationId: String) -> [ChatMessage] {
        if conversationId == activeConversationId {
            return messages
        }
        return messagesByConversationId[conversationId] ?? []
    }

    func appendMessage(_ message: ChatMessage, toConversation conversationId: String) {
        if conversationId == activeConversationId {
            messages.append(message)
        }
        messagesByConversationId[conversationId, default: []].append(message)
        hotScenePool?.markNeedsReload(conversationID: conversationId)
    }

    func updateMessage(at index: Int, inConversation conversationId: String, content: String) {
        if conversationId == activeConversationId, index < messages.count {
            let existing = messages[index]
            messages[index] = ChatMessage(
                id: existing.id,
                role: .assistant,
                content: content,
                createdAt: existing.createdAt
            )
        }
        if var bucket = messagesByConversationId[conversationId], index < bucket.count {
            let existing = bucket[index]
            bucket[index] = ChatMessage(
                id: existing.id,
                role: .assistant,
                content: content,
                createdAt: existing.createdAt
            )
            messagesByConversationId[conversationId] = bucket
        }
        hotScenePool?.markNeedsReload(conversationID: conversationId)
    }

    func pushStreamingContent(conversationId: String, messageID: UUID, content: String) {
        guard conversationId == activeConversationId else { return }
        guard let scene = hotScenePool?.sceneFor(conversationID: conversationId) else { return }
        scene.pushStreamingContent(messageID: messageID, content: content)
    }

    func markUnreadCompletion(forConversation conversationId: String) {
        guard conversationId != activeConversationId else { return }
        unreadCompletions.insert(conversationId)
    }

    func clearUnreadCompletion(forConversation conversationId: String) {
        unreadCompletions.remove(conversationId)
    }

    func clearActiveConversationUnreadIfAtTail() {
        guard let conversationId = activeConversationId else { return }
        clearUnreadCompletion(forConversation: conversationId)
    }

    func syncPublishedSchedulerState() {
        guard let coordinator = requestCoordinator else { return }
        runningConversationIds = coordinator.conversationsWithRunning()
        queuedConversationCounts = coordinator.conversationsWithQueued()
    }

    var sidebarThreadsLoadApplyDelayOverride: Duration?

    // MARK: - Init

    private init(
        settings: AppSettings,
        preferencesRepository: GRDBAppPreferencesRepository?,
        credentialStore: any KeychainCredentialStore,
        registry: ProviderRegistry,
        messageRenderRuntime: MessageRenderRuntime,
        persistence: ChatPersistenceCoordinator?,
        catalogRepository: (any ProviderCatalogRepository)? = nil,
        providerConfigRepository: (any ProviderConfigurationRepository)? = nil,
        agentPresetRepository: (any AgentPresetRepository)? = nil,
        promptTemplateRepository: (any PromptTemplateRepository)? = nil,
        activeConversationId: String? = nil,
        messages: [ChatMessage] = [],
        sidebarThreads: [ConversationSidebarThread] = [],
        hasMoreOlderMessages: Bool = false,
        oldestLoadedOrderIndex: Int? = nil,
        hasMoreSidebarThreads: Bool = false,
        sidebarThreadsCursor: SidebarThreadsCursor? = nil
    ) {
        self.settings = settings
        HushColors.apply(theme: settings.theme)
        self.preferencesRepository = preferencesRepository
        self.credentialStore = credentialStore
        self.registry = registry
        self.messageRenderRuntime = messageRenderRuntime
        self.persistence = persistence
        self.catalogRepository = catalogRepository
        self.providerConfigRepository = providerConfigRepository
        self.agentPresetRepository = agentPresetRepository
        self.promptTemplateRepository = promptTemplateRepository
        self.activeConversationId = activeConversationId
        self.messages = messages
        self.sidebarThreads = sidebarThreads
        isLoadingOlderMessages = false
        self.hasMoreOlderMessages = hasMoreOlderMessages
        isLoadingMoreSidebarThreads = false
        self.hasMoreSidebarThreads = hasMoreSidebarThreads
        self.oldestLoadedOrderIndex = oldestLoadedOrderIndex
        self.sidebarThreadsCursor = sidebarThreadsCursor

        if let activeConversationId {
            let snapshot = ConversationPageSnapshot(
                messages: messages,
                hasMoreOlderMessages: hasMoreOlderMessages,
                oldestLoadedOrderIndex: oldestLoadedOrderIndex
            )
            conversationPageCache[activeConversationId] = snapshot
            conversationPageCacheOrder = [activeConversationId]
        }

        messageRenderRuntime.setActiveConversation(
            conversationID: activeConversationId,
            generation: activeConversationRenderGeneration
        )

        // Set up catalog refresh service if repository is available
        if let repo = catalogRepository {
            catalogRefreshService = CatalogRefreshService(
                catalogRepository: repo,
                registry: registry
            )
        }
    }

    deinit {
        debounceTask?.cancel()
        conversationLoadTask?.cancel()
        startupPrewarmTask?.cancel()
        switchAwayPrewarmTask?.cancel()
        idlePrewarmTask?.cancel()
    }

    /// Second-phase setup: create the coordinator after `self` is fully initialized.
    private func configureCoordinator(
        persistence: ChatPersistenceCoordinator?,
        credentialResolver: CredentialResolver
    ) {
        requestCoordinator = RequestCoordinator(
            container: self,
            persistence: persistence,
            credentialResolver: credentialResolver
        )
        requestCoordinator.updateMaxConcurrent(settings.maxConcurrentRequests)
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    static func bootstrap() -> AppContainer {
        #if DEBUG
            if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
                var registry = ProviderRegistry()
                registry.register(MockProvider(id: "mock"))
                return AppContainer.forTesting(
                    settings: .testDefault,
                    registry: registry,
                    enableStartupPrewarm: false
                )
            }
        #endif

        var loadedSettings = AppSettings.default

        var registry = ProviderRegistry()
        #if DEBUG
            registry.register(MockProvider(id: "mock"))
        #endif
        registry.register(OpenAIProvider(id: "openai"))

        // Initialize database and restore persisted state
        var persistence: ChatPersistenceCoordinator?
        var catalogRepository: GRDBProviderCatalogRepository?
        var providerConfigRepository: GRDBProviderConfigurationRepository?
        var preferencesRepository: GRDBAppPreferencesRepository?
        var agentPresetRepository: GRDBAgentPresetRepository?
        var promptTemplateRepository: GRDBPromptTemplateRepository?
        var conversationId: String?
        var restoredMessages: [ChatMessage] = []
        var restoredHasMoreOlderMessages = false
        var restoredOldestOrderIndex: Int?
        var restoredSidebarThreads: [ConversationSidebarThread] = []
        var restoredHasMoreSidebarThreads = false
        var restoredSidebarCursor: SidebarThreadsCursor?

        do {
            let dbManager: DatabaseManager
            #if DEBUG
                if let raw = ProcessInfo.processInfo.environment["HUSH_DB_PATH"]?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !raw.isEmpty
                {
                    let url = URL(fileURLWithPath: raw)
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    dbManager = try DatabaseManager(path: raw)
                } else {
                    dbManager = try DatabaseManager.appDefault()
                }
            #else
                dbManager = try DatabaseManager.appDefault()
            #endif
            let coordinator = ChatPersistenceCoordinator(dbManager: dbManager)
            persistence = coordinator
            catalogRepository = GRDBProviderCatalogRepository(dbManager: dbManager)
            providerConfigRepository = GRDBProviderConfigurationRepository(dbManager: dbManager)
            preferencesRepository = GRDBAppPreferencesRepository(dbManager: dbManager)
            agentPresetRepository = GRDBAgentPresetRepository(dbManager: dbManager)
            promptTemplateRepository = GRDBPromptTemplateRepository(dbManager: dbManager)

            // Migrate preferences from JSON → SQLite on first run
            let prefsRepo = preferencesRepository!
            let existingPrefs = try prefsRepo.fetch()
            if existingPrefs == nil {
                let jsonStore = JSONSettingsStore.defaultStore()
                let jsonSettings = (try? jsonStore.load()) ?? .default
                try prefsRepo.save(jsonSettings)

                // Migrate provider configs from JSON → SQLite
                let configRepo = providerConfigRepository!
                let existingDBConfigs = try configRepo.fetchAll()
                if existingDBConfigs.isEmpty {
                    for config in jsonSettings.providerConfigurations {
                        try configRepo.upsert(config)
                    }
                }
            }

            // Load app preferences from SQLite (source of truth)
            if let prefsRecord = try prefsRepo.fetch() {
                let prefs = prefsRecord.toAppPreferences()
                loadedSettings.selectedProviderID = prefs.selectedProviderID
                loadedSettings.selectedModelID = prefs.selectedModelID
                loadedSettings.parameters = prefs.parameters
                loadedSettings.quickBar = prefs.quickBar
                loadedSettings.theme = prefs.theme
                loadedSettings.maxConcurrentRequests = prefs.maxConcurrentRequests
            }

            // Load provider configs from SQLite (source of truth)
            let dbConfigs = try providerConfigRepository!.fetchAll()
            loadedSettings.providerConfigurations = dbConfigs

            let bootstrapResult = try coordinator.bootstrapState(
                messageLimit: RuntimeConstants.conversationMessagePageSize
            )
            conversationId = bootstrapResult.conversationID
            restoredMessages = bootstrapResult.messagePage.messages
            restoredHasMoreOlderMessages = bootstrapResult.messagePage.hasMoreOlderMessages
            restoredOldestOrderIndex = bootstrapResult.messagePage.oldestOrderIndex

            if let sidebarPage = try? coordinator.fetchSidebarThreadsPage(cursor: nil, limit: 10) {
                restoredSidebarThreads = sidebarPage.threads
                restoredHasMoreSidebarThreads = sidebarPage.hasMore
                restoredSidebarCursor = sidebarPage.nextCursor
            }
        } catch {
            // Fall back to in-memory mode if database fails
            print("[Hush] Database bootstrap failed, running in memory-only mode: \(error)")
        }

        let container = AppContainer(
            settings: loadedSettings,
            preferencesRepository: preferencesRepository,
            credentialStore: KeychainAdapter(),
            registry: registry,
            messageRenderRuntime: .shared,
            persistence: persistence,
            catalogRepository: catalogRepository,
            providerConfigRepository: providerConfigRepository,
            agentPresetRepository: agentPresetRepository,
            promptTemplateRepository: promptTemplateRepository,
            activeConversationId: conversationId,
            messages: restoredMessages,
            sidebarThreads: restoredSidebarThreads,
            hasMoreOlderMessages: restoredHasMoreOlderMessages,
            oldestLoadedOrderIndex: restoredOldestOrderIndex,
            hasMoreSidebarThreads: restoredHasMoreSidebarThreads,
            sidebarThreadsCursor: restoredSidebarCursor
        )
        container.configureCoordinator(
            persistence: persistence,
            credentialResolver: CredentialResolver()
        )
        container.scheduleStartupPrewarmIfNeeded()
        return container
    }

    @MainActor
    static func forTesting(
        settings: AppSettings? = nil,
        preferencesRepository: GRDBAppPreferencesRepository? = nil,
        credentialStore: (any KeychainCredentialStore)? = nil,
        registry: ProviderRegistry? = nil,
        persistence: ChatPersistenceCoordinator? = nil,
        catalogRepository: (any ProviderCatalogRepository)? = nil,
        providerConfigRepository: (any ProviderConfigurationRepository)? = nil,
        activeConversationId: String? = nil,
        messages: [ChatMessage] = [],
        sidebarThreads: [ConversationSidebarThread] = [],
        hasMoreOlderMessages: Bool = false,
        oldestLoadedOrderIndex: Int? = nil,
        hasMoreSidebarThreads: Bool = false,
        sidebarThreadsCursor: SidebarThreadsCursor? = nil,
        messageRenderRuntime: MessageRenderRuntime? = nil,
        credentialResolver: CredentialResolver = CredentialResolver(),
        agentPresetRepository: (any AgentPresetRepository)? = nil,
        promptTemplateRepository: (any PromptTemplateRepository)? = nil,
        streamingPresentationPolicyOverride: StreamingPresentationPolicy? = .testingFast,
        enableStartupPrewarm: Bool = false
    ) -> AppContainer {
        let resolvedSettings = settings ?? .default
        let resolvedRegistry = registry ?? ProviderRegistry()
        let resolvedRenderRuntime = messageRenderRuntime ?? MessageRenderRuntime()
        let container = AppContainer(
            settings: resolvedSettings,
            preferencesRepository: preferencesRepository,
            credentialStore: credentialStore ?? KeychainAdapter(),
            registry: resolvedRegistry,
            messageRenderRuntime: resolvedRenderRuntime,
            persistence: persistence,
            catalogRepository: catalogRepository,
            providerConfigRepository: providerConfigRepository,
            agentPresetRepository: agentPresetRepository,
            promptTemplateRepository: promptTemplateRepository,
            activeConversationId: activeConversationId,
            messages: messages,
            sidebarThreads: sidebarThreads,
            hasMoreOlderMessages: hasMoreOlderMessages,
            oldestLoadedOrderIndex: oldestLoadedOrderIndex,
            hasMoreSidebarThreads: hasMoreSidebarThreads,
            sidebarThreadsCursor: sidebarThreadsCursor
        )
        container.configureCoordinator(
            persistence: persistence,
            credentialResolver: credentialResolver
        )
        container.streamingPresentationPolicyOverride = streamingPresentationPolicyOverride
        if enableStartupPrewarm {
            container.scheduleStartupPrewarmIfNeeded()
        }
        return container
    }

    // MARK: - UI Actions

    func toggleQuickBar() {
        showQuickBar.toggle()
    }

    func addPlaceholderProvider() {
        let id = "provider-\(UUID().uuidString.prefix(8))"
        let configuration = ProviderConfiguration(
            id: String(id),
            name: "OpenAI Compatible",
            type: .openAI,
            endpoint: "https://api.example.com/v1",
            apiKeyEnvironmentVariable: "HUSH_API_KEY",
            defaultModelID: "model-id",
            isEnabled: true
        )
        settings.providerConfigurations.append(configuration)

        // Persist to SQLite
        try? providerConfigRepository?.upsert(configuration)
    }

    func removeProvider(id: String) {
        settings.providerConfigurations.removeAll { $0.id == id }

        // Persist deletion to SQLite
        try? providerConfigRepository?.delete(id: id)

        if !settings.providerConfigurations.contains(where: { $0.id == settings.selectedProviderID }) {
            settings.selectedProviderID = settings.providerConfigurations.first?.id ?? ""
        }
    }

    // MARK: - Settings Workspace

    func openAISettingsSnapshot() -> OpenAISettingsSnapshot {
        let providerConfiguration = settings.providerConfigurations.first(where: { $0.id == OpenAISettingsInput.providerID })
        let credentialRef = normalizedCredentialRef(from: providerConfiguration)

        return OpenAISettingsSnapshot(
            endpoint: normalizeEndpoint(providerConfiguration?.endpoint ?? OpenAIProvider.defaultEndpoint),
            defaultModelID: providerConfiguration?.defaultModelID ?? "",
            isEnabled: providerConfiguration?.isEnabled ?? false,
            hasCredential: credentialStore.hasSecret(forCredentialRef: credentialRef)
        )
    }

    func saveOpenAISettings(_ input: OpenAISettingsInput) throws -> OpenAISettingsSnapshot {
        let normalizedModelID = input.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEnabled || !normalizedModelID.isEmpty else {
            throw OpenAISettingsSaveError.defaultModelRequired
        }

        let existingIndex = settings.providerConfigurations.firstIndex(where: { $0.id == OpenAISettingsInput.providerID })
        let existingConfiguration = existingIndex.map { settings.providerConfigurations[$0] }
        let credentialRef = normalizedCredentialRef(from: existingConfiguration)
        let trimmedAPIKey = input.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmedAPIKey.isEmpty {
            do {
                try credentialStore.setSecret(trimmedAPIKey, forCredentialRef: credentialRef)
            } catch {
                throw OpenAISettingsSaveError.keychainWriteFailed
            }
        }

        let hasCredential = !trimmedAPIKey.isEmpty || credentialStore.hasSecret(forCredentialRef: credentialRef)
        if input.isEnabled, !hasCredential {
            throw OpenAISettingsSaveError.credentialRequired
        }

        let nextConfiguration = ProviderConfiguration(
            id: OpenAISettingsInput.providerID,
            name: existingConfiguration?.name ?? "OpenAI",
            type: .openAI,
            endpoint: normalizeEndpoint(input.endpoint),
            apiKeyEnvironmentVariable: existingConfiguration?.apiKeyEnvironmentVariable ?? "",
            defaultModelID: normalizedModelID,
            isEnabled: input.isEnabled,
            credentialRef: credentialRef,
            pinnedModelIDs: existingConfiguration?.pinnedModelIDs ?? []
        )

        if let index = existingIndex {
            settings.providerConfigurations[index] = nextConfiguration
        } else {
            settings.providerConfigurations.append(nextConfiguration)
        }

        // Persist to SQLite
        try? providerConfigRepository?.upsert(nextConfiguration)

        if settings.selectedProviderID == OpenAISettingsInput.providerID, input.isEnabled {
            settings.selectedModelID = normalizedModelID
        } else if !input.isEnabled, settings.selectedProviderID == OpenAISettingsInput.providerID {
            if let fallbackProvider = fallbackProviderConfiguration() {
                settings.selectedProviderID = fallbackProvider.id
                let fallbackModel = fallbackProvider.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallbackModel.isEmpty {
                    settings.selectedModelID = fallbackModel
                }
            } else {
                settings.selectedProviderID = ""
                settings.selectedModelID = ""
            }
        }

        // Trigger catalog refresh when provider is enabled with credentials
        if input.isEnabled, hasCredential {
            refreshCatalog(forProviderID: OpenAISettingsInput.providerID)
        }

        return OpenAISettingsSnapshot(
            endpoint: nextConfiguration.endpoint,
            defaultModelID: nextConfiguration.defaultModelID,
            isEnabled: nextConfiguration.isEnabled,
            hasCredential: hasCredential
        )
    }

    // MARK: - Multi-Provider Profile Management

    /// Saves or updates a provider profile by its stable ID.
    /// Does NOT persist secrets - only non-secret fields and credentialRef.
    func saveProviderProfile(_ profile: ProviderConfiguration) {
        let wasSelectedProvider = settings.selectedProviderID == profile.id

        if let index = settings.providerConfigurations.firstIndex(where: { $0.id == profile.id }) {
            settings.providerConfigurations[index] = profile
        } else {
            settings.providerConfigurations.append(profile)
        }

        // Persist to SQLite
        try? providerConfigRepository?.upsert(profile)

        if wasSelectedProvider {
            if !profile.isEnabled {
                selectDeterministicFallbackProvider()
            } else {
                let normalizedModel = profile.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalizedModel.isEmpty {
                    settings.selectedModelID = normalizedModel
                }
            }
        }
    }

    /// Sets a provider as the default (selected) provider.
    /// Automatically selects its default model.
    func setDefaultProvider(id: String) {
        guard let config = settings.providerConfigurations.first(where: { $0.id == id }) else { return }
        settings.selectedProviderID = id
        let model = config.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            settings.selectedModelID = model
        }
        triggerCatalogRefreshIfNeeded(providerID: id)
    }

    /// Removes a provider profile and cleans up its catalog cache.
    func removeProviderProfile(id: String) {
        settings.providerConfigurations.removeAll { $0.id == id }

        // Persist deletion to SQLite
        try? providerConfigRepository?.delete(id: id)

        // Clean up catalog cache (best-effort, no secrets involved)
        try? catalogRepository?.removeCatalog(forProviderID: id)

        // Deterministic fallback if removed provider was selected
        if settings.selectedProviderID == id {
            selectDeterministicFallbackProvider()
        }
    }

    /// Selects a provider and its default model, triggering catalog refresh if needed.
    func selectProvider(id: String) {
        guard let config = settings.providerConfigurations.first(where: { $0.id == id }) else { return }
        guard config.isEnabled else { return }

        settings.selectedProviderID = id

        // Try to use defaultModelID as initial selection
        let defaultModel = config.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !defaultModel.isEmpty {
            settings.selectedModelID = defaultModel
        }

        // Trigger catalog refresh if no usable cache exists
        triggerCatalogRefreshIfNeeded(providerID: id)
    }

    /// Returns cached catalog models for a provider, or empty array if unavailable.
    func cachedModels(forProviderID providerID: String) -> [ModelDescriptor] {
        (try? catalogRepository?.models(forProviderID: providerID)) ?? []
    }

    /// Returns the catalog refresh status for a provider.
    func catalogRefreshStatus(forProviderID providerID: String) -> ProviderCatalogRefreshStatus? {
        try? catalogRepository?.refreshStatus(forProviderID: providerID)
    }

    /// Resolves available models for a provider asynchronously.
    /// Uses cache if available; otherwise fetches from provider API and caches the result.
    /// Returns sorted models and whether they came from cache.
    func availableModels(forProviderID providerID: String) async -> (models: [ModelDescriptor], fromCache: Bool, error: String?) {
        guard let service = catalogRefreshService else {
            return ([], false, "Catalog service unavailable")
        }

        guard let config = settings.providerConfigurations.first(where: { $0.id == providerID }) else {
            return ([], false, "Provider not configured")
        }

        let provider = resolveProvider(for: config)
        let credentialRef = normalizedCredentialRef(from: config)
        let bearerToken = try? CredentialResolver(
            secretStore: credentialStore
        ).resolve(providerID: providerID, credentialRef: credentialRef)

        let context = ProviderInvocationContext(
            endpoint: config.endpoint,
            bearerToken: bearerToken
        )

        let (models, fromCache) = await service.resolveModels(
            providerID: providerID,
            context: context,
            providerOverride: provider
        )

        let sortedModels = models.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        if sortedModels.isEmpty {
            return ([], fromCache, "Model catalog unavailable")
        }

        return (sortedModels, fromCache, nil)
    }

    /// Resolves model catalog data from the current draft provider settings without persisting it.
    func previewModels(for draft: ProviderCatalogDraftInput) async -> (models: [ModelDescriptor], error: String?) {
        let provider = previewProvider(for: draft)
        let trimmedAPIKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let bearerToken: String?
        if !trimmedAPIKey.isEmpty {
            bearerToken = trimmedAPIKey
        } else if let credentialRef = draft.credentialRef?.trimmingCharacters(in: .whitespacesAndNewlines), !credentialRef.isEmpty {
            bearerToken = try? CredentialResolver(secretStore: credentialStore)
                .resolve(providerID: draft.providerID, credentialRef: credentialRef)
        } else {
            switch draft.type {
            case .openAI:
                return ([], "Enter an API key to fetch models.")
            #if DEBUG
                case .mock:
                    bearerToken = nil
            #endif
            }
        }

        let context = ProviderInvocationContext(
            endpoint: normalizedEndpoint(draft.endpoint, for: draft.type),
            bearerToken: bearerToken
        )

        do {
            let models = try await provider.availableModels(context: context)
            let sortedModels = models.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            if sortedModels.isEmpty {
                return ([], "Model catalog unavailable")
            }
            return (sortedModels, nil)
        } catch {
            return ([], error.localizedDescription)
        }
    }

    // MARK: - Catalog Refresh Triggers

    /// Triggers a catalog refresh for a provider. Non-blocking; runs asynchronously.
    func refreshCatalog(forProviderID providerID: String) {
        guard let service = catalogRefreshService else { return }
        guard let config = settings.providerConfigurations.first(where: { $0.id == providerID }) else { return }

        let provider = resolveProvider(for: config)

        let credentialRef = normalizedCredentialRef(from: config)
        let bearerToken = try? CredentialResolver(
            secretStore: credentialStore
        ).resolve(providerID: providerID, credentialRef: credentialRef)

        let context = ProviderInvocationContext(
            endpoint: config.endpoint,
            bearerToken: bearerToken
        )

        catalogRefreshingProviderIDs.insert(providerID)
        catalogRefreshErrors.removeValue(forKey: providerID)

        Task {
            let result = await service.refresh(
                providerID: providerID,
                context: context,
                providerOverride: provider
            )
            self.catalogRefreshingProviderIDs.remove(providerID)
            switch result {
            case let .success(modelCount):
                self.statusMessage = "Refreshed \(modelCount) models for \(config.name)"
            case let .failure(error):
                self.statusMessage = "Catalog refresh failed: \(error)"
                self.catalogRefreshErrors[providerID] = error
            }
        }
    }

    private func resolveProvider(for config: ProviderConfiguration) -> any LLMProvider {
        ensureProviderRegistered(for: config)
    }

    private func previewProvider(for draft: ProviderCatalogDraftInput) -> any LLMProvider {
        if let provider = registry.provider(for: draft.providerID) {
            return provider
        }
        return makeProviderRuntime(id: draft.providerID, type: draft.type)
    }

    /// Ensures a provider runtime is registered for the given configuration.
    /// Returns the registered provider instance.
    @discardableResult
    func ensureProviderRegistered(for config: ProviderConfiguration) -> any LLMProvider {
        if let existing = registry.provider(for: config.id) {
            return existing
        }
        let provider = makeProviderRuntime(id: config.id, type: config.type)
        registry.register(provider)
        return provider
    }

    private func makeProviderRuntime(id: String, type: ProviderType) -> any LLMProvider {
        switch type {
        case .openAI:
            OpenAIProvider(id: id)
        #if DEBUG
            case .mock:
                MockProvider(id: id)
        #endif
        }
    }

    /// Triggers catalog refresh if provider has no usable cache.
    private func triggerCatalogRefreshIfNeeded(providerID: String) {
        guard let status = try? catalogRepository?.refreshStatus(forProviderID: providerID) else { return }
        if !status.hasUsableCache {
            refreshCatalog(forProviderID: providerID)
        }
    }

    /// Selects a deterministic fallback when the current default provider is unset.
    func selectDeterministicFallback() {
        selectDeterministicFallbackProvider()
    }

    /// Deterministic fallback: select first enabled provider, or clear selection.
    private func selectDeterministicFallbackProvider() {
        if let fallback = fallbackProviderConfiguration() {
            settings.selectedProviderID = fallback.id
            let fallbackModel = fallback.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackModel.isEmpty {
                settings.selectedModelID = fallbackModel
            }
        } else {
            settings.selectedProviderID = ""
            settings.selectedModelID = ""
        }
    }

    // MARK: - Send Pipeline

    func sendDraft(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Queue-full atomic rejection: no user message, no queue append, no persistence
        if requestCoordinator.isQueueFull {
            statusMessage = "Queue full – request rejected (max \(RuntimeConstants.pendingQueueCapacity))"
            return
        }

        let conversationId = activeConversationId ?? ""

        let userMessage = ChatMessage(role: .user, content: trimmed)
        appendMessage(userMessage, toConversation: conversationId)
        updateSidebarThreadsAfterUserMessage(userMessage)
        cacheCurrentConversationSnapshotIfNeeded()

        if !conversationId.isEmpty {
            try? persistence?.persistUserMessage(userMessage, conversationId: conversationId)
        }

        let snapshot = QueueItemSnapshot(
            prompt: trimmed,
            providerID: settings.selectedProviderID,
            modelID: settings.selectedModelID,
            parameters: settings.parameters,
            userMessageID: userMessage.id,
            conversationId: conversationId
        )

        requestCoordinator.submitRequest(snapshot)
    }

    private func updateSidebarThreadsAfterUserMessage(_ message: ChatMessage) {
        guard let conversationId = activeConversationId else { return }

        let derivedTitle = ConversationSidebarTitleFormatter.topicTitle(from: message.content)

        if let existingIndex = sidebarThreads.firstIndex(where: { $0.id == conversationId }) {
            let existing = sidebarThreads[existingIndex]
            let resolvedTitle =
                existing.title == ConversationSidebarTitleFormatter.placeholderTitle
                    ? derivedTitle
                    : existing.title

            sidebarThreads.remove(at: existingIndex)
            sidebarThreads.insert(
                ConversationSidebarThread(
                    id: conversationId,
                    title: resolvedTitle,
                    lastActivityAt: message.createdAt
                ),
                at: 0
            )
        } else {
            sidebarThreads.insert(
                ConversationSidebarThread(
                    id: conversationId,
                    title: derivedTitle,
                    lastActivityAt: message.createdAt
                ),
                at: 0
            )
        }
    }

    func quickBarSubmit(_ text: String) {
        sendDraft(text)
    }

    func stopActiveRequest() {
        guard let conversationId = activeConversationId else { return }
        requestCoordinator.stopConversation(conversationId)
    }

    func activateConversation(conversationId: String) {
        beginConversationActivation(conversationId: conversationId, allowSameConversation: false)
    }

    func retryActiveConversationLoad() {
        guard let conversationId = activeConversationId else { return }
        beginConversationActivation(conversationId: conversationId, allowSameConversation: true)
    }

    private func beginConversationActivation(
        conversationId: String,
        allowSameConversation: Bool
    ) {
        if !allowSameConversation {
            guard conversationId != activeConversationId else { return }
        }

        // User activity: cancel any pending idle prewarm work immediately.
        idlePrewarmTask?.cancel()

        guard let persistence else {
            activeConversationLoadError = "Persistence unavailable"
            isActiveConversationLoading = false
            return
        }

        activeConversationLoadError = nil
        isActiveConversationLoading = true

        cacheCurrentConversationSnapshotIfNeeded()

        conversationLoadTask?.cancel()
        conversationLoadGeneration &+= 1
        let generation = conversationLoadGeneration
        activeConversationRenderGeneration = generation
        messageRenderRuntime.setActiveConversation(
            conversationID: conversationId,
            generation: generation
        )
        let previousConversationId = activeConversationId

        // Sync current active messages into bucket before switching away
        if let prevId = activeConversationId, !messages.isEmpty {
            messagesByConversationId[prevId] = messages
        }

        requestCoordinator.rebalanceForActiveSwitch(newActiveConversationId: conversationId)

        activeConversationSwitchTrace = ConversationSwitchTrace(
            generation: generation,
            conversationId: conversationId,
            startedAt: .now,
            snapshotAppliedAt: nil,
            layoutReadyAt: nil,
            didLogRichRenderReady: false,
            didLogPresentedRendered: false,
            didLogRenderCacheHitRate: false
        )
        ConversationSwitchDebug.log(
            "start generation=\(generation) from=\(previousConversationId ?? "nil") to=\(conversationId)"
        )

        isLoadingOlderMessages = false
        if !applyCachedConversationSnapshotIfAvailable(conversationId: conversationId, generation: generation) {
            ConversationSwitchDebug.log(
                "cache-miss generation=\(generation) conversation=\(conversationId)"
            )
            messages = []
            hasMoreOlderMessages = false
            oldestLoadedOrderIndex = nil
            activeConversationId = conversationId
            statusMessage = "Loading thread..."
        }

        syncStreamingContentForActiveConversationIfNeeded(conversationId: conversationId)

        conversationLoadTask = makeConversationLoadTask(
            persistence: persistence,
            conversationId: conversationId,
            generation: generation
        )

        scheduleSwitchAwayPrewarmIfNeeded(from: previousConversationId, persistence: persistence)
        scheduleIdlePrewarmIfNeeded()
    }

    private func applyCachedConversationSnapshotIfAvailable(
        conversationId: String,
        generation: UInt64
    ) -> Bool {
        guard let cached = conversationPageCache[conversationId] else { return false }

        let snapshotToApply = resolvedCachedConversationSnapshot(
            cached,
            conversationId: conversationId
        )
        let stats = makeConversationMessageStats(snapshotToApply.messages)
        ConversationSwitchDebug.log(
            "cache-hit generation=\(generation) conversation=\(conversationId) " +
                "messages=\(stats.messageCount) assistants=\(stats.assistantCount) " +
                "longAssistants=\(stats.longAssistantCount) chars=\(stats.totalChars)"
        )
        applyConversationSnapshot(snapshotToApply, conversationId: conversationId)
        markConversationSwitchSnapshotAppliedIfNeeded(
            conversationId: conversationId,
            generation: generation,
            source: "cache",
            stats: stats
        )
        statusMessage = "Ready"
        return true
    }

    private func resolvedCachedConversationSnapshot(
        _ cached: ConversationPageSnapshot,
        conversationId: String
    ) -> ConversationPageSnapshot {
        guard let bucket = messagesByConversationId[conversationId],
              bucket != cached.messages
        else {
            return cached
        }

        let pageSize = RuntimeConstants.conversationMessagePageSize
        let bounded = Array(bucket.suffix(pageSize))
        return ConversationPageSnapshot(
            messages: bounded,
            hasMoreOlderMessages: cached.hasMoreOlderMessages,
            oldestLoadedOrderIndex: cached.oldestLoadedOrderIndex
        )
    }

    private func makeConversationLoadTask(
        persistence: ChatPersistenceCoordinator,
        conversationId: String,
        generation: UInt64
    ) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                let fetchStartedAt = Date.now
                let pageSize = RuntimeConstants.conversationMessagePageSize
                ConversationSwitchDebug.log(
                    "db-fetch-start generation=\(generation) conversation=\(conversationId) " +
                        "limit=\(pageSize)"
                )
                let page = try await Task.detached(priority: .userInitiated) {
                    try persistence.fetchMessagePage(
                        conversationId: conversationId,
                        beforeOrderIndex: nil,
                        limit: pageSize
                    )
                }.value
                try Task.checkCancellation()

                guard let self, generation == self.conversationLoadGeneration else { return }
                let fetchMs = Int(Date.now.timeIntervalSince(fetchStartedAt) * 1000)
                let stats = makeConversationMessageStats(page.messages)
                ConversationSwitchDebug.log(
                    "db-fetch-done generation=\(generation) conversation=\(conversationId) fetchMs=\(fetchMs) " +
                        "messages=\(stats.messageCount) assistants=\(stats.assistantCount) " +
                        "longAssistants=\(stats.longAssistantCount) chars=\(stats.totalChars)"
                )
                let snapshot = ConversationPageSnapshot(
                    messages: page.messages,
                    hasMoreOlderMessages: page.hasMoreOlderMessages,
                    oldestLoadedOrderIndex: page.oldestOrderIndex
                )
                _ = self.applyConversationSnapshot(snapshot, conversationId: conversationId)
                self.markConversationSwitchSnapshotAppliedIfNeeded(
                    conversationId: conversationId,
                    generation: generation,
                    source: "db",
                    stats: stats
                )
                self.cacheConversationSnapshot(conversationId: conversationId, snapshot: snapshot)
                self.isActiveConversationLoading = false
                self.activeConversationLoadError = nil
                self.statusMessage = "Ready"
            } catch is CancellationError {
                ConversationSwitchDebug.log(
                    "db-fetch-cancelled generation=\(generation) conversation=\(conversationId)"
                )
                guard let self else { return }
                guard generation == self.conversationLoadGeneration else { return }
                guard self.activeConversationId == conversationId else { return }
                guard self.messages.isEmpty else { return }

                if self.activeConversationSwitchTrace?.generation == generation {
                    self.activeConversationSwitchTrace = nil
                }
                self.isActiveConversationLoading = false
                self.activeConversationLoadError = "Loading cancelled"
                self.statusMessage = "Loading cancelled"
            } catch {
                guard let self, generation == self.conversationLoadGeneration else { return }
                if self.activeConversationSwitchTrace?.generation == generation {
                    self.activeConversationSwitchTrace = nil
                }
                ConversationSwitchDebug.log(
                    "db-fetch-failed generation=\(generation) conversation=\(conversationId) " +
                        "error=\(error.localizedDescription)"
                )
                self.isActiveConversationLoading = false
                self.activeConversationLoadError = error.localizedDescription
                self.statusMessage = "Failed to load thread: \(error.localizedDescription)"
            }
        }
    }

    @discardableResult
    func loadOlderMessagesIfNeeded() async -> Bool {
        guard !isLoadingOlderMessages else { return false }
        guard hasMoreOlderMessages else { return false }
        guard let persistence, let conversationId = activeConversationId else { return false }
        guard let beforeOrderIndex = oldestLoadedOrderIndex else {
            hasMoreOlderMessages = false
            return false
        }

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        let pageSize = RuntimeConstants.conversationMessagePageSize

        do {
            let page = try await Task.detached(priority: .userInitiated) {
                try persistence.fetchMessagePage(
                    conversationId: conversationId,
                    beforeOrderIndex: beforeOrderIndex,
                    limit: pageSize
                )
            }.value

            guard conversationId == activeConversationId else { return false }

            hasMoreOlderMessages = page.hasMoreOlderMessages
            if let oldestOrderIndex = page.oldestOrderIndex {
                oldestLoadedOrderIndex = oldestOrderIndex
            }

            let existingIDs = Set(messages.map(\.id))
            let incoming = page.messages.filter { !existingIDs.contains($0.id) }
            guard !incoming.isEmpty else { return false }

            messages = incoming + messages
            cacheCurrentConversationSnapshotIfNeeded()
            return true
        } catch {
            statusMessage = "Failed to load earlier messages: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func loadMoreSidebarThreadsIfNeeded() async -> Bool {
        guard !isLoadingMoreSidebarThreads else { return false }
        guard hasMoreSidebarThreads else { return false }
        guard let persistence else { return false }

        let loadGeneration = sidebarThreadsLoadGeneration
        let cursor = sidebarThreadsCursor
        isLoadingMoreSidebarThreads = true
        defer { isLoadingMoreSidebarThreads = false }

        do {
            let page = try await Task.detached(priority: .userInitiated) {
                try persistence.fetchSidebarThreadsPage(
                    cursor: cursor,
                    limit: 10
                )
            }.value

            if let delay = sidebarThreadsLoadApplyDelayOverride {
                try? await Task.sleep(for: delay)
            }

            guard loadGeneration == sidebarThreadsLoadGeneration else {
                return false
            }

            hasMoreSidebarThreads = page.hasMore
            sidebarThreadsCursor = page.nextCursor

            let existingIDs = Set(sidebarThreads.map(\.id))
            let incoming = page.threads.filter { !existingIDs.contains($0.id) }
            guard !incoming.isEmpty else { return false }

            sidebarThreads.append(contentsOf: incoming)
            return true
        } catch {
            guard loadGeneration == sidebarThreadsLoadGeneration else {
                return false
            }
            statusMessage = "Failed to load more threads: \(error.localizedDescription)"
            return false
        }
    }

    func resetConversation() {
        cacheCurrentConversationSnapshotIfNeeded()
        activeConversationSwitchTrace = nil

        conversationLoadTask?.cancel()
        conversationLoadTask = nil

        if let prevId = activeConversationId, !messages.isEmpty {
            messagesByConversationId[prevId] = messages
        }

        messages.removeAll()
        isLoadingOlderMessages = false
        hasMoreOlderMessages = false
        oldestLoadedOrderIndex = nil
        isActiveConversationLoading = false
        activeConversationLoadError = nil
        statusMessage = "Conversation cleared"

        if let persistence {
            activeConversationId = try? persistence.createNewConversation()
            conversationLoadGeneration &+= 1
            activeConversationRenderGeneration = conversationLoadGeneration
            messageRenderRuntime.setActiveConversation(
                conversationID: activeConversationId,
                generation: activeConversationRenderGeneration
            )
        } else {
            conversationLoadGeneration &+= 1
            activeConversationRenderGeneration = conversationLoadGeneration
            messageRenderRuntime.setActiveConversation(
                conversationID: activeConversationId,
                generation: activeConversationRenderGeneration
            )
        }

        requestCoordinator.rebalanceForActiveSwitch(newActiveConversationId: activeConversationId)
    }

    func deleteConversation(conversationId: String) {
        if requestCoordinator.isConversationRunning(conversationId) {
            requestCoordinator.stopConversation(conversationId)
        }
        guard let persistence else { return }

        messageRenderRuntime.clearProtection(conversationID: conversationId)

        do {
            try persistence.deleteConversation(id: conversationId)
        } catch {
            statusMessage = "Failed to delete: \(error.localizedDescription)"
            return
        }

        sidebarThreads.removeAll { $0.id == conversationId }
        conversationPageCache.removeValue(forKey: conversationId)
        conversationPageCacheOrder.removeAll { $0 == conversationId }
        messagesByConversationId.removeValue(forKey: conversationId)

        if activeConversationId == conversationId {
            resetConversation()
        }
    }

    private func syncStreamingContentForActiveConversationIfNeeded(conversationId: String) {
        guard conversationId == activeConversationId else { return }
        guard let running = requestCoordinator.runningRequest(forConversation: conversationId) else { return }
        guard let messageID = running.assistantMessageID else { return }
        syncPresentedStreamingMessageIntoBucketsIfNeeded(
            conversationId: conversationId,
            messageID: messageID,
            content: running.presentedText
        )
        pushStreamingContent(
            conversationId: conversationId,
            messageID: messageID,
            content: running.presentedText
        )
    }

    private func syncPresentedStreamingMessageIntoBucketsIfNeeded(
        conversationId: String,
        messageID: UUID,
        content: String
    ) {
        var didUpdateActiveMessages = false

        if conversationId == activeConversationId,
           let activeIndex = messages.lastIndex(where: { $0.id == messageID }),
           messages[activeIndex].content != content
        {
            let existing = messages[activeIndex]
            messages[activeIndex] = ChatMessage(
                id: existing.id,
                role: existing.role,
                content: content,
                createdAt: existing.createdAt
            )
            didUpdateActiveMessages = true
        }

        if var bucket = messagesByConversationId[conversationId] {
            if let bucketIndex = bucket.lastIndex(where: { $0.id == messageID }),
               bucket[bucketIndex].content != content
            {
                let existing = bucket[bucketIndex]
                bucket[bucketIndex] = ChatMessage(
                    id: existing.id,
                    role: existing.role,
                    content: content,
                    createdAt: existing.createdAt
                )
                messagesByConversationId[conversationId] = bucket
            } else if didUpdateActiveMessages {
                messagesByConversationId[conversationId] = messages
            }
        } else if didUpdateActiveMessages {
            messagesByConversationId[conversationId] = messages
        }
    }

    func archiveConversation(conversationId: String) {
        if requestCoordinator.isConversationRunning(conversationId) {
            statusMessage = "Stop active request before archiving"
            return
        }
        guard let persistence else { return }

        do {
            try persistence.archiveConversation(id: conversationId)
        } catch {
            statusMessage = "Failed to archive: \(error.localizedDescription)"
            return
        }

        sidebarThreads.removeAll { $0.id == conversationId }

        if activeConversationId == conversationId {
            resetConversation()
        }
    }

    func unarchiveConversation(conversationId: String) {
        guard let persistence else { return }

        do {
            try persistence.unarchiveConversation(id: conversationId)
        } catch {
            statusMessage = "Failed to unarchive: \(error.localizedDescription)"
            return
        }

        // Re-insert into sidebar sorted by lastActivityAt
        if let threads = try? persistence.fetchSidebarThreads(limit: 200) {
            if let restored = threads.first(where: { $0.id == conversationId }) {
                let insertIndex = sidebarThreads.firstIndex(where: {
                    $0.lastActivityAt < restored.lastActivityAt
                }) ?? sidebarThreads.endIndex
                sidebarThreads.insert(restored, at: insertIndex)
            }
        }
    }

    func fetchArchivedThreads() -> [ConversationSidebarThread] {
        guard let persistence else { return [] }
        return (try? persistence.fetchArchivedThreads()) ?? []
    }

    @discardableResult
    private func applyConversationSnapshot(
        _ snapshot: ConversationPageSnapshot,
        conversationId: String
    ) -> Bool {
        var didChange = false

        if messages != snapshot.messages {
            messages = snapshot.messages
            didChange = true
        }

        // Sync to message bucket
        messagesByConversationId[conversationId] = snapshot.messages

        if hasMoreOlderMessages != snapshot.hasMoreOlderMessages {
            hasMoreOlderMessages = snapshot.hasMoreOlderMessages
            didChange = true
        }

        if oldestLoadedOrderIndex != snapshot.oldestLoadedOrderIndex {
            oldestLoadedOrderIndex = snapshot.oldestLoadedOrderIndex
            didChange = true
        }

        if activeConversationId != conversationId {
            activeConversationId = conversationId
            didChange = true
        }

        return didChange
    }

    private func cacheCurrentConversationSnapshotIfNeeded() {
        guard let conversationId = activeConversationId else { return }
        guard messages.count <= RuntimeConstants.conversationMessagePageSize else { return }
        if let running = requestCoordinator?.runningRequest(forConversation: conversationId),
           let messageID = running.assistantMessageID
        {
            syncPresentedStreamingMessageIntoBucketsIfNeeded(
                conversationId: conversationId,
                messageID: messageID,
                content: running.presentedText
            )
        }
        let snapshot = ConversationPageSnapshot(
            messages: messages,
            hasMoreOlderMessages: hasMoreOlderMessages,
            oldestLoadedOrderIndex: oldestLoadedOrderIndex
        )
        cacheConversationSnapshot(conversationId: conversationId, snapshot: snapshot)
    }

    private func cacheConversationSnapshot(
        conversationId: String,
        snapshot: ConversationPageSnapshot
    ) {
        conversationPageCache[conversationId] = snapshot
        conversationPageCacheOrder.removeAll { $0 == conversationId }
        conversationPageCacheOrder.append(conversationId)

        while conversationPageCacheOrder.count > conversationPageCacheCapacity {
            let evicted = conversationPageCacheOrder.removeFirst()
            conversationPageCache.removeValue(forKey: evicted)
        }
    }

    func markConversationSwitchLayoutReady() {
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.conversationId == activeConversationId else { return }
        guard trace.layoutReadyAt == nil else { return }

        trace.layoutReadyAt = .now
        let layoutReadyAt = trace.layoutReadyAt ?? .now
        let snapshotLagMs: Int?
        let snapshotLag: String
        if let snapshotAt = trace.snapshotAppliedAt {
            let lag = Int(layoutReadyAt.timeIntervalSince(snapshotAt) * 1000)
            snapshotLagMs = lag
            snapshotLag = "\(lag)ms"
        } else {
            snapshotLagMs = nil
            snapshotLag = "n/a"
        }
        let totalElapsedMs = Int(layoutReadyAt.timeIntervalSince(trace.startedAt) * 1000)
        PerfTrace.duration(
            PerfTrace.Event.switchLayoutReady,
            ms: Double(totalElapsedMs),
            fields: [
                "generation": "\(trace.generation)",
                "conversation": trace.conversationId
            ]
        )
        if let snapshotLagMs {
            PerfTrace.duration(
                PerfTrace.Event.switchSnapshotToLayoutReady,
                ms: Double(snapshotLagMs),
                fields: [
                    "generation": "\(trace.generation)",
                    "conversation": trace.conversationId
                ]
            )
        }
        ConversationSwitchDebug.log(
            "layout-ready generation=\(trace.generation) conversation=\(trace.conversationId) " +
                "snapshot->layout=\(snapshotLag) total=\(totalElapsedMs)ms"
        )
        activeConversationSwitchTrace = trace
    }

    func reportActiveConversationRichRenderReadyIfNeeded() {
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.conversationId == activeConversationId else { return }
        guard let snapshotAppliedAt = trace.snapshotAppliedAt else { return }
        guard !trace.didLogRichRenderReady else { return }

        trace.didLogRichRenderReady = true
        let now = Date.now
        let snapshotElapsedMs = Int(now.timeIntervalSince(snapshotAppliedAt) * 1000)
        let totalElapsedMs = Int(now.timeIntervalSince(trace.startedAt) * 1000)
        let stats = makeConversationMessageStats(messages)
        PerfTrace.duration(
            PerfTrace.Event.switchRichReady,
            ms: Double(totalElapsedMs),
            fields: [
                "generation": "\(trace.generation)",
                "conversation": trace.conversationId,
                "messages": "\(stats.messageCount)"
            ]
        )
        PerfTrace.duration(
            PerfTrace.Event.switchSnapshotToRichReady,
            ms: Double(snapshotElapsedMs),
            fields: [
                "generation": "\(trace.generation)",
                "conversation": trace.conversationId,
                "messages": "\(stats.messageCount)"
            ]
        )
        ConversationSwitchDebug.log(
            "rich-ready generation=\(trace.generation) conversation=\(trace.conversationId) " +
                "snapshot->rich=\(snapshotElapsedMs)ms total=\(totalElapsedMs)ms " +
                "messages=\(stats.messageCount) longAssistants=\(stats.longAssistantCount)"
        )
        activeConversationSwitchTrace = nil
    }

    func reportSwitchPresentedRenderedFromReloadIfNeeded(
        conversationId: String?,
        generation: UInt64,
        renderCacheHits: Int,
        renderCacheMisses: Int,
        contentWidth: Int
    ) {
        guard let conversationId else { return }
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.generation == generation else { return }
        guard trace.conversationId == conversationId else { return }

        let hits = max(0, renderCacheHits)
        let misses = max(0, renderCacheMisses)
        let total = hits + misses

        if !trace.didLogRenderCacheHitRate, total > 0 {
            let hitRate = Double(hits) / Double(total)
            PerfTrace.count(
                PerfTrace.Event.renderCacheHitRate,
                fields: [
                    "generation": "\(generation)",
                    "conversation": conversationId,
                    "hits": "\(hits)",
                    "misses": "\(misses)",
                    "hit_rate": String(format: "%.2f", hitRate)
                ]
            )
            trace.didLogRenderCacheHitRate = true
        }

        guard !trace.didLogPresentedRendered else {
            activeConversationSwitchTrace = trace
            return
        }
        guard total > 0 else {
            activeConversationSwitchTrace = trace
            return
        }

        let mode = misses > 0 ? "cache-miss-reload" : "cache-hit-reload"
        let elapsedMs = Int(Date.now.timeIntervalSince(trace.startedAt) * 1000)
        PerfTrace.duration(
            PerfTrace.Event.switchPresentedRendered,
            ms: Double(elapsedMs),
            fields: [
                "generation": "\(generation)",
                "conversation": conversationId,
                "mode": mode,
                "content_width": "\(contentWidth)",
                "hits": "\(hits)",
                "misses": "\(misses)"
            ]
        )

        trace.didLogPresentedRendered = true
        activeConversationSwitchTrace = trace
    }

    func reportHotSceneSwitchPresentedRenderedIfNeeded(
        conversationId: String,
        generation: UInt64
    ) {
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.generation == generation else { return }
        guard trace.conversationId == conversationId else { return }

        if trace.snapshotAppliedAt == nil {
            trace.snapshotAppliedAt = .now
            let elapsedMs = Int(trace.snapshotAppliedAt!.timeIntervalSince(trace.startedAt) * 1000)
            let stats = makeConversationMessageStats(messages)
            PerfTrace.duration(
                PerfTrace.Event.switchSnapshotApplied,
                ms: Double(elapsedMs),
                fields: [
                    "generation": "\(generation)",
                    "conversation": conversationId,
                    "source": "hot-scene",
                    "messages": "\(stats.messageCount)"
                ]
            )
        }

        if !trace.didLogRenderCacheHitRate {
            PerfTrace.count(
                PerfTrace.Event.renderCacheHitRate,
                fields: [
                    "generation": "\(generation)",
                    "conversation": conversationId,
                    "hits": "0",
                    "misses": "0",
                    "hit_rate": "n/a",
                    "mode": "hot-scene"
                ]
            )
            trace.didLogRenderCacheHitRate = true
        }

        if !trace.didLogPresentedRendered {
            let elapsedMs = Int(Date.now.timeIntervalSince(trace.startedAt) * 1000)
            PerfTrace.duration(
                PerfTrace.Event.switchPresentedRendered,
                ms: Double(elapsedMs),
                fields: [
                    "generation": "\(generation)",
                    "conversation": conversationId,
                    "mode": "hot-scene"
                ]
            )
            trace.didLogPresentedRendered = true
        }

        activeConversationSwitchTrace = trace
        markConversationSwitchLayoutReady()
        reportActiveConversationRichRenderReadyIfNeeded()
    }

    var cachedConversationIDsForTesting: [String] {
        conversationPageCacheOrder
    }

    func runStartupPrewarmForTesting() async {
        await performStartupPrewarmIfNeeded()
    }

    #if DEBUG
        func runAutomationScenarioIfNeeded() {
            guard !Self.didStartAutomationScenario else { return }
            guard let raw = ProcessInfo.processInfo.environment["HUSH_AUTOMATION_SCENARIO"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty
            else {
                return
            }

            Self.didStartAutomationScenario = true
            Task(priority: .utility) { @MainActor [weak self] in
                guard let self else { return }
                await self.runAutomationScenario(raw)
            }
        }

        private static var didStartAutomationScenario: Bool = false

        private func runAutomationScenario(_ rawScenario: String) async {
            let scenario = rawScenario.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch scenario {
            case "hot-scene-memory":
                await runHotSceneMemoryAutomation()
            default:
                return
            }
        }

        private func runHotSceneMemoryAutomation() async {
            guard let persistence else { return }

            // Seed a small set of worst-case conversations and drive a deterministic switch pattern.
            // This is intended for xctrace-based memory profiling automation.
            let now = Date.now

            func seedConversation(_ conversationId: String, prefix: String) {
                for index in 1 ... 18 {
                    let content = """
                    # \(prefix)\(index)

                    Inline math: $E=mc^2$

                    | a | b | c |
                    |---|---|---|
                    | 1 | 2 | 3 |
                    | 4 | 5 | 6 |
                    | 7 | 8 | 9 |
                    """
                    try? persistence.persistSystemMessage(
                        ChatMessage(role: .assistant, content: content),
                        conversationId: conversationId,
                        status: .completed
                    )
                }
            }

            // Create 3 conversations to fill the hot scene pool (capacity=3).
            guard let conversationA = try? persistence.createNewConversation(),
                  let conversationB = try? persistence.createNewConversation(),
                  let conversationC = try? persistence.createNewConversation()
            else { return }

            seedConversation(conversationA, prefix: "A")
            seedConversation(conversationB, prefix: "B")
            seedConversation(conversationC, prefix: "C")

            sidebarThreads = [
                ConversationSidebarThread(id: conversationA, title: "A", lastActivityAt: now),
                ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: now),
                ConversationSidebarThread(id: conversationC, title: "C", lastActivityAt: now)
            ]

            // Phase 1: baseline — stay on a single conversation.
            activateConversation(conversationId: conversationA)
            _ = await waitForAutomationReady(conversationId: conversationA, timeout: .seconds(10))

            let baselineHold = automationSeconds(for: "HUSH_AUTOMATION_BASELINE_HOLD_S", default: 8)
            try? await Task.sleep(for: .seconds(baselineHold))

            // Phase 2: hot — switch to fill the pool with 3 scenes.
            activateConversation(conversationId: conversationB)
            _ = await waitForAutomationReady(conversationId: conversationB, timeout: .seconds(10))
            await Task.yield()

            activateConversation(conversationId: conversationC)
            _ = await waitForAutomationReady(conversationId: conversationC, timeout: .seconds(10))

            let hotHold = automationSeconds(for: "HUSH_AUTOMATION_HOT_HOLD_S", default: 14)
            try? await Task.sleep(for: .seconds(hotHold))

            if automationBool(for: "HUSH_AUTOMATION_EXIT", default: false) {
                NSApp.terminate(nil)
            }
        }

        private func waitForAutomationReady(conversationId: String, timeout: Duration) async -> Bool {
            let deadline = ContinuousClock.now + timeout
            while ContinuousClock.now < deadline {
                if activeConversationId == conversationId, statusMessage == "Ready" {
                    return true
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }

        private func automationSeconds(for key: String, default fallback: Double) -> Double {
            guard let raw = ProcessInfo.processInfo.environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty,
                let seconds = Double(raw)
            else {
                return fallback
            }
            return max(0, seconds)
        }

        private func automationBool(for key: String, default fallback: Bool) -> Bool {
            guard let raw = ProcessInfo.processInfo.environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            else {
                return fallback
            }
            if raw == "1" || raw == "true" || raw == "yes" { return true }
            if raw == "0" || raw == "false" || raw == "no" { return false }
            return fallback
        }
    #endif

    private func markConversationSwitchSnapshotAppliedIfNeeded(
        conversationId: String,
        generation: UInt64,
        source: String,
        stats: ConversationMessageStats
    ) {
        guard var trace = activeConversationSwitchTrace else { return }
        guard trace.generation == generation else { return }
        guard trace.conversationId == conversationId else { return }
        guard trace.snapshotAppliedAt == nil else { return }

        trace.snapshotAppliedAt = .now
        let elapsedMs = Int(trace.snapshotAppliedAt!.timeIntervalSince(trace.startedAt) * 1000)
        PerfTrace.duration(
            PerfTrace.Event.switchSnapshotApplied,
            ms: Double(elapsedMs),
            fields: [
                "generation": "\(generation)",
                "conversation": conversationId,
                "source": source,
                "messages": "\(stats.messageCount)"
            ]
        )
        ConversationSwitchDebug.log(
            "snapshot-applied source=\(source) generation=\(generation) conversation=\(conversationId) " +
                "elapsed=\(elapsedMs)ms messages=\(stats.messageCount) assistants=\(stats.assistantCount) " +
                "longAssistants=\(stats.longAssistantCount) chars=\(stats.totalChars)"
        )
        activeConversationSwitchTrace = trace
    }

    private func scheduleStartupPrewarmIfNeeded() {
        ConversationSwitchDebug.log("startup-prewarm-scheduled")
        startupPrewarmTask?.cancel()
        startupPrewarmTask = Task { [weak self] in
            guard let self else { return }
            await self.performStartupPrewarmIfNeeded()
        }
    }

    private func performStartupPrewarmIfNeeded() async {
        guard let persistence else { return }

        let candidateIDs = Array(
            sidebarThreads
                .map(\.id)
                .filter { $0 != activeConversationId }
                .prefix(RenderConstants.startupPrewarmConversationCount)
        )
        guard !candidateIDs.isEmpty else {
            ConversationSwitchDebug.log("startup-prewarm-skip no-candidates")
            return
        }

        ConversationSwitchDebug.log(
            "startup-prewarm-begin candidates=\(candidateIDs.count) active=\(activeConversationId ?? "nil")"
        )

        for conversationId in candidateIDs {
            if Task.isCancelled { return }

            do {
                let fetchStartedAt = Date.now
                let page = try await Task.detached(priority: .utility) {
                    try persistence.fetchMessagePage(
                        conversationId: conversationId,
                        beforeOrderIndex: nil,
                        limit: RenderConstants.startupPrewarmMessageLimit
                    )
                }.value

                if Task.isCancelled { return }

                let snapshot = ConversationPageSnapshot(
                    messages: page.messages,
                    hasMoreOlderMessages: page.hasMoreOlderMessages,
                    oldestLoadedOrderIndex: page.oldestOrderIndex
                )
                cacheConversationSnapshot(conversationId: conversationId, snapshot: snapshot)
                let fetchMs = Int(Date.now.timeIntervalSince(fetchStartedAt) * 1000)
                let stats = makeConversationMessageStats(page.messages)
                let prewarmedCount = await prewarmRenderCache(
                    for: page.messages,
                    conversationID: conversationId
                )
                ConversationSwitchDebug.log(
                    "startup-prewarm-done conversation=\(conversationId) fetchMs=\(fetchMs) " +
                        "messages=\(stats.messageCount) assistants=\(stats.assistantCount) " +
                        "longAssistants=\(stats.longAssistantCount) prewarmedAssistants=\(prewarmedCount)"
                )
            } catch {
                ConversationSwitchDebug.log(
                    "startup-prewarm-failed conversation=\(conversationId) error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func prewarmRenderCache(
        for messages: [ChatMessage],
        conversationID: String?,
        availableWidth: CGFloat = HushSpacing.chatContentMaxWidth
    ) async -> Int {
        let assistants = messages.filter { $0.role == .assistant }
        guard !assistants.isEmpty else { return 0 }

        let targetMessages = assistants.suffix(RenderConstants.startupRenderPrewarmAssistantMessageCap)
        guard !targetMessages.isEmpty else { return 0 }

        let style = RenderStyle.fromTheme()
        let inputs = targetMessages.map {
            MessageRenderInput(
                content: $0.content,
                availableWidth: availableWidth,
                style: style,
                isStreaming: false
            )
        }
        await messageRenderRuntime.prewarm(inputs: inputs, protectFor: conversationID)
        return targetMessages.count
    }

    func scheduleStreamingCompletePrewarmIfNeeded(
        conversationID: String,
        finalAssistantContent: String
    ) {
        guard conversationID != activeConversationId else { return }
        guard !finalAssistantContent.isEmpty else { return }

        Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await Task.yield()

            let isHotScene = self.hotScenePool?.hotConversationIDs.contains(conversationID) ?? false
            if isHotScene {
                let messages = self.messagesForConversation(conversationID)
                _ = await self.prewarmRenderCache(for: messages, conversationID: conversationID)
                return
            }

            let style = RenderStyle.fromTheme()
            let input = MessageRenderInput(
                content: finalAssistantContent,
                availableWidth: HushSpacing.chatContentMaxWidth,
                style: style,
                isStreaming: false
            )
            await self.messageRenderRuntime.prewarm(
                inputs: [input],
                protectFor: conversationID
            )
        }
    }

    func performResizeCacheCleanup(
        contentWidth: CGFloat,
        hotConversationIDs: [String]
    ) async {
        guard contentWidth > 0 else { return }

        messageRenderRuntime.clearAllProtections()

        var targets: [String] = []
        if let activeConversationId {
            targets.append(activeConversationId)
        }
        targets.append(contentsOf: hotConversationIDs)

        var seen: Set<String> = []
        for conversationID in targets where seen.insert(conversationID).inserted {
            let messages = messagesForConversation(conversationID)
            _ = await prewarmRenderCache(
                for: messages,
                conversationID: conversationID,
                availableWidth: contentWidth
            )
            await Task.yield()
        }
    }

    private func noteUserActivityForIdlePrewarm() {
        scheduleIdlePrewarmIfNeeded()
    }

    func cancelIdlePrewarmFromCoordinator() {
        idlePrewarmTask?.cancel()
    }

    func scheduleIdlePrewarmFromCoordinator() {
        scheduleIdlePrewarmIfNeeded()
    }

    private func scheduleIdlePrewarmIfNeeded() {
        idlePrewarmTask?.cancel()
        idlePrewarmTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .seconds(RenderConstants.idlePrewarmDelay))
            if Task.isCancelled { return }
            guard !self.isActiveConversationSending else { return }

            let conversationIDs = self.hotConversationIDsForIdlePrewarm()
            guard !conversationIDs.isEmpty else { return }

            for conversationID in conversationIDs {
                if Task.isCancelled { return }
                guard let snapshot = self.conversationPageCache[conversationID] else { continue }
                _ = await self.prewarmRenderCache(
                    for: snapshot.messages,
                    conversationID: conversationID
                )
            }
        }
    }

    private func hotConversationIDsForIdlePrewarm() -> [String] {
        let active = activeConversationId
        return Array(
            conversationPageCacheOrder
                .reversed()
                .filter { $0 != active }
                .prefix(RenderConstants.startupPrewarmConversationCount)
        )
    }

    private func scheduleSwitchAwayPrewarmIfNeeded(
        from previousConversationId: String?,
        persistence: ChatPersistenceCoordinator
    ) {
        guard let previousConversationId else { return }

        let activatedConversationId = activeConversationId
        let adjacent = sidebarAdjacentConversationIDs(around: previousConversationId)
            .filter { $0 != activatedConversationId }

        guard !adjacent.isEmpty else { return }

        switchAwayPrewarmTask?.cancel()
        switchAwayPrewarmTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await Task.yield()

            for conversationID in adjacent {
                if Task.isCancelled { return }
                let messages = self.messagesForPrewarm(conversationId: conversationID, persistence: persistence)
                if messages.isEmpty { continue }
                _ = await self.prewarmRenderCache(
                    for: messages,
                    conversationID: conversationID
                )
                await Task.yield()
            }
        }
    }

    private func sidebarAdjacentConversationIDs(around conversationId: String) -> [String] {
        guard let idx = sidebarThreads.firstIndex(where: { $0.id == conversationId }) else { return [] }

        var candidates: [String] = []
        if idx > 0 {
            candidates.append(sidebarThreads[idx - 1].id)
        }
        if idx + 1 < sidebarThreads.count {
            candidates.append(sidebarThreads[idx + 1].id)
        }

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }

    private func messagesForPrewarm(
        conversationId: String,
        persistence: ChatPersistenceCoordinator
    ) -> [ChatMessage] {
        if let snapshot = conversationPageCache[conversationId] {
            return snapshot.messages
        }
        if let bucket = messagesByConversationId[conversationId] {
            return bucket
        }
        return (try? persistence.fetchMessagePage(
            conversationId: conversationId,
            beforeOrderIndex: nil,
            limit: RenderConstants.startupPrewarmMessageLimit
        ).messages) ?? []
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .background || phase == .inactive else { return }
        flushSettings()
    }

    // MARK: - Data Management

    func fetchDataStats() async -> DataStats {
        guard let persistence else {
            return DataStats(databaseSizeBytes: 0, conversationCount: 0, messageCount: 0)
        }
        return await Task.detached(priority: .utility) {
            let size = persistence.databaseFileSize()
            let conversations = (try? persistence.conversationCount()) ?? 0
            let messages = (try? persistence.messageCount()) ?? 0
            return DataStats(databaseSizeBytes: size, conversationCount: conversations, messageCount: messages)
        }.value
    }

    func deleteAllChatHistory() async {
        guard !isSending else {
            statusMessage = "Stop active request before clearing data"
            return
        }
        guard let persistence else { return }

        sidebarThreadsLoadGeneration &+= 1

        do {
            try await Task.detached(priority: .userInitiated) {
                try persistence.deleteAllChatData()
            }.value
        } catch {
            statusMessage = "Failed to clear data: \(error.localizedDescription)"
            return
        }

        sidebarThreads.removeAll()
        conversationPageCache.removeAll()
        conversationPageCacheOrder.removeAll()
        isLoadingMoreSidebarThreads = false
        sidebarThreadsCursor = nil
        hasMoreSidebarThreads = false

        messages.removeAll()
        isLoadingOlderMessages = false
        hasMoreOlderMessages = false
        oldestLoadedOrderIndex = nil
        activeConversationId = try? persistence.createNewConversation()
        conversationLoadGeneration &+= 1
        activeConversationRenderGeneration = conversationLoadGeneration
        messageRenderRuntime.setActiveConversation(
            conversationID: activeConversationId,
            generation: activeConversationRenderGeneration
        )
        statusMessage = "All chat history cleared"
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
            try preferencesRepository?.save(settings)
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

private extension AppContainer {
    func fallbackProviderConfiguration() -> ProviderConfiguration? {
        settings.providerConfigurations.first(where: { $0.isEnabled })
    }

    func normalizeEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? OpenAIProvider.defaultEndpoint : trimmed
    }

    func normalizedEndpoint(_ endpoint: String, for type: ProviderType) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch type {
            case .openAI:
                return OpenAIProvider.defaultEndpoint
            #if DEBUG
                case .mock:
                    return "local://mock-provider"
            #endif
            }
        }
        return trimmed
    }
}

// MARK: - Credential Helpers

extension AppContainer {
    func normalizedCredentialRef(from configuration: ProviderConfiguration?) -> String {
        if let ref = configuration?.credentialRef?.trimmingCharacters(in: .whitespacesAndNewlines), !ref.isEmpty {
            return ref
        }

        let providerIDFallback = configuration?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return providerIDFallback.isEmpty ? OpenAISettingsInput.providerID : providerIDFallback
    }

    func saveProviderCredential(_ secret: String, forRef credentialRef: String) throws {
        try credentialStore.setSecret(secret, forCredentialRef: credentialRef)
    }

    func hasProviderCredential(forRef credentialRef: String) -> Bool {
        credentialStore.hasSecret(forCredentialRef: credentialRef)
    }

    func readProviderCredential(forRef credentialRef: String) -> String? {
        try? credentialStore.secret(forCredentialRef: credentialRef)
    }
}

// MARK: - Agent Preset Management

extension AppContainer {
    func fetchAgentPresets() -> [AgentPreset] {
        (try? agentPresetRepository?.fetchAll()) ?? []
    }

    func saveAgentPreset(_ preset: AgentPreset) {
        try? agentPresetRepository?.upsert(preset)
    }

    func deleteAgentPreset(id: String) {
        try? agentPresetRepository?.delete(id: id)
    }
}

// MARK: - Prompt Template Management

extension AppContainer {
    func fetchPromptTemplates() -> [PromptTemplate] {
        (try? promptTemplateRepository?.fetchAll()) ?? []
    }

    func savePromptTemplate(_ template: PromptTemplate) {
        try? promptTemplateRepository?.upsert(template)
    }

    func deletePromptTemplate(id: String) {
        try? promptTemplateRepository?.delete(id: id)
    }
}

#if DEBUG
    extension AppContainer {
        func setRunningConversationIDsForTesting(_ ids: Set<String>) {
            runningConversationIds = ids
        }
    }
#endif

// swiftlint:enable file_length type_body_length
