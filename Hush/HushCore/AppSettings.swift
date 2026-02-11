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

    public init(
        providerConfigurations: [ProviderConfiguration],
        selectedProviderID: String,
        selectedModelID: String,
        parameters: ModelParameters,
        quickBar: QuickBarConfiguration,
        theme: AppTheme = .dark
    ) {
        self.providerConfigurations = providerConfigurations
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.parameters = parameters
        self.quickBar = quickBar
        self.theme = theme
    }

    enum CodingKeys: String, CodingKey {
        case providerConfigurations
        case selectedProviderID
        case selectedModelID
        case parameters
        case quickBar
        case theme
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerConfigurations = try container.decode([ProviderConfiguration].self, forKey: .providerConfigurations)
        selectedProviderID = try container.decode(String.self, forKey: .selectedProviderID)
        selectedModelID = try container.decode(String.self, forKey: .selectedModelID)
        parameters = try container.decode(ModelParameters.self, forKey: .parameters)
        quickBar = try container.decode(QuickBarConfiguration.self, forKey: .quickBar)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .dark
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerConfigurations, forKey: .providerConfigurations)
        try container.encode(selectedProviderID, forKey: .selectedProviderID)
        try container.encode(selectedModelID, forKey: .selectedModelID)
        try container.encode(parameters, forKey: .parameters)
        try container.encode(quickBar, forKey: .quickBar)
        try container.encode(theme, forKey: .theme)
    }

    public static let `default` = AppSettings(
        providerConfigurations: [ProviderConfiguration.mockDefault()],
        selectedProviderID: "mock",
        selectedModelID: "mock-text-1",
        parameters: .standard,
        quickBar: .standard,
        theme: .dark
    )
}
