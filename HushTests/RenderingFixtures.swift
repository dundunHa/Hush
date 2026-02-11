import Foundation

/// Lightweight test fixtures for the rendering pipeline.
enum RenderingFixtures {
    // MARK: - Markdown

    enum Markdown {
        static let headings = """
        # Heading 1
        ## Heading 2
        ### Heading 3
        """

        static let emphasis = """
        This is *italic* and **bold** and ***bold italic*** text.
        """

        static let paragraphs = """
        First paragraph with some text.

        Second paragraph with more text.
        """

        static let inlineCode = """
        Use `print("hello")` to output text.
        """

        static let fencedCodeBlock = """
        ```swift
        func greet() {
            print("Hello, world!")
        }
        ```
        """

        static let codeBlockWithWhitespace = """
        ```
        line 1
            indented line
        \tline with tab

        empty line above
        ```
        """

        static let unorderedList = """
        - First item
        - Second item
        - Third item
        """

        static let orderedList = """
        1. First item
        2. Second item
        3. Third item
        """

        static let blockquote = """
        > This is a blockquote.
        > It can span multiple lines.
        """

        static let link = """
        Visit [Apple](https://apple.com) for more info.
        """

        static let mixed = """
        # Welcome

        This is a **bold** introduction with `inline code`.

        ## Features

        - Feature one
        - Feature two
        - Feature three

        > Note: this is important.

        ```python
        print("hello")
        ```
        """

        static let plainText = """
        This is just plain text with no markdown formatting at all.
        """
    }

    // MARK: - LaTeX

    enum LaTeX {
        static let inlineSimple = "The equation $x^2 + y^2 = z^2$ is famous."

        static let inlineFraction = "Consider $\\frac{a}{b}$ where $a > 0$."

        static let inlineSeriesWithDots = """
        Taylor series: $\\sin x = x - \\frac{x^3}{3!} + \\frac{x^5}{5!} - \\dots = \\sum_{n=0}^{\\infty} \\frac{(-1)^n x^{2n+1}}{(2n+1)!}$
        """

        static let blockEquation = """
        Here is a block equation:

        $$E = mc^2$$

        That was Einstein's formula.
        """

        static let blockMultiline = """
        $$
        \\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}
        $$
        """

        static let dollarInCode = """
        Use `$HOME` to get the home directory. Also `$$var$$` is not math.
        """

        static let dollarInCodeBlock = """
        ```bash
        echo $HOME
        export PRICE="$100"
        ```
        """

        static let escapedDollar = """
        The price is \\$100 for the item.
        """

        static let currencyRange = """
        The widget costs $10-$20 depending on size.
        """

        static let multipleCurrency = """
        Budget: $50, actual: $42.50, savings: $7.50.
        """

        static let uncloseInline = """
        This has an unclosed $math delimiter
        """

        static let uncloseBlock = """
        This has an unclosed $$block math
        that spans lines
        """

        static let manySegments: String = (0 ..< 220).map { "Equation $x_{\($0)}$ here." }.joined(separator: " ")
    }

    // MARK: - Tables

    enum Tables {
        static let simple = """
        | Name | Age |
        |------|-----|
        | Alice | 30 |
        | Bob | 25 |
        """

        static let withMath = """
        | Angle (deg) | Radian (rad) | $\\sin$ value |
        |-------------|--------------|---------------|
        | $0^\\circ$  | $0$          | $0$           |
        | $30^\\circ$ | $\\pi/6$     | $1/2$         |
        | $45^\\circ$ | $\\pi/4$     | $\\sqrt{2}/2$ |
        | $60^\\circ$ | $\\pi/3$     | $\\sqrt{3}/2$ |
        | $90^\\circ$ | $\\pi/2$     | $1$           |
        """

        static let wide = """
        | Feature | Description | Status | Priority | Assignee | Deadline |
        |---------|-------------|--------|----------|----------|----------|
        | Auth | User authentication system | Done | High | Alice | Jan 2025 |
        | Search | Full-text search engine | In Progress | Medium | Bob | Mar 2025 |
        | Export | CSV and PDF export | Planned | Low | Charlie | Jun 2025 |
        """

        static let withFormatting = """
        | Method | Complexity | Notes |
        |--------|-----------|-------|
        | `sort()` | O(n log n) | *stable* |
        | `search()` | O(log n) | **fast** |
        """

