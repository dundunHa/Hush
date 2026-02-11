import Foundation

extension NSAttributedString.Key {
    /// Marks a fenced code block container (header + code) and carries the display language name.
    static let hushCodeBlockLanguage = NSAttributedString.Key("com.hush.markdown.codeBlockLanguage")

    /// Marks the actual code content range inside a code block container.
    /// Used by the transcript UI to implement one-click copy.
    static let hushCodeBlockContent = NSAttributedString.Key("com.hush.markdown.codeBlockContent")
}
