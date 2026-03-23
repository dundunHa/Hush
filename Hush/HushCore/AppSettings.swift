import Foundation

public nonisolated enum AppTheme: String, Codable, CaseIterable, Sendable {
    case graphiteGlass
    case lightGlass
    case ivoryGlass

    public var displayName: String {
        switch self {
        case .graphiteGlass:
            return "Graphite Glass"
        case .lightGlass:
            return "Light Glass"
        case .ivoryGlass:
            return "Ivory Glass"
        }
    }

    public var subtitle: String {
        switch self {
        case .graphiteGlass:
            return "Smoked glass for low-glare focus"
        case .lightGlass:
            return "Daylight glass with airy contrast"
        case .ivoryGlass:
            return "Warm paper glass tuned for long reading"
        }
    }

    public var usesGlassSurface: Bool {
        true
    }

    public var usesDarkAppearance: Bool {
        switch self {
        case .graphiteGlass:
            return true
        case .lightGlass, .ivoryGlass:
            return false
        }
    }

    public static func persistedValue(_ rawValue: String) -> AppTheme {
        switch rawValue {
        case AppTheme.graphiteGlass.rawValue, "dark":
            return .graphiteGlass
        case AppTheme.lightGlass.rawValue, "light":
            return .lightGlass
        case AppTheme.ivoryGlass.rawValue, "readPaper":
            return .ivoryGlass
        default:
            return .graphiteGlass
        }
    }
}

public nonisolated struct QuickBarConfiguration: Codable, Equatable, Sendable {
    public static let supportedModifiers = ["command", "option", "shift", "control"]
    public static let supportedKeys: [String] = {
        let letters = (65 ... 90).compactMap(UnicodeScalar.init).map { String(Character($0)) }
        let digits = (0 ... 9).map(String.init)
        return letters + digits
    }()

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

    public var normalizedKey: String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 1 else { return "" }
        return trimmed
    }

    public var normalizedModifiers: [String] {
        let allowed = Set(Self.supportedModifiers)
        let normalized = modifiers.compactMap { raw -> String? in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return allowed.contains(value) ? value : nil
        }

        var seen = Set<String>()
        return Self.supportedModifiers.filter {
            normalized.contains($0) && seen.insert($0).inserted
        }
    }

    public var isValid: Bool {
        Self.supportedKeys.contains(normalizedKey) && !normalizedModifiers.isEmpty
    }

    public var displayString: String {
        guard isValid else { return "Disabled" }

        let prefix = normalizedModifiers.compactMap(Self.modifierSymbol(for:)).joined()
        return prefix + normalizedKey
    }

    public func validated(fallback: QuickBarConfiguration = .standard) -> QuickBarConfiguration {
        let normalized = QuickBarConfiguration(
            key: normalizedKey,
            modifiers: normalizedModifiers
        )
        return normalized.isValid ? normalized : fallback
    }

    public static func modifierSymbol(for modifier: String) -> String? {
        switch modifier {
        case "command":
            return "⌘"
        case "option":
            return "⌥"
        case "shift":
            return "⇧"
        case "control":
            return "⌃"
        default:
            return nil
        }
    }

    public static func modifierDisplayName(for modifier: String) -> String {
        switch modifier {
        case "command":
            return "Command"
        case "option":
            return "Option"
        case "shift":
            return "Shift"
        case "control":
            return "Control"
        default:
            return modifier.capitalized
        }
    }
}

public nonisolated struct AppFontSettings: Codable, Equatable, Sendable {
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

public nonisolated struct AppSettings: Codable, Equatable, Sendable {
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
        theme: AppTheme = .graphiteGlass,
        fontSettings: AppFontSettings = .default,
        maxConcurrentRequests: Int = RuntimeConstants.defaultMaxConcurrentRequests
    ) {
        self.providerConfigurations = providerConfigurations
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.parameters = parameters
        self.quickBar = quickBar.validated()
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
        quickBar = (try container.decodeIfPresent(QuickBarConfiguration.self, forKey: .quickBar) ?? .standard)
            .validated()
        let rawTheme = try container.decodeIfPresent(String.self, forKey: .theme)
        theme = rawTheme.map(AppTheme.persistedValue) ?? .graphiteGlass
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
        theme: .graphiteGlass,
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
            theme: .graphiteGlass,
            fontSettings: .default,
            maxConcurrentRequests: RuntimeConstants.defaultMaxConcurrentRequests
        )
    #endif
}
