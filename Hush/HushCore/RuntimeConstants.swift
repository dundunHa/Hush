import Foundation

/// Centralized default runtime constants for the Hush application.
public enum RuntimeConstants {
    /// Maximum number of pending requests in the FIFO queue.
    public static let pendingQueueCapacity: Int = 5

    /// Timeout budget for preflight model validation (seconds).
    public static let preflightTimeoutSeconds: Double = 3.0

    /// Timeout budget for active generation (seconds).
    public static let generationTimeoutSeconds: Double = 60.0

    /// Preflight timeout as Duration.
    public static var preflightTimeout: Duration { .seconds(preflightTimeoutSeconds) }

    /// Generation timeout as Duration.
    public static var generationTimeout: Duration { .seconds(generationTimeoutSeconds) }

    /// Trailing debounce interval for settings persistence.
    public static let settingsDebounceInterval: Duration = .seconds(1)
}
