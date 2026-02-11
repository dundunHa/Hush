import Foundation

/// Centralized default runtime constants for the Hush application.
public enum RuntimeConstants {
    /// Default page size for conversation transcript loads.
    public static let conversationMessagePageSize: Int = 9

    /// Maximum number of pending requests in the FIFO queue (excluding running).
    public static let pendingQueueCapacity: Int = 5

    /// Default maximum concurrent running requests across all conversations.
    public static let defaultMaxConcurrentRequests: Int = 3

    /// Anti-starvation: aged threshold in seconds. Queued requests waiting longer
    /// than this are eligible for priority promotion.
    public static let agedThresholdSeconds: TimeInterval = 15

    /// Anti-starvation: after K active-priority grants, one aged request is promoted.
    public static let agedQuotaInterval: Int = 3

    /// Timeout budget for preflight model validation (seconds).
    public static let preflightTimeoutSeconds: Double = 3.0

    /// Timeout budget for active generation (seconds).
    public static let generationTimeoutSeconds: Double = 60.0

    /// Preflight timeout as Duration.
    public static var preflightTimeout: Duration {
        .seconds(preflightTimeoutSeconds)
    }

    /// Generation timeout as Duration.
    public static var generationTimeout: Duration {
        .seconds(generationTimeoutSeconds)
    }

    /// Trailing debounce interval for settings persistence.
    public static let settingsDebounceInterval: Duration = .seconds(1)
}
