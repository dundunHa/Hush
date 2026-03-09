import Foundation
import os

struct StreamingPresentationPolicy: Equatable {
    let revealTickInterval: Duration
    let initialRevealCharacters: Int
    let minimumCharactersPerSecond: Double
    let maximumCharactersPerSecond: Double
    let targetBacklogLagSeconds: Double
    let terminalCatchUpCharactersPerSecond: Double
    let terminalForceRevealAfter: Duration?

    nonisolated static let production = StreamingPresentationPolicy(
        revealTickInterval: .milliseconds(50),
        initialRevealCharacters: 1,
        minimumCharactersPerSecond: 20,
        maximumCharactersPerSecond: 40,
        targetBacklogLagSeconds: 2.0,
        terminalCatchUpCharactersPerSecond: 40,
        terminalForceRevealAfter: nil
    )

    nonisolated static let testingFast = StreamingPresentationPolicy(
        revealTickInterval: .milliseconds(10),
        initialRevealCharacters: 1,
        minimumCharactersPerSecond: 240,
        maximumCharactersPerSecond: 600,
        targetBacklogLagSeconds: 0.1,
        terminalCatchUpCharactersPerSecond: 600,
        terminalForceRevealAfter: nil
    )

    var fastestCharactersPerSecond: Double {
        max(maximumCharactersPerSecond, terminalCatchUpCharactersPerSecond)
    }

    func charactersPerSecond(
        forPendingCharacters pendingCharacters: Int,
        isTerminalCatchUp: Bool
    ) -> Double {
        guard pendingCharacters > 0 else { return 0 }
        if isTerminalCatchUp {
            return terminalCatchUpCharactersPerSecond
        }

        let targetLagSeconds = max(0.05, targetBacklogLagSeconds)
        let targetCharactersPerSecond = Double(pendingCharacters) / targetLagSeconds
        return min(
            maximumCharactersPerSecond,
            max(minimumCharactersPerSecond, targetCharactersPerSecond)
        )
    }
}

/// Configurable constants for the rendering pipeline.
nonisolated enum RenderConstants {
    /// Maximum number of math segments rendered per message.
    static let maxMathSegmentsPerMessage = 200

    /// Maximum content length (characters) for rich rendering;
    /// beyond this the remainder falls back to plain text.
    static let maxRichRenderLength = 50000

    /// Message render cache capacity (number of entries).
    static let messageCacheCapacity = 256

    /// Math render cache capacity (number of entries).
    static let mathCacheCapacity = 256

    /// Streaming coalesce interval in seconds.
    static let streamingCoalesceInterval: TimeInterval = 0.05 // 50ms

    /// Long non-streaming messages beyond this threshold use progressive rendering.
    static let progressiveRenderThresholdChars = 2000

    /// Number of non-active conversations to prewarm at startup.
    static let startupPrewarmConversationCount = 4

    /// Message page size used by startup prewarm.
    static let startupPrewarmMessageLimit = 17

    /// Number of assistant messages pre-rendered per prewarmed conversation.
    static let startupRenderPrewarmAssistantMessageCap = 8

    /// Number of latest assistant messages to prioritize on conversation switch.
    static let switchPriorityRenderCount = 3

    /// Maximum number of pooled live conversation scenes.
    static let hotScenePoolCapacity = 3

    /// Time budget interval between non-streaming render work items (seconds).
    static let nonStreamingRenderBudgetInterval: TimeInterval = 0.12

    /// Delay before idle/offscreen render work becomes eligible (seconds).
    static let offscreenIdleStartDelay: TimeInterval = 1.5

    /// Maximum queued non-streaming render work items.
    static let nonStreamingQueueCapacity = 64

    /// Fast-track interval between direct streaming UI pushes in RequestCoordinator.
    static let streamingFastFlushInterval: Duration = .milliseconds(30)

    /// Presentation-side typewriter tuning for streaming assistant content.
    static let streamingPresentationPolicy = StreamingPresentationPolicy.production

    /// Slow-track interval between streaming model updates in RequestCoordinator.
    static let streamingSlowFlushInterval: Duration = .milliseconds(200)

    /// Legacy interval between streaming UI array updates in RequestCoordinator.
    static let streamingUIFlushInterval: Duration = .milliseconds(100)

    /// Debounce interval for recomputing visible messages from PreferenceKey changes.
    static let visibleMessageRecomputeDebounce: Duration = .milliseconds(150)

    /// Minimum interval between streaming scroll-to-bottom requests (seconds).
    static let streamingScrollCoalesceInterval: TimeInterval = 0.1

    /// Fallback timeout after live-scroll start if no matching end notification arrives.
    static let liveScrollFallbackTimeout: TimeInterval = 3.0

    /// Debounce delay before issuing lookahead prewarm after scroll end.
    static let scrollEndPrewarmDebounce: TimeInterval = 0.2

    // MARK: - Table Attachment Guardrails

    /// Maximum number of tables rendered as attachments per message.
    static let maxTableAttachmentsPerMessage = 3

    /// Maximum row count for a single table to qualify for attachment rendering.
    static let maxTableRows = 80

    /// Maximum column count for a single table to qualify for attachment rendering.
    static let maxTableColumns = 20

    /// Maximum total cell count for a single table to qualify for attachment rendering.
    static let maxTableCells = 1200

    /// Maximum rendered character count (Phase 1 string) for attachment rendering.
    static let maxTableRenderedChars = 20000

    // MARK: - Idle Prewarm

    /// Delay (seconds) of idle time before triggering conversation prewarm.
    static let idlePrewarmDelay: TimeInterval = 2.0
}

/// Debug-only logger for Markdown/LaTeX rendering internals.
nonisolated enum RenderDebug {
    static var isEnabled: Bool {
        #if DEBUG
            guard let raw = ProcessInfo.processInfo.environment["HUSH_RENDER_DEBUG"]?
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

    static func log(_ message: String) {
        guard isEnabled else { return }
        let renderLogger = Logger(subsystem: "com.hush.app", category: "Rendering")
        renderLogger.debug("\(message, privacy: .public)")
        #if DEBUG
            print("[RenderDebug] \(message)")
        #endif
    }

    static func preview(_ text: String, limit: Int = 240) -> String {
        // Prefer a visible glyph over backslash escapes since OSLog may render
        // "\" as octal sequences (e.g. "\134"), which is confusing in log streams.
        let normalized = text.replacingOccurrences(of: "\n", with: "⏎")
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "..."
    }
}
