import Foundation
import MinimalistCore

/// GTK dispatches every callback on the main thread; MinimalistCore's
/// model classes are `@MainActor`. This bridges the toolkit's
/// nonisolated view context onto that guarantee.
func onMain<T>(_ body: @MainActor () throws -> T) rethrows -> T {
    try MainActor.assumeIsolated(body)
}

/// Owns the open `Document` instances and the workspace's file tree.
/// Adwaita's `@State` holds value types only, so reference-typed model
/// state lives here and the views keep lightweight snapshots.
@MainActor
final class DocumentStore {
    static let shared = DocumentStore()

    private(set) var documents: [String: Document] = [:]
    /// Last saved (or freshly loaded) content per document path — what
    /// the editor compares against to show the dirty marker.
    private var baselines: [String: String] = [:]
    private(set) var rootNode: FileNode?
    private(set) var folderURL: URL?

    // MARK: - Folder

    func loadFolder(url: URL) {
        folderURL = url
        rootNode = FileNode(url: url, isDirectory: true)
        rootNode?.loadChildrenIfNeeded()
    }

    /// Flatten the visible part of the file tree for the sidebar list.
    /// `expanded` holds the paths of open directories.
    func visibleRows(expanded: Set<String>) -> [FileRow] {
        guard let rootNode else { return [] }
        rootNode.loadChildrenIfNeeded()
        var rows: [FileRow] = []
        walk(rootNode, depth: 0, expanded: expanded, into: &rows)
        return rows
    }

    private func walk(
        _ node: FileNode,
        depth: Int,
        expanded: Set<String>,
        into rows: inout [FileRow]
    ) {
        for child in node.children ?? [] {
            let path = child.url.path
            rows.append(FileRow(
                id: path,
                name: child.name,
                isDirectory: child.isDirectory,
                depth: depth,
                isExpanded: expanded.contains(path)
            ))
            if child.isDirectory, expanded.contains(path) {
                child.loadChildrenIfNeeded()
                walk(child, depth: depth + 1, expanded: expanded, into: &rows)
            }
        }
    }

    func reloadTree() {
        rootNode?.reloadChildren()
    }

    // MARK: - Documents

    /// Open (or return the already-open) document. Returns nil when the
    /// file can't be read as one of the supported kinds.
    func openDocument(at url: URL) -> Document? {
        let path = url.path
        if let existing = documents[path] { return existing }
        guard let doc = Document(url: url) else { return nil }
        documents[path] = doc
        baselines[path] = doc.text
        return doc
    }

    func baseline(for path: String) -> String {
        baselines[path] ?? ""
    }

    /// Push `text` into the document and persist it. Returns false when
    /// the write fails.
    func save(path: String, text: String) -> Bool {
        guard let doc = documents[path] else { return false }
        doc.text = text
        do {
            try doc.save()
        } catch {
            return false
        }
        baselines[path] = text
        return true
    }

    func newUntitled(named name: String) -> Document {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Minimalist", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Untitled-\(UUID().uuidString).txt")
        let doc = Document(untitledAt: url, displayName: name)
        documents[url.path] = doc
        return doc
    }

    func document(for path: String) -> Document? {
        documents[path]
    }

    func close(path: String) {
        guard let doc = documents.removeValue(forKey: path) else { return }
        baselines.removeValue(forKey: path)
        doc.discardTempBacking()
    }

    /// Move a document under a new path key after Save As / relocate.
    func rekey(from oldPath: String, to newPath: String, baseline: String) {
        guard let doc = documents.removeValue(forKey: oldPath) else { return }
        baselines.removeValue(forKey: oldPath)
        documents[newPath] = doc
        baselines[newPath] = baseline
    }
}

/// One visible row in the sidebar's flattened file tree.
struct FileRow: Identifiable, Equatable {
    /// Absolute path — stable across rebuilds.
    let id: String
    let name: String
    let isDirectory: Bool
    let depth: Int
    let isExpanded: Bool
}

/// One tab in the editor's tab strip.
struct EditorTab: Identifiable, Equatable {
    /// Absolute path of the backing file (temp path for untitled docs).
    var id: String
    var title: String
    /// MinimalistCore language identifier (highlight.js naming).
    var languageID: String
}
