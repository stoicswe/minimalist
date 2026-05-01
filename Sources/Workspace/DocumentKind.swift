import Foundation

/// What kind of file backs a `Document`. Drives which viewer renders
/// inside the editor pane — text gets the code editor (or the markdown /
/// asciidoc reader on toggle), the rest get specialized media viewers
/// or the hex dump.
enum DocumentKind: String, Codable {
    case text
    case pdf
    case image
    case video
    case binary
}

enum DocumentKindDetector {
    /// File-size ceiling above which we don't even attempt a UTF-8 read —
    /// large binaries can hang the main thread. ~50 MB is well past any
    /// reasonable source file but small enough to load images / pdfs of
    /// expected scale through their dedicated viewers separately.
    static let textLoadCeiling: Int64 = 50 * 1024 * 1024

    private static let pdfExtensions: Set<String> = ["pdf"]
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp",
        "heic", "heif", "webp", "ico", "icns",
    ]
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm",
    ]

    /// Returns the kind purely from extension. `nil` means "could be text
    /// or could be binary — caller needs to look at the bytes".
    static func mediaKind(forExtension ext: String) -> DocumentKind? {
        let lower = ext.lowercased()
        if pdfExtensions.contains(lower)   { return .pdf }
        if imageExtensions.contains(lower) { return .image }
        if videoExtensions.contains(lower) { return .video }
        return nil
    }

    /// Treat AsciiDoc (.adoc / .asciidoc / .asc) as text — it goes through
    /// the markdown reader on toggle, with a small AsciiDoc → Markdown
    /// pre-converter applied first.
    static func isAsciiDoc(_ url: URL) -> Bool {
        ["adoc", "asciidoc", "asc"].contains(url.pathExtension.lowercased())
    }

    static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown", "mdx"].contains(url.pathExtension.lowercased())
    }

    /// Whether the reader-view toggle should appear for this URL.
    static func supportsReaderView(_ url: URL) -> Bool {
        isMarkdown(url) || isAsciiDoc(url)
    }
}
