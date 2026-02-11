import AppKit

@MainActor
final class HotScenePoolController: NSViewController {
    private weak var container: AppContainer?
    private let pool: HotScenePool
    private var lastActiveConversationID: String?

    // MARK: - Diff State (avoids redundant apply when only unrelated @Published fields change)

    private var lastForwardedMessageCount: Int?
    private var lastForwardedLastMessageContentHash: Int?
    private var lastForwardedLastMessageID: UUID?
    private var lastForwardedLastMessageRole: ChatRole?
    private var lastForwardedIsSending: Bool?
    private var lastForwardedGeneration: UInt64?

    private var lastKnownContentWidth: Int?
    private var resizeDebounceTask: Task<Void, Never>?

    convenience init() {
        self.init(pool: HotScenePool())
    }

    init(pool: HotScenePool) {
        self.pool = pool
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.clear.cgColor
        rootView.layer?.masksToBounds = true
        rootView.autoresizingMask = [.width, .height]
        view = rootView
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        let rawWidth = view.bounds.width
        guard rawWidth > 0 else { return }

        let clampedWidth = min(rawWidth, HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2)
        let contentWidth = max(1, clampedWidth - HushSpacing.xl * 2)
        let quantized = Int(contentWidth)

        if lastKnownContentWidth == nil {
            lastKnownContentWidth = quantized
            return
        }
        guard lastKnownContentWidth != quantized else { return }
        lastKnownContentWidth = quantized

        scheduleResizeCleanup(expectedContentWidth: quantized)
    }

    func update(container: AppContainer) {
        self.container = container
        container.registerHotScenePool(pool)

        guard let activeConversationID = container.activeConversationId else { return }

        if lastActiveConversationID != activeConversationID {
            switchToActiveConversation(container: container)
            lastActiveConversationID = activeConversationID
        } else {
            forwardUpdateToActiveScene(container: container)
        }
    }

    func switchToActiveConversation(container: AppContainer) {
        guard let activeConversationID = container.activeConversationId else { return }
        let messages = container.messages
        let generation = container.activeConversationRenderGeneration
        let isSending = container.runningConversationIds.contains(activeConversationID)

        lastForwardedMessageCount = messages.count
        lastForwardedLastMessageContentHash = messages.last?.content.hashValue
        lastForwardedLastMessageID = messages.last?.id
        lastForwardedLastMessageRole = messages.last?.role
        lastForwardedIsSending = isSending
        lastForwardedGeneration = generation

        let previousConversationID = lastActiveConversationID
        let result = pool.switchTo(
            conversationID: activeConversationID,
            messageCount: messages.count,
            generation: generation,
            makeScene: { ConversationViewController(container: container) }
        )
        let isHotHitWithoutReload = !result.didCreate && !result.scene.needsReload

        if let evicted = result.evicted {
            evictScene(conversationID: evicted.conversationID, scene: evicted.scene, container: container)
        }

        if result.didCreate {
            attachSceneIfNeeded(result.scene)
            result.scene.applyConversationState(
                conversationId: activeConversationID,
                messages: messages,
                isSending: isSending,
                generation: generation,
                container: container
            )
        } else if result.scene.needsReload {
            result.scene.needsReload = false
            result.scene.applyConversationState(
                conversationId: activeConversationID,
                messages: messages,
                isSending: isSending,
                generation: generation,
                container: container
            )
        }

        if let previousConversationID,
           previousConversationID != activeConversationID,
           let previousScene = pool.sceneFor(conversationID: previousConversationID)
        {
            previousScene.view.isHidden = true
        }

        result.scene.view.isHidden = false

        if isHotHitWithoutReload {
            container.reportHotSceneSwitchPresentedRenderedIfNeeded(
                conversationId: activeConversationID,
                generation: generation
            )
        }

        container.messageRenderRuntime.setSceneConfiguration(
            active: (activeConversationID, generation),
            hot: pool.hotConversationGenerations()
        )
    }

