import AppKit
import Markdown

/// Renders Markdown table nodes as readable monospace text blocks.
enum TableRenderer {
    // MARK: - Public Interface

    /// Render a Markdown `Table` node into a styled monospace attributed string.
    static func render(
        table: Markdown.Table,
        style: RenderStyle,
        maxWidth _: CGFloat
    ) -> NSAttributedString {
        let (headers, rows) = extractTableData(table)
        guard !headers.isEmpty else {
            return NSAttributedString()
        }

        // Calculate column widths
        let columnWidths = computeColumnWidths(headers: headers, rows: rows)

        let result = NSMutableAttributedString()

        // Header row
        let headerLine = formatRow(headers, widths: columnWidths)
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: style.codeFont,
            .foregroundColor: style.tableHeaderColor
        ]
        result.append(NSAttributedString(string: headerLine + "\n", attributes: headerAttrs))

        // Separator
        let separatorLine = columnWidths.map { String(repeating: "─", count: $0) }.joined(separator: "─┼─")
        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: style.codeFont,
            .foregroundColor: style.tableBorderColor
        ]
        result.append(NSAttributedString(string: separatorLine + "\n", attributes: separatorAttrs))

        // Data rows
        let rowAttrs: [NSAttributedString.Key: Any] = [
            .font: style.codeFont,
            .foregroundColor: style.bodyColor
        ]
        for row in rows {
            let line = formatRow(row, widths: columnWidths)
            result.append(NSAttributedString(string: line + "\n", attributes: rowAttrs))
        }

        // Add background paragraph style
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        result.addAttribute(
            .paragraphStyle,
            value: para,
            range: NSRange(location: 0, length: result.length)
        )

        return result
    }

    // MARK: - Private

    private static func extractTableData(
        _ table: Markdown.Table
    ) -> (headers: [String], rows: [[String]]) {
        var headers: [String] = []
        var rows: [[String]] = []

        // Head
        let head = table.head
        for cell in head.cells {
            headers.append(cell.plainText.trimmingCharacters(in: .whitespaces))
        }

        // Body rows
        let body = table.body
        for row in body.rows {
            var rowData: [String] = []
            for cell in row.cells {
                rowData.append(cell.plainText.trimmingCharacters(in: .whitespaces))
            }
            // Pad if fewer columns
            while rowData.count < headers.count {
                rowData.append("")
            }
            rows.append(rowData)
        }

        return (headers, rows)
    }

    private static func computeColumnWidths(
        headers: [String],
        rows: [[String]]
    ) -> [Int] {
        var widths = headers.map(\.count)
        for row in rows {
            for (columnIndex, cell) in row.enumerated() where columnIndex < widths.count {
                widths[columnIndex] = max(widths[columnIndex], cell.count)
            }
        }
        return widths
    }

    private static func formatRow(_ cells: [String], widths: [Int]) -> String {
        var parts: [String] = []
        for (columnIndex, cell) in cells.enumerated() {
            let width = columnIndex < widths.count ? widths[columnIndex] : cell.count
            parts.append(cell.padding(toLength: width, withPad: " ", startingAt: 0))
        }
        return parts.joined(separator: " │ ")
    }
}

// MARK: - Markdown.Table.Cell Helpers

private extension Markdown.Table.Cell {
    var plainText: String {
        var result = ""
        for child in children {
            if let text = child as? Markdown.Text {
                result += text.string
            } else if let code = child as? InlineCode {
                result += code.code
            } else if let emphasis = child as? Emphasis {
                for inner in emphasis.children {
                    if let t = inner as? Markdown.Text { result += t.string }
                }
            } else if let strong = child as? Strong {
                for inner in strong.children {
                    if let t = inner as? Markdown.Text { result += t.string }
                }
            }
        }
        return result
    }
}
