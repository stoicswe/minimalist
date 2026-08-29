import SwiftUI
import MarkdownUI
import AppKit

/// A full-featured markdown reader powered by MarkdownUI. Supports the
/// CommonMark spec plus GitHub-flavored extensions: tables, task lists,
/// strikethrough, footnotes, nested lists, images, syntax-highlighted code
/// blocks, and more.
///
/// Local-file links (`[label](other-doc.md)`, relative paths, or
/// `file://` URLs) open as new tabs in the workspace instead of being
/// handed to the system. External URLs (`http(s)://`, `mailto:`, etc.)
/// fall through to the standard openURL action.
///
/// Rendering strategy: the document is parsed once per text change, off
/// the main thread, into cached `MarkdownContent` — re-parsing on every
/// SwiftUI update pass was the reader's main source of jank. Large
/// documents are additionally split into heading-bounded sections that
/// render inside a `LazyVStack`, so only the sections near the viewport
/// pay layout cost.
struct MarkdownReaderView: View {
    let text: String
    /// URL of the source document, used to resolve relative links to
    /// other local files. Pass `nil` for ad-hoc / unsaved markdown.
    var sourceURL: URL? = nil

    @EnvironmentObject private var workspace: Workspace

    @State private var chunks: [ReaderChunk] = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MarkdownChunkBuilder.seamSpacing) {
                ForEach(chunks) { chunk in
                    Markdown(chunk.content)
                }
            }
            .markdownTheme(transparentGitHub)
            .markdownTextStyle {
                FontSize(15)
                BackgroundColor(nil)
            }
            .textSelection(.enabled)
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollContentBackground(.hidden)
        .environment(\.openURL, OpenURLAction { url in
            handleLink(url)
        })
        .task(id: text) {
            let source = text
            let built = await Task.detached(priority: .userInitiated) {
                MarkdownChunkBuilder.build(from: source)
            }.value
            if !Task.isCancelled {
                chunks = built
            }
        }
    }

    /// Resolve `url` against the source document, open it in the
    /// workspace if it points at a real local file, otherwise hand it
    /// back to the system to handle (web links, mail, etc.).
    private func handleLink(_ url: URL) -> OpenURLAction.Result {
        if let local = resolveLocalFileURL(url),
           FileManager.default.fileExists(atPath: local.path) {
            workspace.open(url: local)
            return .handled
        }
        return .systemAction
    }

    /// Map a link URL onto a local file URL if it's reasonable to do
    /// so. Returns nil for anything that's clearly an external link.
    private func resolveLocalFileURL(_ url: URL) -> URL? {
        if url.isFileURL {
            return url
        }
        // SwiftUI hands MarkdownUI's `[text](relative.md)` to us as a
        // URL with no scheme — `url.scheme == nil` and `path` containing
        // the relative string. Resolve it against the source document.
        if url.scheme == nil || url.scheme?.isEmpty == true {
            guard let base = sourceURL?.deletingLastPathComponent() else {
                return nil
            }
            // `URL(string:)` may have eaten the `./` or other prefix —
            // rebuild from the absolute string instead so we don't lose
            // any pre-existing relative components.
            let raw = url.absoluteString
            if raw.isEmpty { return nil }
            return URL(fileURLWithPath: raw, relativeTo: base).standardizedFileURL
        }
        // Anything with a scheme other than file:// — http, https,
        // mailto, custom schemes — is for the system to open.
        return nil
    }

    /// `.gitHub` theme with the opaque body / blockquote / table backgrounds
    /// cleared so the editor pane (or its glass blur) shows through.
    private var transparentGitHub: Theme {
        Theme.gitHub
            .text {
                BackgroundColor(nil)
            }
            .blockquote { configuration in
                configuration.label
                    .relativePadding(.horizontal, length: .em(1))
                    .relativeLineSpacing(.em(0.25))
                    .markdownTextStyle {
                        ForegroundColor(Color.secondary)
                    }
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 3)
                    }
            }
    }
}

/// One independently renderable slice of a markdown document, with its
/// content already parsed. `id` is the slice's position, so SwiftUI can
/// diff a rebuilt chunk list against the old one.
// `@unchecked` only because MarkdownUI predates strict concurrency and
// hasn't annotated `MarkdownContent`; it's an immutable parsed value,
// built once in the builder task and only read afterward.
nonisolated struct ReaderChunk: Identifiable, Equatable, @unchecked Sendable {
    let id: Int
    let content: MarkdownContent
}

