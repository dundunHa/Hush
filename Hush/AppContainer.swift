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
    var requestCoordinator: RequestCoordinator!
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

    init(
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
}
