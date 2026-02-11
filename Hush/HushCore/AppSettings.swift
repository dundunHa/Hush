import Foundation

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case dark

    public var displayName: String {
        switch self {
        case .dark:
            return "Dark"
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

public struct AppSettings: Codable, Equatable, Sendable {
    public var providerConfigurations: [ProviderConfiguration]
    public var selectedProviderID: String
    public var selectedModelID: String
    public var parameters: ModelParameters
    public var quickBar: QuickBarConfiguration
    public var theme: AppTheme
    public var maxConcurrentRequests: Int

    public init(
        providerConfigurations: [ProviderConfiguration],
        selectedProviderID: String,
        selectedModelID: String,
        parameters: ModelParameters,
        quickBar: QuickBarConfiguration,
        theme: AppTheme = .dark,
        maxConcurrentRequests: Int = RuntimeConstants.defaultMaxConcurrentRequests
    ) {
        self.providerConfigurations = providerConfigurations
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.parameters = parameters
        self.quickBar = quickBar
        self.theme = theme
        self.maxConcurrentRequests = maxConcurrentRequests
    }

    enum CodingKeys: String, CodingKey {
        case providerConfigurations
        case selectedProviderID
        case selectedModelID
        case parameters
        case quickBar
        case theme
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
        try container.encode(maxConcurrentRequests, forKey: .maxConcurrentRequests)
    }

    public static let `default` = AppSettings(
        providerConfigurations: [],
        selectedProviderID: "",
        selectedModelID: "",
        parameters: .standard,
        quickBar: .standard,
        theme: .dark,
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
            maxConcurrentRequests: RuntimeConstants.defaultMaxConcurrentRequests
        )
    #endif
}
