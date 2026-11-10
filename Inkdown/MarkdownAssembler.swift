import Foundation

// Turns the texts of the single pages into one Markdown file.
enum MarkdownAssembler {

    // Joins the pages in order. Every page starts with an invisible marker
    // `<!-- Page N -->`, so the text can be checked against the original.
    // Blank pages are left out; unreadable pages are named.
    static func assemble(_ pages: [PageResult]) -> String {
        var parts: [String] = []
        for (index, page) in pages.enumerated() {
            let number = index + 1
            switch page {
            case .text(let text):
                parts.append("<!-- Page \(number) -->\n\n\(text)")
            case .unreadable:
                parts.append("<!-- Page \(number) -->\n\n[PAGE \(number) COULD NOT BE READ]")
            case .blank:
                break
            }
        }
        if parts.isEmpty { return "" }
        return parts.joined(separator: "\n\n") + "\n"
    }

    // Tidies what Claude sent back for one page.
    static func clean(_ text: String) -> PageResult {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = removingSurroundingFence(cleaned)
        if cleaned.isEmpty || cleaned == "[BLANK PAGE]" {
            return .blank
        }
        return .text(cleaned)
    }

    // Sometimes a model wraps its whole answer in a code fence (three
    // backticks before and after). If so, the fence is removed. Fences
    // inside the text are left alone.
    private static func removingSurroundingFence(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.count >= 2,
              let first = lines.first, first.hasPrefix("```"),
              let last = lines.last, last == "```" else {
            return text
        }
        lines.removeFirst()
        lines.removeLast()
        // If another fence line is left inside, the outer pair was not a
        // wrapper around everything, so keep the text as it was.
        if lines.contains(where: { $0.hasPrefix("```") }) {
            return text
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
