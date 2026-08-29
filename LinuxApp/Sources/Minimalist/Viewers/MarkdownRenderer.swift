import Foundation

/// Renders Markdown into Pango markup for the reader view — the Linux
/// counterpart of the macOS app's MarkdownUI reader.
///
/// This is a deliberately small block/inline renderer rather than a full
/// CommonMark implementation: headings, emphasis, code, lists, quotes,
/// rules, and links, which is what the reader view is for. Anything it
/// doesn't recognize passes through as text.
enum MarkdownRenderer {

    static func pangoMarkup(from markdown: String) -> String {
        var output: [String] = []
        var inFence = false
        var fenceLines: [String] = []

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine

            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inFence {
                    output.append(codeBlock(fenceLines))
                    fenceLines = []
                }
                inFence.toggle()
                continue
            }
            if inFence {
                fenceLines.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                output.append("")
                continue
            }
            if trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }), trimmed.count >= 3 {
                output.append("<span alpha=\"40%\">────────────────────</span>")
                continue
            }
            if let heading = heading(trimmed) {
                output.append(heading)
                continue
            }
            if trimmed.hasPrefix("&gt;") || trimmed.hasPrefix(">") {
                let body = trimmed.drop(while: { $0 == ">" }).trimmingCharacters(in: .whitespaces)
                output.append("<span alpha=\"70%\">▏ <i>\(inlines(body))</i></span>")
                continue
            }
            if let bullet = bullet(line) {
                output.append(bullet)
                continue
            }
            output.append(inlines(trimmed))
        }
        if inFence, !fenceLines.isEmpty {
            output.append(codeBlock(fenceLines))
        }
        return output.joined(separator: "\n")
    }

    // MARK: - Blocks

    private static func heading(_ line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes > 0, hashes <= 6 else { return nil }
        let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        let size: String
        switch hashes {
        case 1: size = "xx-large"
        case 2: size = "x-large"
        case 3: size = "large"
        default: size = "medium"
        }
        return "<span size=\"\(size)\" weight=\"bold\">\(inlines(text))</span>"
    }

    private static func bullet(_ line: String) -> String? {
        let indent = line.prefix { $0 == " " || $0 == "\t" }.count
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let pad = String(repeating: "    ", count: min(indent / 2, 4))
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return "\(pad)• \(inlines(String(trimmed.dropFirst(2))))"
        }
        // Ordered list: `1. text`
        let digits = trimmed.prefix { $0.isNumber }
        if !digits.isEmpty, trimmed.dropFirst(digits.count).hasPrefix(". ") {
            let body = trimmed.dropFirst(digits.count + 2)
            return "\(pad)\(digits). \(inlines(String(body)))"
        }
        return nil
    }

    private static func codeBlock(_ lines: [String]) -> String {
        let body = lines.map(escape).joined(separator: "\n")
        return "<tt><span alpha=\"85%\">\(body)</span></tt>"
    }

    // MARK: - Inlines

    /// Escape first, then re-introduce markup for the inline constructs.
    private static func inlines(_ text: String) -> String {
        var result = escape(text)
        result = replacePairs(in: result, delimiter: "**", open: "<b>", close: "</b>")
        result = replacePairs(in: result, delimiter: "__", open: "<b>", close: "</b>")
        result = replacePairs(in: result, delimiter: "*", open: "<i>", close: "</i>")
        result = replacePairs(in: result, delimiter: "`", open: "<tt>", close: "</tt>")
        result = links(in: result)
        return result
    }

    /// `[title](target)` → a Pango link. Targets are already escaped.
    private static func links(in text: String) -> String {
        var result = ""
        var rest = Substring(text)
        while let openBracket = rest.firstIndex(of: "[") {
            guard let closeBracket = rest[openBracket...].firstIndex(of: "]"),
                  rest.index(after: closeBracket) < rest.endIndex,
                  rest[rest.index(after: closeBracket)] == "(",
                  let closeParen = rest[closeBracket...].firstIndex(of: ")")
            else {
                result += rest[..<rest.index(after: openBracket)]
                rest = rest[rest.index(after: openBracket)...]
                continue
            }
            let title = rest[rest.index(after: openBracket)..<closeBracket]
            let target = rest[rest.index(closeBracket, offsetBy: 2)..<closeParen]
            result += rest[..<openBracket]
            result += "<a href=\"\(target)\">\(title)</a>"
            rest = rest[rest.index(after: closeParen)...]
        }
        return result + rest
    }

    /// Wrap text between matching `delimiter` pairs.
    private static func replacePairs(
        in text: String,
        delimiter: String,
        open: String,
        close: String
    ) -> String {
        let parts = text.components(separatedBy: delimiter)
        guard parts.count >= 3 else { return text }
        var result = parts[0]
        var index = 1
        while index < parts.count {
            if index + 1 < parts.count {
                result += open + parts[index] + close + parts[index + 1]
                index += 2
            } else {
                result += delimiter + parts[index]
                index += 1
            }
        }
        return result
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
