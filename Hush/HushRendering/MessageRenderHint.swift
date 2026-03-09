import Foundation

/// Scheduling hint attached to a message render request.
///
/// This carries conversation-local position and visibility metadata so
/// non-streaming rich rendering can prioritize "latest + visible" work.
struct MessageRenderHint: Equatable {
    let conversationID: String
    let messageID: UUID
    let rankFromLatest: Int
    let isVisible: Bool
    let switchGeneration: UInt64
}
