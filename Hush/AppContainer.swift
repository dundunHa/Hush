import AppKit
import Combine
import Foundation
import os
import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
    // MARK: - Published State

    @Published var settings: AppSettings {
        didSet {
            persistSettingsIfNeeded(previous: oldValue)
            if oldValue.maxConcurrentRequests != settings.maxConcurrentRequests {
                requestCoordinator?.updateMaxConcurrent(settings.maxConcurrentRequests)
            }
        }
    }

    @Published var messages: [ChatMessage]
    @Published var sidebarThreads: [ConversationSidebarThread]
    @Published var isLoadingOlderMessages: Bool
    @Published var hasMoreOlderMessages: Bool
    @Published var isLoadingMoreSidebarThreads: Bool
    @Published var hasMoreSidebarThreads: Bool
    @Published var isActiveConversationLoading: Bool = false
    @Published var activeConversationLoadError: String?

    @Published var showQuickBar: Bool = false
    @Published var quickBarState: QuickBarSessionState = .empty
    @Published var statusMessage: String = "Ready"

    // MARK: - Request Lifecycle State (managed by RequestCoordinator)

    var requestStates: [RequestID: ActiveRequestState] = [:]
    @Published var runningConversationIds: Set<String> = []
    @Published var queuedConversationCounts: [String: Int] = [:]
    @Published var unreadCompletions: Set<String> = []
    @Published var catalogRefreshingProviderIDs: Set<String> = []
    @Published var catalogRefreshErrors: [String: String] = [:]

    // MARK: - Message Buckets

    var messagesByConversationId: [String: [ChatMessage]] = [:]
    weak var hotScenePool: HotScenePool?

    // MARK: - Computed

    var isSending: Bool {
        !runningConversationIds.isEmpty
    }

    var isActiveConversationSending: Bool {
        guard let activeId = activeConversationId else { return false }
        return runningConversationIds.contains(activeId)
    }

    var isQuickBarSending: Bool {
        guard let conversationId = quickBarState.conversationId else { return false }
        return runningConversationIds.contains(conversationId)
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

    let preferencesRepository: GRDBAppPreferencesRepository?
    var registry: ProviderRegistry
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

    let persistence: ChatPersistenceCoordinator?
    let messageAssetStore: (any MessageAssetStore)?
    @Published var activeConversationId: String?
    @Published var activeConversationRenderGeneration: UInt64 = 0

    // MARK: - Debounce State

    var debounceTask: Task<Void, Never>?
    var isDirty: Bool = false
    var conversationLoadTask: Task<Void, Never>?
    var conversationLoadGeneration: UInt64 = 0
    var oldestLoadedOrderIndex: Int?
    var sidebarThreadsCursor: SidebarThreadsCursor?
    var sidebarThreadsLoadGeneration: UInt64 = 0
    var conversationPageCache: [String: ConversationPageSnapshot] = [:]
    var conversationPageCacheOrder: [String] = []
    let conversationPageCacheCapacity = 8
    var startupPrewarmTask: Task<Void, Never>?
    var switchAwayPrewarmTask: Task<Void, Never>?
    var idlePrewarmTask: Task<Void, Never>?
    var activeConversationSwitchTrace: ConversationSwitchTrace?
    var quickBarGeneration: UInt64 = 0

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

    var sidebarThreadsLoadApplyDelayOverride: Duration?

    // MARK: - Init

    private init(
        settings: AppSettings,
        preferencesRepository: GRDBAppPreferencesRepository?,
        registry: ProviderRegistry,
        messageRenderRuntime: MessageRenderRuntime,
        persistence: ChatPersistenceCoordinator?,
        messageAssetStore: (any MessageAssetStore)? = nil,
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
        self.preferencesRepository = preferencesRepository
        self.registry = registry
        self.messageRenderRuntime = messageRenderRuntime
        self.persistence = persistence
        self.messageAssetStore = messageAssetStore
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
        credentialResolver: CredentialResolver,
        messageAssetStore: (any MessageAssetStore)?
    ) {
        requestCoordinator = RequestCoordinator(
            container: self,
            persistence: persistence,
            credentialResolver: credentialResolver,
            messageAssetStore: messageAssetStore
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
        var messageAssetStore: (any MessageAssetStore)?
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
            let baseURL = URL(fileURLWithPath: dbManager.databasePath)
                .deletingLastPathComponent()
                .appendingPathComponent("MessageAssets", isDirectory: true)
            messageAssetStore = FileMessageAssetStore(baseURL: baseURL)
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
                loadedSettings.fontSettings = prefs.fontSettings
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
            registry: registry,
            messageRenderRuntime: .shared,
            persistence: persistence,
            messageAssetStore: messageAssetStore,
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
            credentialResolver: CredentialResolver(),
            messageAssetStore: messageAssetStore
        )
        container.scheduleStartupPrewarmIfNeeded()
        return container
    }

    @MainActor
    static func forTesting(
        settings: AppSettings? = nil,
        preferencesRepository: GRDBAppPreferencesRepository? = nil,
        registry: ProviderRegistry? = nil,
        persistence: ChatPersistenceCoordinator? = nil,
        messageAssetStore: (any MessageAssetStore)? = nil,
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
            registry: resolvedRegistry,
            messageRenderRuntime: resolvedRenderRuntime,
            persistence: persistence,
            messageAssetStore: messageAssetStore,
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
            credentialResolver: credentialResolver,
            messageAssetStore: messageAssetStore
        )
        container.streamingPresentationPolicyOverride = streamingPresentationPolicyOverride
        if enableStartupPrewarm {
            container.scheduleStartupPrewarmIfNeeded()
        }
        return container
    }

    // MARK: - UI Actions

    func toggleQuickBar() {
        if showQuickBar {
            showQuickBar = false
        } else {
            prepareQuickBarSessionIfNeeded()
            showQuickBar = true
        }
    }

    func closeQuickBar() {
        showQuickBar = false
    }

    func updateQuickBarDraft(_ draft: String) {
        mutateQuickBarState { state in
            state.draft = draft
        }
    }

    func selectQuickBarModel(id: String) {
        prepareQuickBarSessionIfNeeded()
        mutateQuickBarState { state in
            state.selectedModelID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func selectQuickBarProvider(id: String) {
        prepareQuickBarSessionIfNeeded()
        guard let config = settings.providerConfigurations.first(where: {
            $0.id == id && $0.isEnabled
        }) else {
            return
        }

        let defaultModelID = config.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateQuickBarState { state in
            state.providerID = id
            state.selectedModelID = defaultModelID
        }
    }

    func resetQuickBarConversation() {
        guard !isQuickBarSending else { return }
        prepareQuickBarSessionIfNeeded(forceReset: true)
    }

    func continueQuickBarInMainChat() {
        guard !isQuickBarSending else { return }
        guard let quickBarConversationId = quickBarState.conversationId,
              !quickBarState.messages.isEmpty
        else {
            return
        }

        cacheCurrentConversationSnapshotIfNeeded()
        let messages = quickBarState.messages
        messagesByConversationId[quickBarConversationId] = messages
        let titleSeed = messages.first(where: { $0.role == .user })?.content
        let resolvedTitle = ConversationSidebarTitleFormatter.makeTitle(
            conversationTitle: nil,
            firstUserContent: titleSeed
        )
        let lastActivityAt = messages.last?.createdAt ?? .now
        upsertSidebarThread(
            conversationId: quickBarConversationId,
            title: resolvedTitle,
            lastActivityAt: lastActivityAt
        )

        let snapshot = ConversationPageSnapshot(
            messages: messages,
            hasMoreOlderMessages: false,
            oldestLoadedOrderIndex: nil
        )
        activateConversationSnapshot(
            snapshot,
            conversationId: quickBarConversationId,
            status: "Quick Bar chat opened in main window"
        )

        showQuickBar = false
        NotificationCenter.default.post(name: .hushActivateMainWindow, object: nil)
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

    #if DEBUG
        func runAutomationScenarioIfNeeded() {
            guard !Self.didStartAutomationScenario else { return }
            guard let raw = automationScenarioValue(),
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

        private func automationScenarioValue() -> String? {
            if let raw = ProcessInfo.processInfo.environment["HUSH_AUTOMATION_SCENARIO"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !raw.isEmpty
            {
                return raw
            }

            let arguments = ProcessInfo.processInfo.arguments

            if let index = arguments.firstIndex(of: "--automation-scenario"),
               arguments.indices.contains(index + 1)
            {
                let raw = arguments[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : raw
            }

            if let argument = arguments.first(where: { $0.hasPrefix("--automation-scenario=") }) {
                let raw = String(argument.dropFirst("--automation-scenario=".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? nil : raw
            }

            return nil
        }

        private func runAutomationScenario(_ rawScenario: String) async {
            let scenario = rawScenario.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch scenario {
            case "hot-scene-memory":
                await runHotSceneMemoryAutomation()
            case "quickbar-layout":
                runQuickBarLayoutAutomation(showsComplexAssistantReply: false)
            case "quickbar-layout-complex":
                runQuickBarLayoutAutomation(showsComplexAssistantReply: true)
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

        private func runQuickBarLayoutAutomation(showsComplexAssistantReply: Bool) {
            settings.providerConfigurations = [.mockDefault()]
            settings.selectedProviderID = "mock"
            settings.selectedModelID = "mock-text-1"

            let base = Date.now
            let messages = [
                ChatMessage(
                    role: .user,
                    content: "QuickBar 里用户消息右侧留白看起来比 assistant 左侧更窄，帮我看一下。",
                    createdAt: base.addingTimeInterval(-32)
                ),
                ChatMessage(
                    role: .assistant,
                    content: showsComplexAssistantReply
                        ? """
                        我先把 QuickBar 这里的复杂回复也放进同一个发布态检查里：

                        - 对比 mirrored lane 和 full-width card 的切换
                        - 确认 markdown 列表不会被误压进窄 bubble
                        - 检查 transcript 和 composer 的整体呼吸感
                        """
                        : """
                        我先对比消息容器、文本对齐和 transcript surface 的横向 inset，确认问题是出在 QuickBar 外层宽度，还是单条消息内部的布局约束。
                        """,
                    createdAt: base.addingTimeInterval(-12)
                )
            ]

            configureQuickBarPreview(
                conversationId: "quickbar-layout-automation",
                messages: messages,
                draft: "",
                isExpanded: true,
                isSending: false,
                showQuickBar: true,
                providerID: "mock",
                modelID: "mock-text-1"
            )
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
}

#if DEBUG
    extension AppContainer {
        func configureQuickBarPreview(
            conversationId: String = "quickbar-preview",
            messages: [ChatMessage] = [],
            draft: String = "",
            isExpanded: Bool,
            isSending: Bool = false,
            showQuickBar: Bool = true,
            providerID: String = "mock",
            modelID: String = "mock-text-1"
        ) {
            quickBarGeneration &+= 1

            let resolvedConversationId: String? = if messages.isEmpty, !isSending {
                nil
            } else {
                conversationId
            }

            quickBarState = QuickBarSessionState(
                conversationId: resolvedConversationId,
                messages: messages,
                draft: draft,
                isExpanded: isExpanded,
                providerID: providerID,
                selectedModelID: modelID,
                generation: quickBarGeneration
            )

            if let resolvedConversationId {
                messagesByConversationId[resolvedConversationId] = messages
            }

            runningConversationIds = if isSending, let resolvedConversationId {
                [resolvedConversationId]
            } else {
                []
            }
            self.showQuickBar = showQuickBar
            statusMessage = "Ready"
        }

        func setRunningConversationIDsForTesting(_ ids: Set<String>) {
            runningConversationIds = ids
        }

        func requestCoordinatorFlushStateCountForTesting() -> Int {
            requestCoordinator.flushStateCountForTesting()
        }
    }
#endif
