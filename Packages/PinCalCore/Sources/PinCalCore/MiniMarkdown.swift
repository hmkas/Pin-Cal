import Foundation

/// A deliberately small Markdown subset for email messages:
/// `**bold**`, `*italic*` / `_italic_`, `[text](https://link)`, lists with `- ` or `* `,
/// blank lines between paragraphs and single line breaks inside them.
public enum MiniMarkdown {
    public static func html(_ markdown: String) -> String {
        var out = ""
        var inParagraph = false
        var inList = false

        func closeParagraph() { if inParagraph { out += "</p>"; inParagraph = false } }
        func closeList() { if inList { out += "</ul>"; inList = false } }

        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let item = listItem(trimmed) {
                closeParagraph()
                if !inList { out += "<ul>"; inList = true }
                out += "<li>\(inlineHTML(item))</li>"
            } else if trimmed.isEmpty {
                closeParagraph()
                closeList()
            } else {
                closeList()
                if inParagraph { out += "<br>" } else { out += "<p>"; inParagraph = true }
                out += inlineHTML(trimmed)
            }
        }
        closeParagraph()
        closeList()
        return out
    }

    public static func plainText(_ markdown: String) -> String {
        markdown.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let item = listItem(trimmed) { return "• " + inlinePlain(item) }
            return inlinePlain(line)
        }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func listItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern)
    }

    private static let link = regex(#"\[([^\]]+)\]\(([^)\s]+)\)"#)
    private static let bold = regex(#"\*\*(.+?)\*\*"#)
    private static let starItalic = regex(#"(?<![*\w])\*(?![\s*])(.+?)(?<!\s)\*(?![*\w])"#)
    private static let underscoreItalic = regex(#"(?<![\w])_(?!\s)(.+?)(?<!\s)_(?![\w])"#)

    /// Replaces every match, building the replacement from the capture groups.
    private static func replace(_ regex: NSRegularExpression, in text: String, with make: ([String]) -> String) -> String {
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (1..<match.numberOfRanges).map { ns.substring(with: match.range(at: $0)) }
            result += make(groups)
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    static func inlineHTML(_ text: String) -> String {
        formatInline(escape(text), bold: { "<b>\($0)</b>" }, italic: { "<i>\($0)</i>" }) { label, url in
            let safe = url.hasPrefix("http://") || url.hasPrefix("https://") || url.hasPrefix("mailto:")
            return safe ? "<a href=\"\(url)\">\(label)</a>" : label
        }
    }

    static func inlinePlain(_ text: String) -> String {
        formatInline(text, bold: { $0 }, italic: { $0 }) { label, url in
            label == url ? url : "\(label) (\(url))"
        }
    }

    /// Links are swapped for placeholder tokens first, so emphasis markers inside URLs are left alone.
    private static func formatInline(
        _ text: String,
        bold makeBold: (String) -> String,
        italic makeItalic: (String) -> String,
        link makeLink: (String, String) -> String
    ) -> String {
        var links: [(label: String, url: String)] = []
        var s = replace(Self.link, in: text) { groups in
            links.append((groups[0], groups[1]))
            return "\u{E000}\(links.count - 1)\u{E001}"
        }
        s = replace(bold, in: s) { makeBold($0[0]) }
        s = replace(starItalic, in: s) { makeItalic($0[0]) }
        s = replace(underscoreItalic, in: s) { makeItalic($0[0]) }
        for (index, item) in links.enumerated() {
            let label = formatInline(item.label, bold: makeBold, italic: makeItalic, link: makeLink)
            s = s.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: makeLink(label, item.url))
        }
        return s
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
