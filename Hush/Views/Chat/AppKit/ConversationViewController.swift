import AppKit

@MainActor
final class ConversationViewController: NSViewController {
    private var container: AppContainer
    private let messageTableView = MessageTableView()
    private var lastLayoutReadyGeneration: UInt64?
    var needsReload: Bool = false
    #if DEBUG
        private(set) var applyCountForTesting: Int = 0
        private(set) var streamingPushCountForTesting: Int = 0
        private(set) var lastStreamingPushMessageIDForTesting: UUID?
        private(set) var lastStreamingPushContentForTesting: String?
    #endif

    init(container: AppContainer) {
        self.container = container
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

        rootView.addSubview(messageTableView)
        messageTableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            messageTableView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            messageTableView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            messageTableView.topAnchor.constraint(equalTo: rootView.topAnchor),
            messageTableView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        view = rootView
        renderConversationState()
    }

    func update(container: AppContainer) {
        self.container = container
        renderConversationState()
    }

    func applyConversationState(
        conversationId: String?,
        messages: [ChatMessage],
        isSending: Bool,
        generation: UInt64,
        container: AppContainer
    ) {
        needsReload = false
        #if DEBUG
            applyCountForTesting += 1
        #endif
        messageTableView.apply(
            messages: messages,
            activeConversationID: conversationId,
            isActiveConversationSending: isSending,
            switchGeneration: generation,
            runtime: container.messageRenderRuntime,
            container: container
        )

        guard conversationId == container.activeConversationId else { return }
        guard lastLayoutReadyGeneration != generation else { return }
        lastLayoutReadyGeneration = generation
        DispatchQueue.main.async { [weak self] in
            self?.container.markConversationSwitchLayoutReady()
        }
    }

    func cancelVisibleRenderWorkForEviction() {
        messageTableView.cancelVisibleRenderWorkForEviction()
    }

    func pushStreamingContent(messageID: UUID, content: String) {
        #if DEBUG
            streamingPushCountForTesting += 1
            lastStreamingPushMessageIDForTesting = messageID
            lastStreamingPushContentForTesting = content
        #endif
        messageTableView.updateStreamingCell(messageID: messageID, content: content)
    }

    private func renderConversationState() {
        applyConversationState(
            conversationId: container.activeConversationId,
            messages: container.messages,
            isSending: container.isActiveConversationSending,
            generation: container.activeConversationRenderGeneration,
            container: container
        )
    }
}

#if DEBUG
    extension ConversationViewController {
        var messageTableViewForTesting: MessageTableView {
            messageTableView
        }
    }
#endif
