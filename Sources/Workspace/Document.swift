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
    /// Set by callers (e.g. the Zen-mode search palette) to request that
    /// the editor scroll to a 1-based line number on its next update.
    /// `EditorView.updateNSView` consumes and clears the value.
    @Published var pendingScrollLine: Int?

    private var savedText: String

    /// Open an existing file from disk.
    init?(url: URL) {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.url = url
        self.displayName = url.lastPathComponent
        self.isUntitled = false
        self.text = raw
        self.savedText = raw
        self.lineEnding = LineEnding.detect(in: raw)
        self.indentation = Indentation.detect(in: raw) ?? Indentation.defaultsFromUserPrefs()
        self.language = LanguageDetector.language(for: url)
    }

    /// Create a new untitled document backed by a temp file.
    init(untitledAt tempURL: URL, displayName: String) {
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
    func save() throws {
        let normalized = lineEnding.normalize(text)
        try normalized.write(to: url, atomically: true, encoding: .utf8)
        savedText = text
        isDirty = false
    }

    /// Write current text to backing temp file without changing dirty state.
    /// Used to keep the temp file in sync as a crash-recovery snapshot.
    func writeDraftSnapshot() {
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
