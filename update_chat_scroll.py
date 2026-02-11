import re

with open('Hush/Views/Chat/ChatScrollStage.swift', 'r') as f:
    content = f.read()

# 1. Replace states
old_states = """
    @State private var messageFrames: [UUID: CGRect] = [:]
    @State private var viewportFrame: CGRect = .zero
    @State private var visibleMessageIDs: Set<UUID> = []
    @State private var pendingScrollTask: Task<Void, Never>?
    @State private var pendingVisibilityRecompute: Task<Void, Never>?
    @State private var pendingSwitchScrollWhenMessagesAppear = false
    @State private var lastStreamingScrollTime: Date = .distantPast
    @State private var rankByID: [UUID: Int] = [:]
    @State private var activeMessageIDs: Set<UUID> = []
"""

new_states = """
    @State private var pendingScrollTask: Task<Void, Never>?
    @State private var pendingSwitchScrollWhenMessagesAppear = false
    @State private var lastStreamingScrollTime: Date = .distantPast
    @State private var rankByID: [UUID: Int] = [:]

    // Windowing State
    @State private var topVisibleMessageID: UUID?
    @State private var previousWindowRange: Range<Int>?
    @State private var previousMessageCount: Int?
"""

content = content.replace(old_states.strip(), new_states.strip())

# 2. Replace body layout
old_body = """
    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: HushSpacing.lg) {
                        LazyVStack(alignment: .leading, spacing: HushSpacing.lg) {
                            topPaginationSection(proxy: proxy)

                            let messages = container.messages
                            let cachedRanks = rankByID

                            ForEach(messages, id: \\.id) { message in
                                MessageBubble(
                                    message: message,
                                    isStreaming: isStreamingMessage(message),
                                    runtime: container.messageRenderRuntime,
                                    renderHint: renderHint(for: message, rankByID: cachedRanks)
                                )
                                .equatable()
                                .id(message.id)
                                .background(messageFrameTracker(for: message))
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                            }

                            if container.isActiveConversationSending {
                                loadingIndicator
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
"""

new_body = """
    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: HushSpacing.lg) {
                        LazyVStack(alignment: .leading, spacing: HushSpacing.lg) {
                            topPaginationSection(proxy: proxy)

                            let messages = container.messages
                            let cachedRanks = rankByID
                            let windowOutput = computeWindow(for: messages)

                            ForEach(windowOutput.windowRange, id: \\.self) { index in
                                let message = messages[index]
                                MessageBubble(
                                    message: message,
                                    isStreaming: isStreamingMessage(message),
                                    runtime: container.messageRenderRuntime,
                                    renderHint: renderHint(for: message, rankByID: cachedRanks, isVisible: true)
                                )
                                .equatable()
                                .id(message.id)
                                .onAppear {
                                    if topVisibleMessageID == nil || (messages.firstIndex(where: { $0.id == topVisibleMessageID }) ?? Int.max) > index {
                                        topVisibleMessageID = message.id
                                    }
                                }
                                .onDisappear {
                                    if topVisibleMessageID == message.id {
                                        let window = windowOutput.windowRange
                                        let nextIndex = index + 1
                                        if window.contains(nextIndex) {
                                            topVisibleMessageID = messages[nextIndex].id
                                        } else if window.contains(index - 1) {
                                            topVisibleMessageID = messages[index - 1].id
                                        } else {
                                            topVisibleMessageID = nil
                                        }
                                    }
                                }
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                            }

                            if container.isActiveConversationSending {
                                loadingIndicator
                                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
"""

content = content.replace(old_body.strip(), new_body.strip())

