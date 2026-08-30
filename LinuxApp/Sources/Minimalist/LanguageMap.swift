import CCodeEditor
import Foundation

/// Maps MinimalistCore's language identifiers (highlight.js naming, from
/// `LanguageDetector`) onto GtkSourceView language ids.
///
/// The ids that ship with GtkSourceView vary by version, so each core
/// language lists candidates and the first one the installed library
/// actually knows about wins.
enum LanguageMap {

    private static let candidates: [String: [String]] = [
        "javascript": ["js", "javascript"],
        "typescript": ["typescript", "js"],
        "objectivec": ["objc"],
        "bash": ["sh", "bash"],
        "python": ["python3", "python"],
        "cpp": ["cpp", "c"],
        "csharp": ["c-sharp", "csharp"],
        "markdown": ["markdown"],
        "protobuf": ["protobuf", "proto"],
        "graphql": ["graphql"],
        "powershell": ["powershell"],
        "scss": ["scss", "css"],
        "less": ["less", "css"],
        "ini": ["ini", "toml"],
        "vim": ["vim", "sh"],
        "plaintext": [],
    ]

    /// Every language id the installed GtkSourceView knows, sorted.
    /// Cached: the list can't change while the app runs, and the editor
    /// consults it on every render.
    static let availableIDs: [String] = loadAvailableIDs()

    private static let knownIDs = Set(availableIDs)

    private static func loadAvailableIDs() -> [String] {
        guard let manager = gtk_source_language_manager_get_default(),
              let raw = gtk_source_language_manager_get_language_ids(manager)
        else { return [] }
        var ids: [String] = []
        var index = 0
        while let entry = raw[index] {
            ids.append(String(cString: entry))
            index += 1
        }
        return ids.sorted()
    }

    /// The GtkSourceView language id for a core language, or nil for
    /// plain text / anything this GtkSourceView build can't highlight.
    static func editorLanguage(for coreID: String) -> String? {
        for candidate in candidates[coreID] ?? [coreID] where knownIDs.contains(candidate) {
            return candidate
        }
        return knownIDs.contains(coreID) ? coreID : nil
    }

    /// The display name GtkSourceView gives a language id.
    static func displayName(of id: String) -> String {
        guard let manager = gtk_source_language_manager_get_default(),
              let language = gtk_source_language_manager_get_language(manager, id),
              let name = gtk_source_language_get_name(language)
        else { return id }
        return String(cString: name)
    }

    /// Style scheme ids available for the syntax-theme preference.
    static let styleSchemeIDs: [String] = loadStyleSchemeIDs()

    private static func loadStyleSchemeIDs() -> [String] {
        guard let manager = gtk_source_style_scheme_manager_get_default(),
              let raw = gtk_source_style_scheme_manager_get_scheme_ids(manager)
        else { return [] }
        var ids: [String] = []
        var index = 0
        while let entry = raw[index] {
            ids.append(String(cString: entry))
            index += 1
        }
        return ids.sorted()
    }
}
