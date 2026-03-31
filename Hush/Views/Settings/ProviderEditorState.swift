import SwiftUI

enum ProviderEditorTarget: Equatable {
    case existing(String)
    case new

    var providerID: String? {
        switch self {
        case let .existing(providerID):
            return providerID
        case .new:
            return nil
        }
    }
}

struct ProviderEditorSelectionRequest: Equatable {
    let target: ProviderEditorTarget
    let reloadIfSame: Bool
}

struct ProviderEditorSnapshot: Equatable {
    let name: String
    let type: ProviderType
    let endpoint: String
    let defaultModelID: String
    let pinnedModelIDs: [String]
    let isEnabled: Bool
    let hasStoredCredential: Bool
}

struct ProviderEditorBaseline: Equatable {
    let target: ProviderEditorTarget
    let name: String
    let type: ProviderType
    let endpoint: String
    let defaultModelID: String
    let pinnedModelIDs: [String]
    let isEnabled: Bool
    let hasStoredCredential: Bool
}

enum ProviderSettingsLayout {
    static let wideThreshold: CGFloat = 980
    static let listPaneMinWidth: CGFloat = 320
    static let listPaneMaxWidth: CGFloat = 380
    static let listPaneWidthFraction: CGFloat = 0.28
    static let compactListMaxHeight: CGFloat = 280
    static let paneCornerRadius: CGFloat = 22
}
