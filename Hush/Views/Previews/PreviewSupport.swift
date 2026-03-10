#if DEBUG

    import Foundation

    // MARK: - Preview Fixtures

    enum PreviewFixtures {
        // MARK: - ChatMessage

        static func userMessage(
            content: String = "Hello, how can you help me today?",
            createdAt: Date = .now
        ) -> ChatMessage {
            ChatMessage(role: .user, content: content, createdAt: createdAt)
        }

        static func assistantMessage(
            content: String = "I'm here to help! Ask me anything.",
            createdAt: Date = .now
        ) -> ChatMessage {
            ChatMessage(role: .assistant, content: content, createdAt: createdAt)
        }

        static func systemMessage(
            content: String = "You are a helpful assistant.",
            createdAt: Date = .now
        ) -> ChatMessage {
            ChatMessage(role: .system, content: content, createdAt: createdAt)
        }

        static var sampleConversation: [ChatMessage] {
            let base = Date.now
            return [
                userMessage(
                    content: "What is SwiftUI?",
                    createdAt: base.addingTimeInterval(-60)
                ),
                assistantMessage(
                    content: """
                    SwiftUI is Apple's declarative UI framework. It lets you build \
                    user interfaces across all Apple platforms using Swift code. \
                    Instead of using storyboards or XIBs, you describe your UI in code \
                    and SwiftUI handles the rendering.
                    """,
                    createdAt: base.addingTimeInterval(-30)
                ),
                userMessage(
                    content: "Can you show me a simple example?",
                    createdAt: base
                )
            ]
        }

        // MARK: - ConversationSidebarThread

        static func sidebarThread(
            id: String = UUID().uuidString,
            title: String = "Sample conversation",
            lastActivityAt: Date = .now
        ) -> ConversationSidebarThread {
            ConversationSidebarThread(
                id: id,
                title: title,
                lastActivityAt: lastActivityAt
            )
        }

        static var sampleSidebarThreads: [ConversationSidebarThread] {
            let base = Date.now
            return [
                sidebarThread(
                    title: "SwiftUI Layout Tips",
                    lastActivityAt: base.addingTimeInterval(-300)
                ),
                sidebarThread(
                    title: "Debugging Concurrency",
                    lastActivityAt: base.addingTimeInterval(-3600)
                ),
                sidebarThread(
                    title: "GRDB Migration Strategy",
                    lastActivityAt: base.addingTimeInterval(-86400)
                )
            ]
        }

        // MARK: - ProviderConfiguration

        static func providerConfiguration(
            id: String = "preview-openai",
            name: String = "OpenAI",
            type: ProviderType = .openAI,
            endpoint: String = "https://api.openai.com/v1",
            defaultModelID: String = "gpt-4o",
            isEnabled: Bool = true
        ) -> ProviderConfiguration {
            ProviderConfiguration(
                id: id,
                name: name,
                type: type,
                endpoint: endpoint,
                apiKeyEnvironmentVariable: "",
                defaultModelID: defaultModelID,
                isEnabled: isEnabled
            )
        }

        static var sampleProviderConfigurations: [ProviderConfiguration] {
            [
                providerConfiguration(),
                ProviderConfiguration.mockDefault()
            ]
        }

        // MARK: - PromptTemplate

        static func promptTemplate(
            id: String = UUID().uuidString,
            name: String = "Code Review",
            content: String = "Review the following code for bugs and improvements:\n\n{{code}}",
            category: String = "Development"
        ) -> PromptTemplate {
            PromptTemplate(
                id: id,
                name: name,
                content: content,
                category: category
            )
        }

        static var samplePromptTemplates: [PromptTemplate] {
            [
                promptTemplate(),
                promptTemplate(
                    name: "Summarize",
                    content: "Summarize the following text concisely:\n\n{{text}}",
                    category: "Writing"
                ),
                promptTemplate(
                    name: "Translate",
                    content: "Translate the following to {{language}}:\n\n{{text}}",
                    category: "Language"
                )
            ]
        }

        // MARK: - AgentPreset

        static func agentPreset(
            id: String = UUID().uuidString,
            name: String = "Code Assistant",
            systemPrompt: String = "You are an expert programmer. Help with code questions.",
            providerID: String = "preview-openai",
            modelID: String = "gpt-4o",
            temperature: Double = 0.7,
            maxTokens: Int = 4096,
            isDefault: Bool = false
        ) -> AgentPreset {
            AgentPreset(
                id: id,
                name: name,
                systemPrompt: systemPrompt,
                providerID: providerID,
                modelID: modelID,
                temperature: temperature,
                maxTokens: maxTokens,
                isDefault: isDefault
            )
        }

        static var sampleAgentPresets: [AgentPreset] {
            [
                agentPreset(isDefault: true),
                agentPreset(
                    name: "Creative Writer",
                    systemPrompt: "You are a creative writer. Help craft engaging stories.",
                    temperature: 0.9,
                    maxTokens: 8192
                ),
                agentPreset(
                    name: "Data Analyst",
                    systemPrompt: "You are a data analyst. Help analyze and interpret data.",
                    temperature: 0.3,
                    maxTokens: 4096
                )
            ]
        }

        // MARK: - ModelParameters

        static func modelParameters(
            temperature: Double = 0.7,
            topP: Double = 1.0,
            maxTokens: Int = 4096,
            presencePenalty: Double = 0.0,
            frequencyPenalty: Double = 0.0
        ) -> ModelParameters {
            ModelParameters(
                temperature: temperature,
                topP: topP,
                maxTokens: maxTokens,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty
            )
        }
    }

    // MARK: - Preview Container Factory

    extension AppContainer {
        @MainActor
        static func makePreviewContainer(
            settings: AppSettings? = nil,
            activeConversationId: String? = nil,
            messages: [ChatMessage] = [],
            sidebarThreads: [ConversationSidebarThread] = [],
            agentPresetRepository: (any AgentPresetRepository)? = nil,
            promptTemplateRepository: (any PromptTemplateRepository)? = nil
        ) -> AppContainer {
            forTesting(
                settings: settings,
                activeConversationId: activeConversationId,
                messages: messages,
                sidebarThreads: sidebarThreads,
                messageRenderRuntime: MessageRenderRuntime(),
                agentPresetRepository: agentPresetRepository,
                promptTemplateRepository: promptTemplateRepository,
                enableStartupPrewarm: false
            )
        }

        @MainActor
        static func makePreviewContainerWithPersistence() -> AppContainer {
            guard let dbManager = try? DatabaseManager.inMemory() else {
                return makePreviewContainer()
            }
            let coordinator = ChatPersistenceCoordinator(dbManager: dbManager)
            let conversationId = (try? coordinator.createNewConversation()) ?? UUID().uuidString
            for message in PreviewFixtures.sampleConversation {
                try? coordinator.persistUserMessage(message, conversationId: conversationId)
            }
            return forTesting(
                persistence: coordinator,
                activeConversationId: conversationId,
                messages: PreviewFixtures.sampleConversation,
                messageRenderRuntime: MessageRenderRuntime(),
                enableStartupPrewarm: false
            )
        }

        @MainActor
        static func makePreviewContainerWithData() -> AppContainer {
            let dbManager = try? DatabaseManager.inMemory()

            var agentPresetRepo: (any AgentPresetRepository)?
            var promptTemplateRepo: (any PromptTemplateRepository)?

            if let dbManager {
                let presetRepo = GRDBAgentPresetRepository(dbManager: dbManager)
                for preset in PreviewFixtures.sampleAgentPresets {
                    try? presetRepo.upsert(preset)
                }
                agentPresetRepo = presetRepo

                let templateRepo = GRDBPromptTemplateRepository(dbManager: dbManager)
                for template in PreviewFixtures.samplePromptTemplates {
                    try? templateRepo.upsert(template)
                }
                promptTemplateRepo = templateRepo
            }

            return makePreviewContainer(
                settings: .default,
                messages: PreviewFixtures.sampleConversation,
                sidebarThreads: PreviewFixtures.sampleSidebarThreads,
                agentPresetRepository: agentPresetRepo,
                promptTemplateRepository: promptTemplateRepo
            )
        }
    }

#endif
