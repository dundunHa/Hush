import Foundation

/// Shared runtime container for message rendering resources.
///
/// Reuses a single renderer instance so render caches survive
/// per-message view/controller lifecycles.
@MainActor
final class MessageRenderRuntime {
    static let shared = MessageRenderRuntime()

    private let renderer: MessageContentRenderer
    private let scheduler: ConversationRenderScheduler

    init(renderer: MessageContentRenderer, scheduler: ConversationRenderScheduler) {
        self.renderer = renderer
        self.scheduler = scheduler
    }

    init() {
        renderer = MessageContentRenderer()
        scheduler = ConversationRenderScheduler()
    }

    func makeRenderController(coalesceInterval: TimeInterval? = nil) -> RenderController {
        RenderController(
            renderer: renderer,
            scheduler: scheduler,
            coalesceInterval: coalesceInterval
        )
    }

    func cachedOutput(for input: MessageRenderInput) -> MessageRenderOutput? {
        renderer.cachedOutput(for: input)
    }

    func peekCachedOutput(for input: MessageRenderInput) -> MessageRenderOutput? {
        renderer.peekCachedOutput(for: input)
    }

    func cachedRowHeight(for input: MessageRenderInput) -> CGFloat? {
        renderer.cachedRowHeight(for: input)
    }

    func prewarm(inputs: [MessageRenderInput]) async {
        await renderer.prewarm(inputs: inputs)
    }

    func prewarm(
        inputs: [MessageRenderInput],
        protectFor conversationID: String?
    ) async {
        await renderer.prewarm(inputs: inputs)
        guard let conversationID else { return }
        renderer.protectCacheEntries(for: inputs, conversationID: conversationID)
    }

    func clearProtection(conversationID: String) {
        renderer.clearProtection(conversationID: conversationID)
    }

    func clearAllProtections() {
        renderer.clearAllProtections()
    }

    func setActiveConversation(
        conversationID: String?,
        generation: UInt64
    ) {
        scheduler.setActiveConversation(
            conversationID: conversationID,
            generation: generation
        )
    }

    func setSceneConfiguration(
        active: (String, UInt64),
        hot: [(String, UInt64)]
    ) {
        scheduler.setSceneConfiguration(active: active, hot: hot)
    }

    func setLiveScrolling(_ value: Bool) {
        scheduler.setLiveScrolling(value)
    }

    func clearCaches() {
        renderer.clearCaches()
    }
}
