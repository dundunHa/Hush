import Foundation

extension Notification.Name {
    static let hushOpenSettings = Notification.Name("hushOpenSettings")
}

enum ThinkingStrength: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var id: String {
        rawValue
    }

    var reasoningEffort: ModelReasoningEffort? {
        switch self {
        case .default:
            return nil
        case .low:
            return .low
        case .medium:
            return .medium
        case .high:
            return .high
        }
    }

    static func from(reasoningEffort: ModelReasoningEffort?) -> ThinkingStrength {
        switch reasoningEffort {
        case nil:
            return .default
        case .some(.none), .some(.minimal), .some(.low):
            return .low
        case .some(.medium):
            return .medium
        case .some(.high), .some(.xhigh):
            return .high
        }
    }
}
