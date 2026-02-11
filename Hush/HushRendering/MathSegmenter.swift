import Foundation

/// Segments text into alternating literal and math regions.
///
/// Rules:
/// - `$$...$$` = block math (may span newlines)
/// - `$...$` = inline math (single-line only)
/// - `\$` = escaped literal dollar sign
/// - Dollar signs inside code spans/blocks must NOT be passed to this segmenter
///   (the caller strips code regions before calling).
/// - Currency patterns like `$10-$20` remain literal.
enum MathSegmenter {
    // MARK: - Types

    enum Segment: Equatable {
        case text(String)
        case inlineMath(String) // content between $ ... $
        case blockMath(String) // content between $$ ... $$
    }

    // MARK: - Public Interface

    /// Segment a text string into literal and math regions.
    /// This method is nonisolated and performs pure computation.
    nonisolated static func segment(_ input: String) -> [Segment] {
        guard input.contains("$") else {
            return input.isEmpty ? [] : [.text(input)]
        }

        var segments: [Segment] = []
        let chars = Array(input.unicodeScalars)
        let count = chars.count
        var pos = 0
        var textBuffer = ""

        while pos < count {
            // Handle escaped dollar: \$
            if chars[pos] == "\\", pos + 1 < count, chars[pos + 1] == "$" {
                textBuffer.append("$")
                pos += 2
                continue
            }

            // Check for $$ (block math)
            if chars[pos] == "$", pos + 1 < count, chars[pos + 1] == "$" {
                if let (content, endPos) = findBlockMathClose(chars, from: pos + 2) {
                    flushText(&textBuffer, into: &segments)
                    segments.append(.blockMath(content))
                    pos = endPos
                    continue
                }
                // No closing $$ found — render literally (common during streaming)
                textBuffer.append("$")
                textBuffer.append("$")
                pos += 2
                continue
            }

            // Check for $ (inline math)
            if chars[pos] == "$" {
                if let (content, endPos) = findInlineMathClose(chars, from: pos + 1) {
                    // Currency guard: values like $10-$20 or $50, $42.50 should remain literal.
                    if isLikelyCurrencyInline(
                        content,
                        chars: chars,
                        closingDollarAfter: endPos
                    ) {
                        textBuffer.append("$")
                        pos += 1
                        continue
                    }
                    flushText(&textBuffer, into: &segments)
                    segments.append(.inlineMath(content))
                    pos = endPos
                    continue
                }
                // Currency guard for unclosed values like "$100"
                if isCurrencyPattern(chars, at: pos) {
                    textBuffer.append("$")
                    pos += 1
                    continue
                }
                // No closing $ on same line — render literally
                textBuffer.append("$")
                pos += 1
                continue
            }

            textBuffer.unicodeScalars.append(chars[pos])
            pos += 1
        }

        flushText(&textBuffer, into: &segments)
        return segments
    }

    // MARK: - Private

    /// Detect common currency patterns: `$<digit>` not followed by math-like content.
    private nonisolated static func isCurrencyPattern(
        _ chars: [Unicode.Scalar],
        at pos: Int
    ) -> Bool {
        guard pos + 1 < chars.count else { return false }
        let next = chars[pos + 1]
        // $<digit> is likely currency
        return next >= "0" && next <= "9"
    }

    /// Detect inline content that is likely currency rather than math.
    /// Only treat as currency when the closed segment looks like part of a continued
    /// currency sequence (e.g. `$10-$20`, `$50, $42.50`).
    private nonisolated static func isLikelyCurrencyInline(
        _ content: String,
        chars: [Unicode.Scalar],
        closingDollarAfter closingEndPos: Int
    ) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard let first = trimmed.unicodeScalars.first else { return false }
        guard first >= "0", first <= "9" else { return false }

        // Strong math hints should bypass currency detection.
        let mathHintChars = CharacterSet(charactersIn: "\\^_{}()[]=+*/")
        if trimmed.rangeOfCharacter(from: mathHintChars) != nil {
            return false
        }

        // If the inline payload contains letters, assume math variable content.
        if trimmed.rangeOfCharacter(from: .letters) != nil {
            return false
        }

        // Allow only numeric/currency punctuation characters.
        let allowed = CharacterSet(charactersIn: "0123456789.,-% ")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return false
        }

        // Treat as currency only when the closed segment clearly continues into
        // another numeric amount after the closing `$`.
        guard closingEndPos < chars.count else { return false }
        let next = chars[closingEndPos]
        let nextIsDigit = next >= "0" && next <= "9"
        guard nextIsDigit else { return false }

        let hasSeparator = trimmed.contains(",") || trimmed.contains(".") || trimmed.contains("-")
        let endsWithContinuation = trimmed.hasSuffix(",") || trimmed.hasSuffix("-")

        if endsWithContinuation || hasSeparator {
            return true
        }
        return false
    }

    /// Find closing `$$` for block math starting at `from`.
    /// Block math MAY span newlines.
    private nonisolated static func findBlockMathClose(
        _ chars: [Unicode.Scalar],
        from: Int
    ) -> (String, Int)? {
        var pos = from
        var content = ""
        while pos < chars.count {
            if chars[pos] == "$", pos + 1 < chars.count, chars[pos + 1] == "$" {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return (content, pos + 2)
            }
            content.unicodeScalars.append(chars[pos])
            pos += 1
        }
        return nil // unclosed — streaming partial
    }

    /// Find closing `$` for inline math starting at `from`.
    /// Inline math MUST NOT span newlines.
    private nonisolated static func findInlineMathClose(
        _ chars: [Unicode.Scalar],
        from: Int
    ) -> (String, Int)? {
        var pos = from
        var content = ""
        while pos < chars.count {
            let ch = chars[pos]
            // Newline breaks inline math
            if ch == "\n" || ch == "\r" {
                return nil
            }
            if ch == "$" {
                let trimmed = content.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                return (content, pos + 1)
            }
            content.unicodeScalars.append(ch)
            pos += 1
        }
        return nil // unclosed
    }

    private nonisolated static func flushText(
        _ buffer: inout String,
        into segments: inout [Segment]
    ) {
        guard !buffer.isEmpty else { return }
        segments.append(.text(buffer))
        buffer = ""
    }
}
