import Foundation

@MainActor
final class Document: Identifiable, ObservableObject {
    let id = UUID()
    @Published var url: URL
    @Published var displayName: String
    @Published var isUntitled: Bool
    @Published var isPreview: Bool = false
    @Published var text: String {
        didSet {
            isDirty = (text != savedText)
            // Editing a preview tab pins it.
            if isDirty && isPreview { isPreview = false }
        }
    }
    @Published var lineEnding: LineEnding
    @Published var indentation: Indentation
    @Published var language: String
    @Published var isDirty: Bool = false
    /// What kind of file this is. Drives which viewer renders in the
    /// editor pane. For non-text kinds, `text` and friends are unused
    /// placeholders — the underlying file isn't loaded into memory until
    /// the viewer asks for it.
    let kind: DocumentKind
    /// Set by callers (e.g. the Zen-mode search palette) to request that
    /// the editor scroll to a 1-based line number on its next update.
    /// `EditorView.updateNSView` consumes and clears the value.
    @Published var pendingScrollLine: Int?

    private var savedText: String

    /// Open an existing file from disk. Detects the file's kind by
    /// extension first; for unknown extensions, attempts a UTF-8 text
    /// load and falls back to the binary (hex) viewer if the bytes don't
    /// decode as text.
    init?(url: URL) {
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        let ext = url.pathExtension.lowercased()

        if let media = DocumentKindDetector.mediaKind(forExtension: ext) {
            self.kind = media
            self.url = url
            self.displayName = url.lastPathComponent
            self.isUntitled = false
            self.text = ""
            self.savedText = ""
            self.lineEnding = .lf
            self.indentation = Indentation.defaultsFromUserPrefs()
            self.language = "plaintext"
            return
        }

        if let raw = Self.loadAsText(url: url) {
            self.kind = .text
            self.url = url
            self.displayName = url.lastPathComponent
            self.isUntitled = false
            self.text = raw
            self.savedText = raw
            self.lineEnding = LineEnding.detect(in: raw)
            self.indentation = Indentation.detect(in: raw) ?? Indentation.defaultsFromUserPrefs()
            self.language = LanguageDetector.language(for: url)
        } else {
            self.kind = .binary
            self.url = url
            self.displayName = url.lastPathComponent
            self.isUntitled = false
            self.text = ""
            self.savedText = ""
            self.lineEnding = .lf
            self.indentation = Indentation.defaultsFromUserPrefs()
            self.language = "plaintext"
        }
    }

    /// Try to load `url` as a UTF-8 text file. Rejects files larger than
    /// the text-load ceiling and files whose decoded contents contain a
    /// NUL byte (a strong signal of binary content even when the rest
    /// decodes cleanly).
    private static func loadAsText(url: URL) -> String? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let size = (attrs?[.size] as? NSNumber)?.int64Value,
           size > DocumentKindDetector.textLoadCeiling {
            return nil
        }
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        if raw.contains("\u{0}") { return nil }
        return raw
    }

    /// Create a new untitled document backed by a temp file.
    init(untitledAt tempURL: URL, displayName: String) {
        self.kind = .text
        self.url = tempURL
        self.displayName = displayName
        self.isUntitled = true
        self.text = ""
        self.savedText = ""
        self.lineEnding = .lf
        self.indentation = Indentation.defaultsFromUserPrefs()
        self.language = "plaintext"
        // Touch the temp file so it exists for crash-recovery purposes.
        try? "".write(to: tempURL, atomically: true, encoding: .utf8)
    }

    /// Persist current text to the document's current URL (temp or real).
    /// No-op for non-text kinds — the binary / media viewers are read-only.
    func save() throws {
        guard kind == .text else { return }
        let normalized = lineEnding.normalize(text)
        try normalized.write(to: url, atomically: true, encoding: .utf8)
        savedText = text
        isDirty = false
    }

    /// Write current text to backing temp file without changing dirty state.
    /// Used to keep the temp file in sync as a crash-recovery snapshot.
    func writeDraftSnapshot() {
        guard kind == .text else { return }
        let normalized = lineEnding.normalize(text)
        try? normalized.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Promote an untitled document to a real file at `newURL`,
    /// or move an existing document to a new location.
    func relocate(to newURL: URL) throws {
        let oldURL = url
        let normalized = lineEnding.normalize(text)
        try normalized.write(to: newURL, atomically: true, encoding: .utf8)
        if isUntitled {
            try? FileManager.default.removeItem(at: oldURL)
        }
        self.url = newURL
        self.displayName = newURL.lastPathComponent
        self.isUntitled = false
        self.language = LanguageDetector.language(for: newURL)
        self.savedText = text
        self.isDirty = false
    }

    /// Delete the temp file backing an untitled document.
    func discardTempBacking() {
        guard isUntitled else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func reformat(eol: LineEnding, indentation newIndent: Indentation) {
        let withNewIndent = newIndent.reformat(text: text, from: indentation)
        let withNewEOL = eol.normalize(withNewIndent)
        self.indentation = newIndent
        self.lineEnding = eol
        self.text = withNewEOL
    }
}