/// Splits a markdown document into section chunks for lazy rendering.
///
/// Small documents come back as a single chunk — byte-for-byte the same
/// render as feeding the whole string to one `Markdown` view. Documents
/// over `singleChunkLimit` are split at top-level ATX headings so the
/// reader can lay sections out lazily. Split points are chosen
/// conservatively:
///
/// - never inside a fenced code block, HTML comment, or raw HTML block
///   (`<pre>` / `<script>` / `<style>` / `<textarea>`),
/// - only at column-0 headings preceded by a blank line, so lists,
///   blockquotes, and paragraphs are never severed mid-construct,
/// - never at all when the document defines footnotes, since a footnote
///   reference must live in the same parse as its definition.
///
/// Link-reference definitions are collected once and appended to every
/// chunk, so `[text][ref]` style links keep resolving no matter which
/// section their definition originally lived in.
// Runs inside `Task.detached` from the reader view — hence
// `nonisolated` despite the app's MainActor default.
nonisolated enum MarkdownChunkBuilder {
    /// Spacing between chunk views. Every chunk after the first starts
    /// with a heading, and the gitHub theme gives headings a 24pt top
    /// margin — so this reproduces the in-document section spacing.
    static let seamSpacing: CGFloat = 24

    /// Documents at or below this UTF-16 length always render as one
    /// chunk (identical to the pre-chunking behavior).
    private static let singleChunkLimit = 24_000

    /// Sections smaller than this get merged with the following one so
    /// a heading-dense document doesn't explode into hundreds of views.
    private static let minChunkLength = 2_000

    static func build(from text: String) -> [ReaderChunk] {
        guard text.utf16.count > singleChunkLimit,
              !containsFootnoteDefinitions(text)
        else {
            return [ReaderChunk(id: 0, content: MarkdownContent(text))]
        }

        let sections = splitSections(text)
        guard sections.count > 1 else {
            return [ReaderChunk(id: 0, content: MarkdownContent(text))]
        }

        let refs = referenceDefinitions(text)
        return sections.enumerated().map { index, section in
            var body = section.text
            // Chunks that end inside an unterminated fence (only possible
            // for the trailing chunk) must not get definitions appended —
            // they'd render as literal code.
            if !refs.isEmpty && !section.endsInsideBlock {
                body += "\n\n" + refs
            }
            return ReaderChunk(id: index, content: MarkdownContent(body))
        }
    }

    // MARK: - Section splitting

    private struct Section {
        let text: String
        let endsInsideBlock: Bool
    }

    /// Tracks "are we inside a multi-line construct that a heading-looking
    /// line could legally appear inside of" while scanning line by line.
    private struct BlockScanner {
        private var fence: (char: Character, length: Int)?
        private var inComment = false
        /// Lowercased closing tag we're waiting for (e.g. `</pre>`).
        private var rawHTMLCloser: String?

        var isInsideBlock: Bool {
            fence != nil || inComment || rawHTMLCloser != nil
        }

        mutating func consume(_ line: Substring) {
            if let fence {
                closeFenceIfNeeded(line, fence: fence)
                return
            }
            if inComment {
                if line.range(of: "-->") != nil { inComment = false }
                return
            }
            if let closer = rawHTMLCloser {
                if line.lowercased().range(of: closer) != nil { rawHTMLCloser = nil }
                return
            }
            if openFenceIfNeeded(line) { return }
            scanRawHTML(line)
        }

        private mutating func closeFenceIfNeeded(_ line: Substring, fence: (char: Character, length: Int)) {
            let indent = line.prefix(while: { $0 == " " })
            guard indent.count <= 3 else { return }
            let rest = line.dropFirst(indent.count)
            let run = rest.prefix(while: { $0 == fence.char })
            guard run.count >= fence.length,
                  rest.dropFirst(run.count).allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\r" })
            else { return }
            self.fence = nil
        }

        private mutating func openFenceIfNeeded(_ line: Substring) -> Bool {
            let indent = line.prefix(while: { $0 == " " })
            guard indent.count <= 3 else { return false }
            let rest = line.dropFirst(indent.count)
            guard let first = rest.first, first == "`" || first == "~" else { return false }
            let run = rest.prefix(while: { $0 == first })
            guard run.count >= 3 else { return false }
            // A backtick fence's info string may not contain backticks.
            if first == "`" && rest.dropFirst(run.count).contains("`") { return false }
            fence = (first, run.count)
            return true
        }

        /// Detect comment openers and raw-HTML blocks that can span blank
        /// lines (CommonMark HTML block types 1–2), so headings inside
        /// them don't become split points.
        private mutating func scanRawHTML(_ line: Substring) {
            let lower = line.lowercased()
            // Comments: walk `<!--` / `-->` pairs in order; an unmatched
            // trailing opener leaves us inside a comment.
            var searchFrom = lower.startIndex
            var open = false
            while true {
                let token = open ? "-->" : "<!--"
                guard let r = lower.range(of: token, range: searchFrom..<lower.endIndex) else { break }
                open.toggle()
                searchFrom = r.upperBound
            }
            if open {
                inComment = true
                return
            }
            for tag in ["pre", "script", "style", "textarea"] {
                if let r = lower.range(of: "<" + tag, options: .backwards),
                   lower.range(of: "</" + tag, range: r.upperBound..<lower.endIndex) == nil {
                    rawHTMLCloser = "</" + tag
                    return
                }
            }
        }
    }

    /// Split into lines on LF, CRLF, or lone CR. (`"\r\n"` is a single
    /// `Character` in Swift, so splitting on `"\n"` alone would leave
    /// CRLF documents unsplit.) Chunked output is rejoined with `"\n"`,
    /// which renders identically under CommonMark.
    private static func splitLines(_ text: String) -> [Substring] {
        text.split(
            omittingEmptySubsequences: false,
            whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
        )
    }

    private static func splitSections(_ text: String) -> [Section] {
        let lines = splitLines(text)
        var scanner = BlockScanner()
        var sections: [Section] = []
        var sectionStart = 0
        var sectionLength = 0
        var previousBlank = true

        for (index, line) in lines.enumerated() {
            if index > sectionStart,
               sectionLength >= minChunkLength,
               previousBlank,
               !scanner.isInsideBlock,
               isATXHeading(line) {
                sections.append(Section(
                    text: lines[sectionStart..<index].joined(separator: "\n"),
                    endsInsideBlock: false
                ))
                sectionStart = index
                sectionLength = 0
            }
            scanner.consume(line)
            previousBlank = line.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\r" }
            sectionLength += line.utf16.count + 1
        }
        sections.append(Section(
            text: lines[sectionStart...].joined(separator: "\n"),
            endsInsideBlock: scanner.isInsideBlock
        ))
        return sections
    }

    /// Column-0 ATX heading: 1–6 `#` followed by whitespace or EOL. The
    /// column-0 requirement (stricter than CommonMark's ≤3 spaces) keeps
    /// us from splitting a heading that's nested inside a list item.
    private static func isATXHeading(_ line: Substring) -> Bool {
        guard line.first == "#" else { return false }
        let hashes = line.prefix(while: { $0 == "#" })
        guard hashes.count <= 6 else { return false }
        let rest = line.dropFirst(hashes.count)
        return rest.isEmpty || rest.first == " " || rest.first == "\t" || rest.first == "\r"
    }

    // MARK: - Definitions that must be visible to every chunk

    /// All link-reference definition lines (`[label]: destination`),
    /// skipping footnote definitions and anything inside code fences.
    private static func referenceDefinitions(_ text: String) -> String {
        var scanner = BlockScanner()
        var defs: [Substring] = []
        for line in splitLines(text) {
            if !scanner.isInsideBlock, isReferenceDefinition(line) {
                defs.append(line)
            }
            scanner.consume(line)
        }
        return defs.joined(separator: "\n")
    }

    private static func isReferenceDefinition(_ line: Substring) -> Bool {
        let indent = line.prefix(while: { $0 == " " })
        guard indent.count <= 3 else { return false }
        let rest = line.dropFirst(indent.count)
        guard rest.first == "[",
              let close = rest.firstIndex(of: "]")
        else { return false }
        let label = rest[rest.index(after: rest.startIndex)..<close]
        guard !label.isEmpty, label.first != "^" else { return false }
        let afterClose = rest[rest.index(after: close)...]
        return afterClose.first == ":"
    }

    /// Footnote definitions (`[^id]: …`) must be parsed together with
    /// their references, so their presence disables chunking entirely.
    private static func containsFootnoteDefinitions(_ text: String) -> Bool {
        splitLines(text).contains { line in
            let indent = line.prefix(while: { $0 == " " })
            guard indent.count <= 3 else { return false }
            let rest = line.dropFirst(indent.count)
            return rest.hasPrefix("[^") && rest.contains("]:")
        }
    }
}
