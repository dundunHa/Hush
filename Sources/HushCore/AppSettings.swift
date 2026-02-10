import Foundation

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

    public init(
        providerConfigurations: [ProviderConfiguration],
        selectedProviderID: String,
        selectedModelID: String,
        parameters: ModelParameters,
        quickBar: QuickBarConfiguration
    ) {
        self.providerConfigurations = providerConfigurations
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.parameters = parameters
        self.quickBar = quickBar
    }

    public static let `default` = AppSettings(
        providerConfigurations: [ProviderConfiguration.mockDefault()],
        selectedProviderID: "mock",
        selectedModelID: "mock-text-1",
        parameters: .standard,
        quickBar: .standard
    )
}

