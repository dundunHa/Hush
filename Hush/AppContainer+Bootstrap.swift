import Foundation

extension AppContainer {
    /// Second-phase setup: create the coordinator after `self` is fully initialized.
    func configureCoordinator(
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

            let prefsRepo = preferencesRepository!
            let existingPrefs = try prefsRepo.fetch()
            if existingPrefs == nil {
                let jsonStore = JSONSettingsStore.defaultStore()
                let jsonSettings = (try? jsonStore.load()) ?? .default
                try prefsRepo.save(jsonSettings)

                let configRepo = providerConfigRepository!
                let existingDBConfigs = try configRepo.fetchAll()
                if existingDBConfigs.isEmpty {
                    for config in jsonSettings.providerConfigurations {
                        try configRepo.upsert(config)
                    }
                }

                loadedSettings = jsonSettings
            } else {
                let snapshot = existingPrefs.toAppPreferences()
                loadedSettings.selectedProviderID = snapshot.selectedProviderID
                loadedSettings.selectedModelID = snapshot.selectedModelID
                loadedSettings.parameters = snapshot.parameters
                loadedSettings.quickBar = snapshot.quickBar
                loadedSettings.theme = snapshot.theme
                loadedSettings.fontSettings = snapshot.fontSettings
                loadedSettings.maxConcurrentRequests = snapshot.maxConcurrentRequests
            }

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
            print("[Hush] Database bootstrap failed, running in memory-only mode: \(error)")
        }

        let container = AppContainer(
            settings: loadedSettings,
            preferencesRepository: preferencesRepository,
            registry: registry,
            messageRenderRuntime: MessageRenderRuntime(),
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
        return container
    }

    @MainActor
    static func forTesting(
        settings: AppSettings? = nil,
        preferencesRepository: GRDBAppPreferencesRepository? = nil,
        registry: ProviderRegistry? = nil,
        messageRenderRuntime: MessageRenderRuntime? = nil,
        persistence: ChatPersistenceCoordinator? = nil,
        messageAssetStore: (any MessageAssetStore)? = nil,
        catalogRepository: (any ProviderCatalogRepository)? = nil,
        providerConfigRepository: (any ProviderConfigurationRepository)? = nil,
        agentPresetRepository: (any AgentPresetRepository)? = nil,
        promptTemplateRepository: (any PromptTemplateRepository)? = nil,
        credentialResolver: CredentialResolver = CredentialResolver(),
        activeConversationId: String? = nil,
        messages: [ChatMessage] = [],
        sidebarThreads: [ConversationSidebarThread] = [],
        hasMoreOlderMessages: Bool = false,
        oldestLoadedOrderIndex: Int? = nil,
        hasMoreSidebarThreads: Bool = false,
        sidebarThreadsCursor: SidebarThreadsCursor? = nil,
        enableStartupPrewarm: Bool = false
    ) -> AppContainer {
        var testRegistry = registry ?? ProviderRegistry()
        if registry == nil {
            testRegistry.register(MockProvider(id: "mock"))
        }
        let container = AppContainer(
            settings: settings ?? .testDefault,
            preferencesRepository: preferencesRepository,
            registry: testRegistry,
            messageRenderRuntime: messageRenderRuntime ?? MessageRenderRuntime(),
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
        _ = enableStartupPrewarm
        return container
    }
}