        /// A table with many columns to exercise horizontal scrolling.
        static let wideForAttachment = """
        | ID | Name | Category | Status | Priority | Assignee | Created | Updated | Due Date | Tags | Estimate | Actual |
        |----|------|----------|--------|----------|----------|---------|---------|----------|------|----------|--------|
        | 1 | Authentication flow | Backend | Done | High | Alice | 2025-01 | 2025-02 | 2025-03 | auth,security | 5d | 4d |
        | 2 | Search indexing | Backend | In Progress | Medium | Bob | 2025-02 | 2025-03 | 2025-04 | search,perf | 8d | 6d |
        | 3 | Dark mode support | Frontend | Planned | Low | Charlie | 2025-03 | 2025-03 | 2025-06 | ui,theme | 3d | - |
        """

        /// A table with math expressions in cells for attachment rendering.
        static let withMathForAttachment = """
        | Function | Domain | Range | Period |
        |----------|--------|-------|--------|
        | $\\sin(x)$ | $(-\\infty, \\infty)$ | $[-1, 1]$ | $2\\pi$ |
        | $\\cos(x)$ | $(-\\infty, \\infty)$ | $[-1, 1]$ | $2\\pi$ |
        | $\\tan(x)$ | $x \\neq \\pi/2 + n\\pi$ | $(-\\infty, \\infty)$ | $\\pi$ |
        """

        /// A table that exceeds the row guardrail (maxRows = 80).
        static let pathologicallyLargeRows: String = {
            var lines = ["| Row | Value |", "|-----|-------|"]
            for row in 0 ..< 100 {
                lines.append("| \(row) | val_\(row) |")
            }
            return lines.joined(separator: "\n")
        }()

        /// A table that exceeds the column guardrail (maxColumns = 20).
        static let pathologicallyLargeColumns: String = {
            let colCount = 25
            let headers = (0 ..< colCount).map { "Col\($0)" }.joined(separator: " | ")
            let separator = (0 ..< colCount).map { _ in "---" }.joined(separator: " | ")
            let row = (0 ..< colCount).map { "v\($0)" }.joined(separator: " | ")
            return "| \(headers) |\n| \(separator) |\n| \(row) |"
        }()

        /// A table that exceeds the cell count guardrail (maxCells = 1200).
        /// 10 columns × 130 rows = 1310 cells (header + 129 data rows).
        static let pathologicallyLargeCells: String = {
            let colCount = 10
            let headers = (0 ..< colCount).map { "H\($0)" }.joined(separator: " | ")
            let separator = (0 ..< colCount).map { _ in "---" }.joined(separator: " | ")
            var lines = ["| \(headers) |", "| \(separator) |"]
            for row in 0 ..< 130 {
                let cells = (0 ..< colCount).map { "r\(row)c\($0)" }.joined(separator: " | ")
                lines.append("| \(cells) |")
            }
            return lines.joined(separator: "\n")
        }()

        /// A table that exceeds the rendered chars guardrail (maxRenderedChars = 20000).
        /// Few rows but cells with very long content strings.
        static let pathologicallyLargeChars: String = {
            let longValue = String(repeating: "x", count: 3000)
            var lines = ["| Col1 | Col2 |", "|------|------|"]
            for _ in 0 ..< 5 {
                lines.append("| \(longValue) | \(longValue) |")
            }
            return lines.joined(separator: "\n")
        }()
    }

    // MARK: - Edge Cases

    enum EdgeCases {
        static let empty = ""

        static let onlyWhitespace = "   \n\n   "

        static let veryLong: String = .init(repeating: "This is a line of text. ", count: 2500)

        static let malformedMarkdown = """
        # Unclosed heading
        **unclosed bold
        *unclosed italic
        [unclosed link](
        ```
        unclosed code block
        """

        static let mixedContentLong = """
        # Analysis Results

        The model achieved **98.5%** accuracy with $\\alpha = 0.01$.

        ## Data Summary

        | Metric | Train | Test |
        |--------|-------|------|
        | Accuracy | 99.1% | 98.5% |
        | Loss | 0.02 | 0.05 |

        The loss function is defined as:

        $$L = -\\frac{1}{N}\\sum_{i=1}^{N} y_i \\log(\\hat{y}_i)$$

        ### Code

        ```python
        model.fit(X_train, y_train, epochs=100)
        results = model.evaluate(X_test, y_test)
        print(f"Accuracy: {results['accuracy']:.1%}")
        ```

        > Note: Results may vary with different random seeds.

        - Run 1: $98.2\\%$
        - Run 2: $98.7\\%$
        - Run 3: $98.5\\%$
        """
    }
}
