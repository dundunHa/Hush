import Foundation
import GRDB

// MARK: - App Preferences Record

/// GRDB-backed record for the `appPreferences` table.
/// Stores non-provider app settings as flattened columns.
public nonisolated struct AppPreferencesRecord: Codable, Sendable, Equatable {
    public var id: String
    public var selectedProviderID: String
    public var selectedModelID: String
    public var temperature: Double
    public var topP: Double
    public var topK: Int?
    public var maxTokens: Int
    public var presencePenalty: Double
    public var frequencyPenalty: Double
    public var contextMessageLimit: Int?
    public var quickBarKey: String
    public var quickBarModifiers: String // JSON-encoded [String]
    public var theme: String
    public var maxConcurrentRequests: Int?
    public var updatedAt: Date

    public init(
        id: String = "default",
        selectedProviderID: String,
        selectedModelID: String,
        temperature: Double,
        topP: Double,
        topK: Int? = nil,
        maxTokens: Int,
        presencePenalty: Double,
        frequencyPenalty: Double,
        contextMessageLimit: Int? = nil,
        quickBarKey: String,
        quickBarModifiers: String = "[]",
        theme: String = AppTheme.dark.rawValue,
        maxConcurrentRequests: Int? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.contextMessageLimit = contextMessageLimit
        self.quickBarKey = quickBarKey
        self.quickBarModifiers = quickBarModifiers
        self.theme = theme
        self.maxConcurrentRequests = maxConcurrentRequests
        self.updatedAt = updatedAt
    }
}

nonisolated extension AppPreferencesRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "appPreferences"
}

// MARK: - Domain Conversion

public struct AppPreferencesSnapshot: Sendable, Equatable {
    public let selectedProviderID: String
    public let selectedModelID: String
    public let parameters: ModelParameters
    public let quickBar: QuickBarConfiguration
    public let theme: AppTheme
    public let maxConcurrentRequests: Int

    public init(
        selectedProviderID: String,
        selectedModelID: String,
        parameters: ModelParameters,
        quickBar: QuickBarConfiguration,
        theme: AppTheme,
        maxConcurrentRequests: Int = RuntimeConstants.defaultMaxConcurrentRequests
    ) {
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.parameters = parameters
        self.quickBar = quickBar
        self.theme = theme
        self.maxConcurrentRequests = maxConcurrentRequests
    }
}

public extension AppPreferencesRecord {
    /// Converts this GRDB record into domain types for app preferences.
    func toAppPreferences() -> AppPreferencesSnapshot {
        let decoder = JSONDecoder()

        let parsedModifiers: [String] = (try? decoder.decode(
            [String].self,
            from: Data(quickBarModifiers.utf8)
        )) ?? []

        let parsedTheme = AppTheme(rawValue: theme) ?? .dark

        return AppPreferencesSnapshot(
            selectedProviderID: selectedProviderID,
            selectedModelID: selectedModelID,
            parameters: ModelParameters(
                temperature: temperature,
                topP: topP,
                topK: topK,
                maxTokens: maxTokens,
                presencePenalty: presencePenalty,
                frequencyPenalty: frequencyPenalty,
                contextMessageLimit: contextMessageLimit
            ),
            quickBar: QuickBarConfiguration(
                key: quickBarKey,
                modifiers: parsedModifiers
            ),
            theme: parsedTheme,
            maxConcurrentRequests: maxConcurrentRequests ?? RuntimeConstants.defaultMaxConcurrentRequests
        )
    }

    /// Creates a GRDB record from domain `AppSettings`.
    static func from(
        _ settings: AppSettings,
        updatedAt: Date = .now
    ) -> AppPreferencesRecord {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let modifiersJSON = (try? String(
            data: encoder.encode(settings.quickBar.modifiers),
            encoding: .utf8
        )) ?? "[]"

        return AppPreferencesRecord(
            selectedProviderID: settings.selectedProviderID,
            selectedModelID: settings.selectedModelID,
            temperature: settings.parameters.temperature,
            topP: settings.parameters.topP,
            topK: settings.parameters.topK,
            maxTokens: settings.parameters.maxTokens,
            presencePenalty: settings.parameters.presencePenalty,
            frequencyPenalty: settings.parameters.frequencyPenalty,
            contextMessageLimit: settings.parameters.contextMessageLimit,
            quickBarKey: settings.quickBar.key,
            quickBarModifiers: modifiersJSON,
            theme: settings.theme.rawValue,
            maxConcurrentRequests: settings.maxConcurrentRequests,
            updatedAt: updatedAt
        )
    }
}
