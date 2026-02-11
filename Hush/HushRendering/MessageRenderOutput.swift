import AppKit

/// Output of a completed render pass.
struct MessageRenderOutput {
    let attributedString: NSAttributedString
    let plainText: String
    let diagnostics: [RenderDiagnostic]

    /// Convenience for an empty / fallback output.
    static func plainFallback(_ text: String, style: RenderStyle) -> MessageRenderOutput {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: style.bodyFont,
            .foregroundColor: style.bodyColor
        ]
        return MessageRenderOutput(
            attributedString: NSAttributedString(string: text, attributes: attrs),
            plainText: text,
            diagnostics: [RenderDiagnostic(kind: .renderFailed, message: "Fell back to plain text")]
        )
    }
}

/// A non-fatal diagnostic emitted during rendering.
struct RenderDiagnostic: Sendable, Equatable {
    enum Kind: String, Sendable, Equatable {
        case mathFailed
        case tableFallback
        case tableAttachment
        case guardrailTriggered
        case renderFailed
    }

    let kind: Kind
    let message: String
}
