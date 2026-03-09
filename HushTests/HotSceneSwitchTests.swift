import AppKit
import Foundation
import GRDB
@testable import Hush
import Testing

@MainActor
@Suite(.serialized)
// swiftlint:disable:next type_body_length
struct HotSceneSwitchTests {
    private struct ConversationReadyTimeoutError: Error {}

    private func waitForConversationReady(
        _ container: AppContainer,
        conversationId: String,
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if container.activeConversationId == conversationId,
               container.statusMessage == "Ready"
            {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        throw ConversationReadyTimeoutError()
    }

    @Test("Visibility toggle hot hit does not reload")
    func visibilityToggleDoesNotReload() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: "A1"),
            conversationId: conversationA,
            status: .completed
        )
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: "B1"),
            conversationId: conversationB,
            status: .completed
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA
        )

        controller.update(container: container, theme: container.settings.theme)
        let sceneA = try #require(pool.sceneFor(conversationID: conversationA))
        let applyCountA = sceneA.applyCountForTesting

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container, theme: container.settings.theme)

        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)
        controller.update(container: container, theme: container.settings.theme)

        let sceneAAfter = try #require(pool.sceneFor(conversationID: conversationA))
        #expect(sceneAAfter.applyCountForTesting == applyCountA)
    }

    @Test("Cold miss creates a new scene and attaches it")
    func coldMissCreatesScene() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()
        try coordinator.persistSystemMessage(
            ChatMessage(role: .assistant, content: "B1"),
            conversationId: conversationB,
            status: .completed
        )

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA
        )

        controller.update(container: container, theme: container.settings.theme)
        #expect(pool.sceneFor(conversationID: conversationA) != nil)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container, theme: container.settings.theme)

        let sceneB = try #require(pool.sceneFor(conversationID: conversationB))
        #expect(sceneB.parent != nil)
        #expect(sceneB.view.superview != nil)
    }

    @Test("Eviction clears render cache protection for the evicted conversation")
    func evictionClearsProtection() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        // Inject a runtime whose RenderCache we can inspect.
        let renderCache = RenderCache(capacity: 20)
        let renderer = MessageContentRenderer(
            renderCache: renderCache,
            mathCache: MathRenderCache(capacity: 10)
        )
        let runtime = MessageRenderRuntime(
            renderer: renderer,
            scheduler: ConversationRenderScheduler()
        )

        let style = RenderStyle.fromTheme()
        let content = "protected"
        let key = RenderCache.makeKey(content: content, width: HushSpacing.chatContentMaxWidth, style: style)
        renderCache.set(key, output: MessageRenderOutput(
            attributedString: NSAttributedString(string: content),
            plainText: content,
            diagnostics: []
        ))
        renderCache.markProtected(key: key, conversationID: conversationA)
        #expect(renderCache.protectedKeyCountForTesting(conversationID: conversationA) == 1)

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let pool = HotScenePool(capacity: 1)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            messageRenderRuntime: runtime
        )

        controller.update(container: container, theme: container.settings.theme)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB)
        controller.update(container: container, theme: container.settings.theme)

        #expect(renderCache.protectedKeyCountForTesting(conversationID: conversationA) == 0)
    }

    @Test("Evicting a scene does not interrupt background streaming")
    func evictionDoesNotInterruptStreaming() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        var registry = ProviderRegistry()
        registry.register(
            MockProvider(
                id: "mock",
                streamBehavior: MockStreamBehavior(
                    chunks: ["A", "B", "C"],
                    delayPerChunk: .milliseconds(80)
                )
            )
        )

        let pool = HotScenePool(capacity: 1)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator
        )
        container.resetConversation()
        let conversationA = try #require(container.activeConversationId)

        controller.update(container: container, theme: container.settings.theme)
        #expect(pool.sceneFor(conversationID: conversationA) != nil)

        container.sendDraft("start")

        // Wait until A is running.
        let startDeadline = ContinuousClock.now + .seconds(2)
        while !container.runningConversationIds.contains(conversationA), ContinuousClock.now < startDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(container.runningConversationIds.contains(conversationA))

        // Switch to a new conversation to evict A's scene while its request is still streaming.
        container.resetConversation()
        let conversationB = try #require(container.activeConversationId)
        controller.update(container: container, theme: container.settings.theme)

        #expect(conversationB != conversationA)
        #expect(pool.sceneFor(conversationID: conversationA) == nil)

        let doneDeadline = ContinuousClock.now + .seconds(3)
        while container.runningConversationIds.contains(conversationA), ContinuousClock.now < doneDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!container.runningConversationIds.contains(conversationA))

        let messagesA = container.messagesForConversation(conversationA)
        let assistant = messagesA.last(where: { $0.role == .assistant })?.content ?? ""
        #expect(assistant.contains("A"))
    }

    @Test("Switching away mid-stream keeps streaming and shows latest content when switching back")
    func backgroundStreamingSwitchBackShowsLatest() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        var registry = ProviderRegistry()
        registry.register(
            MockProvider(
                id: "mock",
                streamBehavior: MockStreamBehavior(
                    chunks: ["A", "B", "C"],
                    delayPerChunk: .milliseconds(60)
                )
            )
        )

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator
        )
        container.resetConversation()
        let conversationA = try #require(container.activeConversationId)

        controller.update(container: container, theme: container.settings.theme)
        let sceneA = try #require(pool.sceneFor(conversationID: conversationA))
        let applyCountA = sceneA.applyCountForTesting

        container.sendDraft("start")

        // Wait until A is running.
        let startDeadline = ContinuousClock.now + .seconds(2)
        while !container.runningConversationIds.contains(conversationA), ContinuousClock.now < startDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(container.runningConversationIds.contains(conversationA))

        // Switch to B without evicting A.
        container.resetConversation()
        let conversationB = try #require(container.activeConversationId)
        controller.update(container: container, theme: container.settings.theme)

        #expect(conversationB != conversationA)
        #expect(pool.sceneFor(conversationID: conversationA) != nil)
        #expect(pool.sceneFor(conversationID: conversationB) != nil)

        // A should be hidden while B is active.
        let sceneAHidden = try #require(pool.sceneFor(conversationID: conversationA))
        #expect(sceneAHidden.view.isHidden)

        // While hidden, streaming deltas should mark A dirty.
        let dirtyDeadline = ContinuousClock.now + .seconds(2)
        while !sceneAHidden.needsReload, ContinuousClock.now < dirtyDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(sceneAHidden.needsReload)

        // Wait for A streaming to complete.
        let doneDeadline = ContinuousClock.now + .seconds(3)
        while container.runningConversationIds.contains(conversationA), ContinuousClock.now < doneDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!container.runningConversationIds.contains(conversationA))

        // Switch back to A and ensure we apply latest state once.
        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA)
        controller.update(container: container, theme: container.settings.theme)

        let sceneAAfter = try #require(pool.sceneFor(conversationID: conversationA))
        #expect(!sceneAAfter.needsReload)
        #expect(sceneAAfter.applyCountForTesting == applyCountA + 1)

        let messagesA = container.messagesForConversation(conversationA)
        let assistant = messagesA.last(where: { $0.role == .assistant })?.content ?? ""
        #expect(assistant.contains("C"))
    }

    @Test("Scroll position is preserved across hot scene switches")
    func scrollPositionPreservedAcrossSwitches() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()

        for index in 0 ..< 80 {
            try coordinator.persistSystemMessage(
                ChatMessage(role: .assistant, content: "A message \(index) \(String(repeating: "x", count: 120))"),
                conversationId: conversationA,
                status: .completed
            )
            try coordinator.persistSystemMessage(
                ChatMessage(role: .assistant, content: "B message \(index) \(String(repeating: "y", count: 120))"),
                conversationId: conversationB,
                status: .completed
            )
        }

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let pool = HotScenePool(capacity: 2)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.display()
        window.contentView?.layoutSubtreeIfNeeded()
        defer {
            window.contentViewController = nil
            window.orderOut(nil)
            withExtendedLifetime(window) {}
        }

        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA
        )

        controller.update(container: container, theme: container.settings.theme)
        try await waitForConversationReady(container, conversationId: conversationA, timeout: .seconds(5))
        controller.view.layoutSubtreeIfNeeded()

        let sceneA = try #require(pool.sceneFor(conversationID: conversationA))
        sceneA.messageTableViewForTesting.setScrollOriginYForTesting(1500)
        let before = sceneA.messageTableViewForTesting.scrollOriginYForTesting
        #expect(before > 0)

        container.activateConversation(conversationId: conversationB)
        try await waitForConversationReady(container, conversationId: conversationB, timeout: .seconds(5))
        controller.update(container: container, theme: container.settings.theme)
        controller.view.layoutSubtreeIfNeeded()

        container.activateConversation(conversationId: conversationA)
        try await waitForConversationReady(container, conversationId: conversationA, timeout: .seconds(5))
        controller.update(container: container, theme: container.settings.theme)
        controller.view.layoutSubtreeIfNeeded()

        let sceneAAfter = try #require(pool.sceneFor(conversationID: conversationA))
        let after = sceneAAfter.messageTableViewForTesting.scrollOriginYForTesting
        #expect(abs(after - before) <= 1.0)
    }

    @Test("Four-conversation loop avoids cache-miss-reload (no plain→rich flash)")
    // swiftlint:disable:next function_body_length
    func fourConversationLoopAvoidsCacheMissReload() async throws {
        let db = try DatabaseManager.inMemory()
        let coordinator = ChatPersistenceCoordinator(dbManager: db)

        let conversationA = try coordinator.createNewConversation()
        let conversationB = try coordinator.createNewConversation()
        let conversationC = try coordinator.createNewConversation()
        let conversationD = try coordinator.createNewConversation()

        func seed(_ conversationId: String, prefix: String) throws {
            for index in 1 ... 6 {
                let content = """
                # \(prefix)\(index)

                Inline math: $E=mc^2$

                | a | b | c |
                |---|---|---|
                | 1 | 2 | 3 |
                | 4 | 5 | 6 |
                """
                try coordinator.persistSystemMessage(
                    ChatMessage(role: .assistant, content: content),
                    conversationId: conversationId,
                    status: .completed
                )
            }
        }

        try seed(conversationA, prefix: "A")
        try seed(conversationB, prefix: "B")
        try seed(conversationC, prefix: "C")
        try seed(conversationD, prefix: "D")

        var registry = ProviderRegistry()
        registry.register(MockProvider(id: "mock"))

        let pool = HotScenePool(capacity: 3)
        let controller = HotScenePoolController(pool: pool)
        controller.loadViewIfNeeded()
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2,
                height: 640
            ),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.display()
        window.contentView?.layoutSubtreeIfNeeded()
        defer {
            window.contentViewController = nil
            window.orderOut(nil)
            withExtendedLifetime(window) {}
        }

        let now = Date.now
        let container = AppContainer.forTesting(
            settings: .testDefault,
            registry: registry,
            persistence: coordinator,
            activeConversationId: conversationA,
            sidebarThreads: [
                ConversationSidebarThread(id: conversationA, title: "A", lastActivityAt: now),
                ConversationSidebarThread(id: conversationB, title: "B", lastActivityAt: now),
                ConversationSidebarThread(id: conversationC, title: "C", lastActivityAt: now),
                ConversationSidebarThread(id: conversationD, title: "D", lastActivityAt: now)
            ]
        )

        // Ensure the active conversation is fully loaded so snapshot caching is non-empty and deterministic.
        container.retryActiveConversationLoad()
        try await waitForConversationReady(container, conversationId: conversationA, timeout: .seconds(5))

        // Prewarm non-active conversations via the existing startup prewarm path.
        await container.runStartupPrewarmForTesting()

        // Also prewarm the active conversation so cold-miss recreation can stay cache-hit.
        let style = RenderStyle.fromTheme()
        let assistantsA = container.messages
            .filter { $0.role == .assistant }
            .suffix(RenderConstants.startupRenderPrewarmAssistantMessageCap)
        let inputsA = assistantsA.map {
            MessageRenderInput(
                content: $0.content,
                availableWidth: HushSpacing.chatContentMaxWidth,
                style: style,
                isStreaming: false
            )
        }
        await container.messageRenderRuntime.prewarm(inputs: inputsA, protectFor: conversationA)

        controller.update(container: container, theme: container.settings.theme)
        try await waitForConversationReady(container, conversationId: conversationA)

        let recorder = PerfTrace.TestRecorder()
        try await PerfTrace.$testRecorder.withValue(recorder) {
            // A → B → C → A includes at least one hot-hit switch.
            container.activateConversation(conversationId: conversationB)
            try await waitForConversationReady(container, conversationId: conversationB, timeout: .seconds(5))
            controller.update(container: container, theme: container.settings.theme)
            controller.view.layoutSubtreeIfNeeded()

            container.activateConversation(conversationId: conversationC)
            try await waitForConversationReady(container, conversationId: conversationC, timeout: .seconds(5))
            controller.update(container: container, theme: container.settings.theme)
            controller.view.layoutSubtreeIfNeeded()

            container.activateConversation(conversationId: conversationA)
            try await waitForConversationReady(container, conversationId: conversationA, timeout: .seconds(5))
            controller.update(container: container, theme: container.settings.theme)
            controller.view.layoutSubtreeIfNeeded()

            // Introduce D to force at least one cold-miss recreation path.
            container.activateConversation(conversationId: conversationD)
            try await waitForConversationReady(container, conversationId: conversationD, timeout: .seconds(5))
            controller.update(container: container, theme: container.settings.theme)
            controller.view.layoutSubtreeIfNeeded()

            // Switch to a still-pooled conversation to hit the visibility-toggle path again.
            container.activateConversation(conversationId: conversationC)
            try await waitForConversationReady(container, conversationId: conversationC, timeout: .seconds(5))
            controller.update(container: container, theme: container.settings.theme)
            controller.view.layoutSubtreeIfNeeded()

            // Recreate an evicted conversation and ensure it's cache-hit on reload.
            container.activateConversation(conversationId: conversationB)
            try await waitForConversationReady(container, conversationId: conversationB, timeout: .seconds(5))
            controller.update(container: container, theme: container.settings.theme)
            controller.view.layoutSubtreeIfNeeded()
        }

        let switchRecords = recorder.snapshot()
            .filter { $0.event == PerfTrace.Event.switchPresentedRendered && $0.type == "duration_ms" }
        let switchModes = switchRecords.compactMap { $0.fields["mode"] }
        let summary = switchRecords.map { record in
            let conversation = record.fields["conversation"] ?? "?"
            let mode = record.fields["mode"] ?? "?"
            let contentWidth = record.fields["content_width"] ?? "?"
            let hits = record.fields["hits"] ?? "?"
            let misses = record.fields["misses"] ?? "?"
            return "\(conversation):\(mode) width=\(contentWidth) hits=\(hits) misses=\(misses)"
        }

        #expect(!switchModes.isEmpty, "No switch.presentedRendered records captured. records=\(summary)")
        #expect(!switchModes.contains("cache-miss-reload"), "Unexpected cache-miss-reload. records=\(summary)")
        #expect(switchModes.contains("hot-scene"), "Expected at least one hot-scene. records=\(summary)")
        #expect(switchModes.contains("cache-hit-reload"), "Expected at least one cache-hit-reload. records=\(summary)")
    }
}
