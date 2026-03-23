import SwiftUI

struct QuickConversationSurface: NSViewControllerRepresentable {
    @EnvironmentObject private var container: AppContainer

    let conversationId: String?
    let messages: [ChatMessage]
    let isSending: Bool
    let generation: UInt64
    let surfaceStyle: ConversationSurfaceStyle = .quickBar

    func makeNSViewController(context _: Context) -> ConversationViewController {
        ConversationViewController(
            container: container,
            theme: container.settings.theme,
            surfaceStyle: surfaceStyle,
            bottomReservedHeight: 0
        )
    }

    func updateNSViewController(_ controller: ConversationViewController, context _: Context) {
        controller.updatePresentation(
            theme: container.settings.theme,
            surfaceStyle: surfaceStyle,
            bottomReservedHeight: 0
        )
        controller.applyConversationState(
            conversationId: conversationId,
            messages: messages,
            isSending: isSending,
            generation: generation,
            container: container
        )
    }
}
