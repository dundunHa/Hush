import Foundation

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case dark
    case light
    case readPaper

    public var displayName: String {
        switch self {
        case .dark:
            return "Dark"
        case .light:
            return "Light"
        case .readPaper:
            return "ReadPaper"
        }
    }

    public var subtitle: String {
        switch self {
        case .dark:
            return "Slate contrast for focused work"
        case .light:
            return "Clean daylight canvas"
        case .readPaper:
            return "Warm paper tone for long reading"
        }
    }
}

public struct QuickBarConfiguration: Codable, Equatable, Sendable {
    public var key: String
    public var modifiers: [String]

    public init(
        key: String,
        modifiers: [String]
    ) {
        self.key = key
        self.modifiers = modifiers
    }

    public static let standard = QuickBarConfiguration(
        key: "K",
        modifiers: ["command", "option"]
    )
}

public struct AppFontSettings: Codable, Equatable, Sendable {
    public static let defaultSize: Double = 14
    public static let minimumSize: Double = 11
    public static let maximumSize: Double = 24

    public var familyName: String?
    public var size: Double

    public init(
        familyName: String? = nil,
        size: Double = AppFontSettings.defaultSize
    ) {
        self.familyName = Self.normalizeFamilyName(familyName)
        self.size = size
    }

    public var normalizedFamilyName: String? {
        Self.normalizeFamilyName(familyName)
    }

    public var normalizedSize: Double {
        min(max(size, Self.minimumSize), Self.maximumSize)
    }

    public func scaledSize(from referenceSize: Double) -> Double {
        normalizedSize * (referenceSize / Self.defaultSize)
    }

    public static let `default` = AppFontSettings()

    private static func normalizeFamilyName(_ familyName: String?) -> String? {
        guard let trimmed = familyName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var providerConfigurations: [ProviderConfiguration]
    public var selectedProviderID: String
    public var selectedModelID: String
    public var parameters: ModelParameters
    public var quickBar: QuickBarConfiguration
    public var theme: AppTheme
    public var fontSettings: AppFontSettings
    public var maxConcurrentRequests: Int

    public init(
        providerConfigurations: [ProviderConfiguration],
        selectedProviderID: String,
        selectedModelID: String,
        parameters: ModelParameters,
        quickBar: QuickBarConfiguration,
        theme: AppTheme = .dark,
        fontSettings: AppFontSettings = .default,
        maxConcurrentRequests: Int = RuntimeConstants.defaultMaxConcurrentRequests
    ) {
        self.providerConfigurations = providerConfigurations
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.parameters = parameters
        self.quickBar = quickBar
        self.theme = theme
        self.fontSettings = fontSettings
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    enum CodingKeys: String, CodingKey {
        case providerConfigurations
        case selectedProviderID
        case selectedModelID
        case parameters
        case quickBar
        case theme
        case fontSettings
        case maxConcurrentRequests
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerConfigurations = try container.decodeIfPresent([ProviderConfiguration].self, forKey: .providerConfigurations)
            ?? []
        selectedProviderID = try container.decodeIfPresent(String.self, forKey: .selectedProviderID) ?? ""
        selectedModelID = try container.decodeIfPresent(String.self, forKey: .selectedModelID) ?? ""
        parameters = try container.decodeIfPresent(ModelParameters.self, forKey: .parameters) ?? .standard
        quickBar = try container.decodeIfPresent(QuickBarConfiguration.self, forKey: .quickBar) ?? .standard
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .dark
        fontSettings = try container.decodeIfPresent(AppFontSettings.self, forKey: .fontSettings) ?? .default
        maxConcurrentRequests = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentRequests)
            ?? RuntimeConstants.defaultMaxConcurrentRequests
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerConfigurations, forKey: .providerConfigurations)
        try container.encode(selectedProviderID, forKey: .selectedProviderID)
        try container.encode(selectedModelID, forKey: .selectedModelID)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(quickBar, forKey: .quickBar)
        try container.encode(theme, forKey: .theme)
        try container.encode(fontSettings, forKey: .fontSettings)
        try container.encode(maxConcurrentRequests, forKey: .maxConcurrentRequests)
    }

    public static let `default` = AppSettings(
        providerConfigurations: [],
        selectedProviderID: "",
        selectedModelID: "",
        parameters: .standard,
        quickBar: .standard,
        theme: .dark,
        fontSettings: .default,
        maxConcurrentRequests: RuntimeConstants.defaultMaxConcurrentRequests
    )

    #if DEBUG
        public static let testDefault = AppSettings(
            providerConfigurations: [ProviderConfiguration.mockDefault()],
            selectedProviderID: "mock",
            selectedModelID: "mock-text-1",
            parameters: .standard,
            quickBar: .standard,
            theme: .dark,
            fontSettings: .default,
            maxConcurrentRequests: RuntimeConstants.defaultMaxConcurrentRequests
        )
    #endif
}