    // MARK: - Private

    private func forwardUpdateToActiveScene(container: AppContainer) {
        guard let activeConversationID = container.activeConversationId else { return }
        guard let scene = pool.sceneFor(conversationID: activeConversationID) else {
            switchToActiveConversation(container: container)
            return
        }

        let messages = container.messages
        let generation = container.activeConversationRenderGeneration
        let isSending = container.runningConversationIds.contains(activeConversationID)

        let messageCount = messages.count
        let lastMessage = messages.last
        let lastContentHash = lastMessage?.content.hashValue
        let lastMessageID = lastMessage?.id
        let lastMessageRole = lastMessage?.role

        let isStreamingDeltaOnlyUpdate =
            isSending
                && messageCount == lastForwardedMessageCount
                && generation == lastForwardedGeneration
                && lastMessageRole == .assistant
                && lastForwardedLastMessageRole == .assistant
                && lastMessageID != nil
                && lastMessageID == lastForwardedLastMessageID
                && lastContentHash != lastForwardedLastMessageContentHash

        if messageCount == lastForwardedMessageCount,
           lastContentHash == lastForwardedLastMessageContentHash,
           isSending == lastForwardedIsSending,
           generation == lastForwardedGeneration
        {
            return
        }

        lastForwardedMessageCount = messageCount
        lastForwardedLastMessageContentHash = lastContentHash
        lastForwardedLastMessageID = lastMessageID
        lastForwardedLastMessageRole = lastMessageRole
        lastForwardedIsSending = isSending
        lastForwardedGeneration = generation

        pool.switchTo(
            conversationID: activeConversationID,
            messageCount: messageCount,
            generation: generation,
            makeScene: { scene }
        )

        if isStreamingDeltaOnlyUpdate,
           let lastMessage,
           let lastMessageID
        {
            scene.pushStreamingContent(messageID: lastMessageID, content: lastMessage.content)
            container.messageRenderRuntime.setSceneConfiguration(
                active: (activeConversationID, generation),
                hot: pool.hotConversationGenerations()
            )
            return
        }

        scene.applyConversationState(
            conversationId: activeConversationID,
            messages: messages,
            isSending: isSending,
            generation: generation,
            container: container
        )

        container.messageRenderRuntime.setSceneConfiguration(
            active: (activeConversationID, generation),
            hot: pool.hotConversationGenerations()
        )
    }

    private func attachSceneIfNeeded(_ scene: ConversationViewController) {
        guard scene.parent == nil else { return }

        addChild(scene)
        view.addSubview(scene.view)
        scene.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scene.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scene.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scene.view.topAnchor.constraint(equalTo: view.topAnchor),
            scene.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Newly attached scenes start hidden until switched to.
        scene.view.isHidden = true

        // Ensure newly attached scenes pick up a non-zero layout before their first apply.
        scene.view.frame = view.bounds
        view.layoutSubtreeIfNeeded()
        scene.view.layoutSubtreeIfNeeded()
    }

    private func evictScene(
        conversationID: String,
        scene: ConversationViewController,
        container: AppContainer
    ) {
        scene.cancelVisibleRenderWorkForEviction()
        container.messageRenderRuntime.clearProtection(conversationID: conversationID)
        container.requestCoordinator.cancelThrottleTasksForConversation(conversationID)
        scene.view.removeFromSuperview()
        scene.removeFromParent()
    }

    private func scheduleResizeCleanup(expectedContentWidth: Int) {
        resizeDebounceTask?.cancel()
        resizeDebounceTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }

            let current = Int(max(1, min(self.view.bounds.width, HushSpacing.chatContentMaxWidth + HushSpacing.xl * 2) - HushSpacing.xl * 2))
            guard current == expectedContentWidth else { return }
            guard let container = self.container else { return }

            await container.performResizeCacheCleanup(
                contentWidth: CGFloat(current),
                hotConversationIDs: self.pool.hotConversationIDs
            )
        }
    }
}
