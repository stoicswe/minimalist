import CodeEditor

/// Maps MinimalistCore's language identifiers (highlight.js naming, from
/// `LanguageDetector`) onto GtkSourceView language ids (CodeEditor's
/// `Language` enum). Returns nil for plain text / unknown languages.
enum LanguageMap {
    static func editorLanguage(for coreID: String) -> Language? {
        if let direct = Language(rawValue: coreID) { return direct }
        switch coreID {
        case "javascript": return .js
        case "objectivec": return .objc
        case "bash": return .sh
        case "plaintext": return nil
        default: return nil
        }
    }
}
