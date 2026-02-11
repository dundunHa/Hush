import AppKit
import Combine
import os

/// Per-message render controller that coalesces streaming updates.
///
/// During streaming, the controller throttles render calls to avoid
/// main-thread churn. Stale renders are cancelled.
@MainActor
final class RenderController: ObservableObject {
    private struct RequestFingerprint: Equatable {
        let contentHash: Int
        let width: Int
        let styleKey: Int
        let isStreaming: Bool

        var schedulerHash: Int {
            var hasher = Hasher()
            hasher.combine(contentHash)
            hasher.combine(width)
            hasher.combine(styleKey)
            hasher.combine(isStreaming)
            return hasher.finalize()
        }
    }

    // MARK: - Published

    @Published private(set) var currentOutput: MessageRenderOutput?

    // MARK: - Dependencies

    private let renderer: MessageContentRenderer
    private let scheduler: ConversationRenderScheduler
    private let coalesceInterval: TimeInterval

    // MARK: - State

    private var pendingStreamingContent: String?
    private var pendingStreamingTask: Task<Void, Never>?
    private var lastRenderTime: Date = .distantPast
    private var lastRequestedFingerprint: RequestFingerprint?
    private var lastRequestedHint: MessageRenderHint?
    private var lastAppliedFingerprint: RequestFingerprint?
    private var lastQueuedPriority: ConversationRenderScheduler.RenderWorkPriority?
    private let anonymousMessageID = UUID()
    private let anonymousConversationID = "__anonymous__"

    // MARK: - Debug

    private enum SwitchRenderDebug {
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

        static var isContentEnabled: Bool {
            #if DEBUG
                guard let raw = ProcessInfo.processInfo.environment["HUSH_CONTENT_DEBUG"]?
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

        private static let logger = Logger(subsystem: "com.hush.app", category: "SwitchRender")
        private static let chunkSize = 256

        static func log(_ message: String, content: String? = nil) {
            guard isEnabled else { return }
            logger.debug("\(message, privacy: .public)")
            guard isContentEnabled, let content else { return }
            var offset = content.startIndex
            var part = 1
            while offset < content.endIndex {
                let end = content.index(offset, offsetBy: chunkSize, limitedBy: content.endIndex) ?? content.endIndex
                let chunk = String(content[offset ..< end])
                logger.debug("[content \(part, privacy: .public)] \(chunk, privacy: .public)")
                offset = end
                part += 1
            }
        }
    }

    // MARK: - Init

    convenience init(
        renderer: MessageContentRenderer,
        coalesceInterval: TimeInterval? = nil
    ) {
        self.init(
            renderer: renderer,
            scheduler: ConversationRenderScheduler(),
            coalesceInterval: coalesceInterval
        )
    }

    init(
        renderer: MessageContentRenderer,
        scheduler: ConversationRenderScheduler,
        coalesceInterval: TimeInterval? = nil
    ) {
        self.renderer = renderer
        self.scheduler = scheduler
        self.coalesceInterval = coalesceInterval ?? RenderConstants.streamingCoalesceInterval
    }

    deinit {
        pendingStreamingTask?.cancel()
    }

    // MARK: - Public Interface

    /// Request a render of content at the given width.
    /// During streaming, calls are coalesced.
    func requestRender(
        content: String,
        availableWidth: CGFloat,
        style: RenderStyle,
        isStreaming: Bool,
        hint: MessageRenderHint? = nil
    ) {
        let fingerprint = makeFingerprint(
            content: content,
            availableWidth: availableWidth,
            style: style,
            isStreaming: isStreaming
        )
        let priority = isStreaming ? nil : resolvePriority(for: hint)

        guard !shouldSkipDuplicate(
            fingerprint: fingerprint,
            isStreaming: isStreaming,
            hint: hint,
            priority: priority
        )
        else {
            SwitchRenderDebug.log(
                "dedup-skip streaming=\(isStreaming) chars=\(content.count) width=\(Int(availableWidth.rounded(.down)))",
                content: content
            )
            return
        }

        lastRequestedFingerprint = fingerprint
        lastRequestedHint = hint
        lastQueuedPriority = priority

        if isStreaming {
            requestStreamingRender(
                content: content,
                availableWidth: availableWidth,
                style: style,
                fingerprint: fingerprint
            )
        } else {
            requestNonStreamingRender(
                input: MessageRenderInput(
                    content: content,
                    availableWidth: availableWidth,
                    style: style,
                    isStreaming: false
                ),
                fingerprint: fingerprint,
                hint: hint,
                priority: priority ?? .high
            )
        }
    }

