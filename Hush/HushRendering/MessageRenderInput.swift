import Foundation

/// Input to the message renderer.
struct MessageRenderInput: Sendable {
    let content: String
    let availableWidth: CGFloat
    let style: RenderStyle
    let isStreaming: Bool

    init(
        content: String,
        availableWidth: CGFloat,
        style: RenderStyle = .appDefault(),
        isStreaming: Bool = false
    ) {
        self.content = content
        self.availableWidth = availableWidth
        self.style = style
        self.isStreaming = isStreaming
    }
}
