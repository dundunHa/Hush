import Foundation

// MARK: - Sync State

/// Tracks whether a record has been synced to the remote backend.
public nonisolated enum SyncState: String, Codable, Sendable {
    /// Local change not yet dispatched.
    case pending
    /// Successfully synced to remote.
    case synced
}

// MARK: - Device Identifier

/// Provides a stable per-device identifier for sync metadata.
public nonisolated enum DeviceIdentifier {
    /// Returns a stable device ID persisted in UserDefaults.
    /// Created once on first access.
    public nonisolated static let current: String = {
        let key = "com.dundunha.hush.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }()
}