# 3. Add computeWindow
add_computeWindow = """
    private func computeWindow(for messages: [ChatMessage]) -> ChatWindowingOutput {
        PerfTrace.measure("visible.recompute.count")
        
        let anchorIndex = topVisibleMessageID.flatMap { id in
            messages.firstIndex(where: { $0.id == id })
        }
        
        let input = ChatWindowingInput(
            messageCount: messages.count,
            tailCount: max(16, RenderConstants.switchPriorityRenderCount),
            bufferSize: RuntimeConstants.conversationMessagePageSize,
            anchorIndex: anchorIndex,
            previousAnchorIndex: nil,
            previousMessageCount: previousMessageCount,
            previousWindowRange: previousWindowRange,
            isPinned: !userHasScrolledUp,
            isStreaming: container.isActiveConversationSending
        )
        
        let output = ChatWindowing.computeWindow(input)
        
        Task { @MainActor in
            if self.previousWindowRange != output.windowRange {
                self.previousWindowRange = output.windowRange
            }
            if self.previousMessageCount != messages.count {
                self.previousMessageCount = messages.count
            }
        }
        
        return output
    }
"""

content = content.replace("enum CountChangeAutoScrollAction: Equatable {", add_computeWindow + "\n    enum CountChangeAutoScrollAction: Equatable {")

# 4. Remove messageFrameTracker and visibility recompute stuff
pattern = re.compile(r"    @ViewBuilder\n    private func messageFrameTracker.*?Set\(visible\)\n    }\n", re.DOTALL)
content = pattern.sub("", content)

# 5. Fix resetForConversationSwitch
old_reset = """
        userHasScrolledUp = false
        lastKnownFirstMessageID = container.messages.first?.id
        lastStreamingScrollTime = .distantPast
        visibleMessageIDs = []
        messageFrames = [:]
        activeMessageIDs = Set(container.messages.map(\\.id))
        pendingSwitchScrollWhenMessagesAppear = container.messages.isEmpty
        rankByID = makeRankByMessageID(container.messages)
"""
new_reset = """
        userHasScrolledUp = false
        lastKnownFirstMessageID = container.messages.first?.id
        lastStreamingScrollTime = .distantPast
        pendingSwitchScrollWhenMessagesAppear = container.messages.isEmpty
        rankByID = makeRankByMessageID(container.messages)
        
        topVisibleMessageID = nil
        previousWindowRange = nil
        previousMessageCount = nil
"""
content = content.replace(old_reset.strip(), new_reset.strip())

content = content.replace("pendingVisibilityRecompute?.cancel()\n        pendingVisibilityRecompute = nil", "")

# 6. Fix handleMessagesChanged
content = content.replace("\n        activeMessageIDs = Set(container.messages.map(\\.id))", "")

# 7. Fix renderHint
content = content.replace("private func renderHint(for message: ChatMessage, rankByID: [UUID: Int]) -> MessageRenderHint {", "private func renderHint(for message: ChatMessage, rankByID: [UUID: Int], isVisible: Bool) -> MessageRenderHint {")
content = content.replace("isVisible: visibleMessageIDs.contains(message.id),", "isVisible: isVisible,")

# 8. Clean up prefs
prefs_pattern = re.compile(r"                \.onPreferenceChange\(MessageFramePreferenceKey\.self\) \{.*?\}\n                \.onPreferenceChange\(ViewportFramePreferenceKey\.self\) \{.*?\}\n", re.DOTALL)
content = prefs_pattern.sub("", content)

# 9. Clean up disappear
disappear_pattern = re.compile(r"                \.onDisappear \{\n                    pendingScrollTask\?\.cancel\(\)\n                    pendingScrollTask = nil\n                    pendingVisibilityRecompute\?\.cancel\(\)\n                    pendingVisibilityRecompute = nil\n                \}", re.DOTALL)
content = disappear_pattern.sub("""                .onDisappear {\n                    pendingScrollTask?.cancel()\n                    pendingScrollTask = nil\n                }""", content)

# 10. Clean up preference keys at bottom
keys_pattern = re.compile(r"private struct MessageFramePreferenceKey: PreferenceKey \{.*?\}\n\nprivate struct ViewportFramePreferenceKey: PreferenceKey \{.*?\}\n", re.DOTALL)
content = keys_pattern.sub("", content)

with open('Hush/Views/Chat/ChatScrollStage.swift', 'w') as f:
    f.write(content)