    /// Cancel any pending render work.
    func cancel() {
        pendingStreamingTask?.cancel()
        pendingStreamingTask = nil
        pendingStreamingContent = nil
        lastRequestedFingerprint = nil
        lastRequestedHint = nil
        lastQueuedPriority = nil
    }

    // MARK: - Private

    private func shouldSkipDuplicate(
        fingerprint: RequestFingerprint,
        isStreaming: Bool,
        hint: MessageRenderHint?,
        priority: ConversationRenderScheduler.RenderWorkPriority?
    ) -> Bool {
        guard fingerprint == lastRequestedFingerprint else { return false }

        if isStreaming {
            return true
        }

        // If nothing is currently rendered, keep allowing retry requests.
        // This avoids getting stuck in plain fallback when queued work is
        // dropped as stale or replaced during fast conversation switches.
        guard currentOutput != nil else { return false }

        // If the currently applied output doesn't match the last requested
        // fingerprint, the previous enqueue was likely dropped as stale.
        // Allow retry so the message doesn't stay stuck on stale content.
        if lastAppliedFingerprint != lastRequestedFingerprint {
            return false
        }

        guard let priority else { return true }
        guard let lastPriority = lastQueuedPriority else { return true }
        guard let hint, let lastHint = lastRequestedHint else { return true }

        let sameScope =
            hint.conversationID == lastHint.conversationID
                && hint.messageID == lastHint.messageID
                && hint.switchGeneration == lastHint.switchGeneration

        guard sameScope else { return false }

        // Allow promotion (e.g. deferred -> visible/high) to replace queued work.
        return priority.rawValue >= lastPriority.rawValue
    }

    private func resolvePriority(
        for hint: MessageRenderHint?
    ) -> ConversationRenderScheduler.RenderWorkPriority {
        guard let hint else { return .high }

        if hint.rankFromLatest < RenderConstants.switchPriorityRenderCount {
            return .high
        }

        if hint.isVisible {
            return .visible
        }

        if hint.rankFromLatest == Int.max {
            return .deferred
        }

        return .idle
    }

    private func makeFingerprint(
        content: String,
        availableWidth: CGFloat,
        style: RenderStyle,
        isStreaming: Bool
    ) -> RequestFingerprint {
        RequestFingerprint(
            contentHash: content.hashValue,
            width: Int(availableWidth.rounded(.down)),
            styleKey: style.cacheKey,
            isStreaming: isStreaming
        )
    }

    private func requestNonStreamingRender(
        input: MessageRenderInput,
        fingerprint: RequestFingerprint,
        hint: MessageRenderHint?,
        priority: ConversationRenderScheduler.RenderWorkPriority
    ) {
        pendingStreamingTask?.cancel()
        pendingStreamingTask = nil
        pendingStreamingContent = nil

        let key = ConversationRenderScheduler.RenderWorkKey(
            conversationID: hint?.conversationID ?? anonymousConversationID,
            messageID: hint?.messageID ?? anonymousMessageID,
            fingerprint: fingerprint.schedulerHash,
            generation: hint?.switchGeneration ?? 0
        )

        if let cached = renderer.cachedOutput(for: input) {
            // Always apply cached output immediately — never clear currentOutput
            // to nil for cache hits. Clearing causes a visible flash to plain-text
            // fallback, and if the queued work gets pruned by a subsequent
            // conversation switch the message stays stuck on fallback forever.
            currentOutput = cached
            lastAppliedFingerprint = fingerprint
            lastQueuedPriority = nil
            SwitchRenderDebug.log(
                "cache-hit-immediate priority=\(priority.rawValue) chars=\(input.content.count) " +
                    "width=\(Int(input.availableWidth.rounded(.down)))",
                content: input.content
            )
            return
        }

        // Keep stale output visible while queued work is pending.
        // Clearing to nil here risks a permanent plain-text fallback if
        // the scheduler prunes or drops the work item before apply runs.

        SwitchRenderDebug.log(
            "enqueue priority=\(priority.rawValue) chars=\(input.content.count) width=\(Int(input.availableWidth.rounded(.down))) " +
                "visible=\(hint?.isVisible ?? false) rank=\(hint?.rankFromLatest ?? -1) generation=\(hint?.switchGeneration ?? 0)",
            content: input.content
        )

        scheduler.enqueue(
            key: key,
            priority: priority,
            input: input,
            render: { [renderer] input in
                renderer.render(input)
            },
            apply: { [weak self] output in
                guard let self else { return }
                guard self.shouldApplyQueuedOutput(
                    fingerprint: fingerprint,
                    hint: hint
                ) else { return }

                self.currentOutput = output
                self.lastAppliedFingerprint = fingerprint
                SwitchRenderDebug.log(
                    "apply priority=\(priority.rawValue) chars=\(input.content.count) width=\(Int(input.availableWidth.rounded(.down)))",
                    content: input.content
                )
            }
        )
    }

    private func shouldApplyQueuedOutput(
        fingerprint: RequestFingerprint,
        hint: MessageRenderHint?
    ) -> Bool {
        guard lastRequestedFingerprint == fingerprint else {
            SwitchRenderDebug.log("skip-apply reason=fingerprint-stale")
            return false
        }

        if let hint,
           let lastHint = lastRequestedHint,
           hint.conversationID != lastHint.conversationID
           || hint.messageID != lastHint.messageID
           || hint.switchGeneration != lastHint.switchGeneration
        {
            SwitchRenderDebug.log("skip-apply reason=generation-stale")
            return false
        }

        return true
    }

    private func requestStreamingRender(
        content: String,
        availableWidth: CGFloat,
        style: RenderStyle,
        fingerprint: RequestFingerprint
    ) {
        lastQueuedPriority = nil
        pendingStreamingContent = content

        // Cancel stale work
        pendingStreamingTask?.cancel()

        let elapsed = Date().timeIntervalSince(lastRenderTime)
        let delay = max(0, coalesceInterval - elapsed)

        pendingStreamingTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            guard !Task.isCancelled else { return }
            guard let self,
                  let content = self.pendingStreamingContent,
                  self.lastRequestedFingerprint == fingerprint
            else { return }

            let input = MessageRenderInput(
                content: content,
                availableWidth: availableWidth,
                style: style,
                isStreaming: true
            )
            let output = self.renderer.render(input)

            guard !Task.isCancelled else { return }
            guard self.lastRequestedFingerprint == fingerprint else { return }
            self.currentOutput = output
            self.lastAppliedFingerprint = fingerprint
            self.lastRenderTime = Date()
            self.pendingStreamingContent = nil
        }
    }
}

#if DEBUG
    extension RenderController {
        var lastRequestedIsStreamingForTesting: Bool? {
            lastRequestedFingerprint?.isStreaming
        }

        var lastRequestedHintForTesting: MessageRenderHint? {
            lastRequestedHint
        }

        var lastQueuedPriorityForTesting: ConversationRenderScheduler.RenderWorkPriority? {
            lastQueuedPriority
        }
    }
#endif
