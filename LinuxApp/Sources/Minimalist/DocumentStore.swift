import Foundation
import MinimalistCore

/// GTK dispatches every callback on the main thread; MinimalistCore's
/// model classes are `@MainActor`. This bridges the toolkit's
/// nonisolated view context onto that guarantee.
func onMain<T>(_ body: @MainActor () throws -> T) rethrows -> T {
    try MainActor.assumeIsolated(body)
}

/// Owns the open `Document` instances, the workspace's file tree, the
/// revision tracker, the recents list, and the user's settings.
///
/// Adwaita's `@State` holds value types only, so reference-typed model
/// state lives here and the views keep lightweight snapshots
/// (`FileRow`, `EditorTab`).
@MainActor
final class DocumentStore {
    static let shared = DocumentStore()

    private(set) var documents: [String: Document] = [:]
    private(set) var rootNode: FileNode?
    private(set) var folderURL: URL?
    /// The workspace's `.minimal/` history — autosave snapshots plus a
    /// mirror commit on every save. Created when a folder is opened.
    private(set) var revisionTracker: RevisionTracker?
    private(set) var recentURLs: [URL] = []

    var settings = AppState.loadSettings() {
        didSet {
            guard settings != oldValue else { return }
            AppState.save(settings)
        }
    }

    /// Last time each document was snapshotted into the autosave track,
    /// so edits are debounced the way the macOS app debounces them.
    private var lastAutosave: [String: Date] = [:]
    private static let autosaveInterval: TimeInterval = 60

    private init() {
        AppState.exportIndentationDefaults(settings)
        recentURLs = AppState.loadSession().recentPaths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    // MARK: - Folder

    func loadFolder(url: URL) {
        folderURL = url
        rootNode = FileNode(url: url, isDirectory: true)
        rootNode?.loadChildrenIfNeeded()
        revisionTracker = RevisionTracker(workspaceURL: url)
    }

    /// Flatten the visible part of the file tree for the sidebar list.
    /// `expanded` holds the paths of open directories.
    func visibleRows(expanded: Set<String>) -> [FileRow] {
        guard let rootNode else { return [] }
        rootNode.loadChildrenIfNeeded()
        var rows: [FileRow] = [
            FileRow(
                id: rootNode.url.path,
                name: rootNode.name,
                isDirectory: true,
                depth: 0,
                isExpanded: expanded.contains(rootNode.url.path)
            )
        ]
        if expanded.contains(rootNode.url.path) {
            walk(rootNode, depth: 1, expanded: expanded, into: &rows)
        }
        return rows
    }

    private func walk(
        _ node: FileNode,
        depth: Int,
        expanded: Set<String>,
        into rows: inout [FileRow]
    ) {
        for child in node.children ?? [] {
            if child.isDirectory {
                // Compacted chains: a folder whose only child is a folder
                // collapses into one dotted `parent.child` row, matching
                // the macOS sidebar.
                var tail = child
                var name = child.name
                while true {
                    tail.loadChildrenIfNeeded()
                    guard let children = tail.children,
                          children.count == 1,
                          let only = children.first,
                          only.isDirectory
                    else { break }
                    tail = only
                    name += "." + only.name
                }
                let path = tail.url.path
                let isExpanded = expanded.contains(path)
                rows.append(FileRow(
                    id: path,
                    name: name,
                    isDirectory: true,
                    depth: depth,
                    isExpanded: isExpanded
                ))
                if isExpanded {
                    walk(tail, depth: depth + 1, expanded: expanded, into: &rows)
                }
            } else {
                rows.append(FileRow(
                    id: child.url.path,
                    name: child.name,
                    isDirectory: false,
                    depth: depth,
                    isExpanded: false
                ))
            }
        }
    }

    func reloadTree() {
        rootNode?.reloadChildren()
    }

    /// Re-read the directory that contains `url` so a new / renamed /
    /// deleted entry shows up without rebuilding the whole tree.
    func reloadTree(containing url: URL) {
        reloadTree(folder: url.deletingLastPathComponent())
    }

    /// Re-read one directory of the tree.
    func reloadTree(folder: URL) {
        if let node = findNode(rootNode, matching: folder) {
            node.reloadChildren()
        } else {
            rootNode?.reloadChildren()
        }
    }

    private func findNode(_ node: FileNode?, matching url: URL) -> FileNode? {
        guard let node else { return nil }
        if node.url.standardizedFileURL.path == url.standardizedFileURL.path { return node }
        for child in node.children ?? [] {
            if let match = findNode(child, matching: url) { return match }
        }
        return nil
    }

    // MARK: - Documents

    /// Open (or return the already-open) document. Returns nil when the
    /// file can't be read.
    func openDocument(at url: URL) -> Document? {
        let path = url.path
        if let existing = documents[path] { return existing }
        guard let doc = Document(url: url) else { return nil }
        documents[path] = doc
        touchRecent(url)
        return doc
    }

    func document(for path: String) -> Document? {
        documents[path]
    }

    func isDirty(_ path: String) -> Bool {
        documents[path]?.isDirty ?? false
    }

    /// Push editor text into the document, and snapshot it into the
    /// autosave track when the debounce window has elapsed.
    func updateText(path: String, text: String) {
        guard let doc = documents[path], doc.text != text else { return }
        doc.text = text
        recordAutosave(doc)
    }

    private func recordAutosave(_ doc: Document) {
        guard doc.kind == .text, !doc.isUntitled, let tracker = revisionTracker else { return }
        let now = Date()
        if let last = lastAutosave[doc.url.path], now.timeIntervalSince(last) < Self.autosaveInterval {
            return
        }
        lastAutosave[doc.url.path] = now
        tracker.recordAutosave(file: doc.url, content: doc.text)
    }

    /// Persist `text` and mirror the save into `.minimal/`. Returns false
    /// when the write fails.
    func save(path: String, text: String) -> Bool {
        guard let doc = documents[path] else { return false }
        doc.text = text
        do {
            try doc.save()
        } catch {
            return false
        }
        revisionTracker?.commitOnSave(file: doc.url, content: doc.text)
        touchRecent(doc.url)
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

    func close(path: String) {
        guard let doc = documents.removeValue(forKey: path) else { return }
        lastAutosave.removeValue(forKey: path)
        doc.discardTempBacking()
    }

    /// Move a document under a new path key after Save As / rename.
    func rekey(from oldPath: String, to newPath: String) {
        guard let doc = documents.removeValue(forKey: oldPath) else { return }
        documents[newPath] = doc
        lastAutosave.removeValue(forKey: oldPath)
    }

    /// Follow a rename or move on disk: any open document under `oldURL`
    /// re-points at its new location.
    func reflectMove(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.standardizedFileURL.path
        let newPath = newURL.standardizedFileURL.path
        for (key, doc) in documents {
            let docPath = doc.url.standardizedFileURL.path
            if docPath == oldPath {
                doc.url = newURL
                doc.displayName = newURL.lastPathComponent
                rekey(from: key, to: newPath)
            } else if docPath.hasPrefix(oldPath + "/") {
                let suffix = String(docPath.dropFirst(oldPath.count))
                doc.url = URL(fileURLWithPath: newPath + suffix)
                rekey(from: key, to: newPath + suffix)
            }
        }
    }

    /// Paths of open documents backed by anything under `url` — used to
    /// close their tabs after a delete.
    func paths(under url: URL) -> [String] {
        let path = url.standardizedFileURL.path
        return documents.values
            .map { $0.url.standardizedFileURL.path }
            .filter { $0 == path || $0.hasPrefix(path + "/") }
    }

    // MARK: - Recents

    func touchRecent(_ url: URL) {
        recentURLs.removeAll { $0.path == url.path }
        recentURLs.insert(url, at: 0)
        if recentURLs.count > 12 {
            recentURLs = Array(recentURLs.prefix(12))
        }
    }

    // MARK: - Git

    func branch() -> String {
        guard let folderURL else { return "" }
        return GitService(workingDirectory: folderURL).currentBranch() ?? ""
    }

    func branches() -> [String] {
        guard let folderURL else { return [] }
        return GitService(workingDirectory: folderURL).localBranches()
    }

    func checkout(_ branch: String) -> String? {
        guard let folderURL else { return "No folder open." }
        do {
            try GitService(workingDirectory: folderURL).checkout(branch)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func createBranch(_ name: String) -> String? {
        guard let folderURL else { return "No folder open." }
        do {
            try GitService(workingDirectory: folderURL).createBranch(name)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Session

    /// Snapshot the window for the next launch. Untitled and preview tabs
    /// aren't restorable, so they're left out.
    func captureSession(tabs: [EditorTab], activeTabID: String) -> SessionState {
        let restorable = tabs.filter { !$0.isUntitled && !$0.isPreview }
        let active = tabs.first { $0.id == activeTabID }
        return SessionState(
            folderPath: folderURL?.path,
            openFilePaths: restorable.map(\.id),
            activeFilePath: (active?.isUntitled == false && active?.isPreview == false)
                ? active?.id
                : nil,
            recentPaths: recentURLs.map(\.path)
        )
    }

    /// Write out the session and make a single "session end" commit
    /// covering the open documents, mirroring the macOS quit behavior.
    func endSession(tabs: [EditorTab], activeTabID: String) {
        AppState.save(captureSession(tabs: tabs, activeTabID: activeTabID))
        guard let tracker = revisionTracker else { return }
        let entries = documents.values
            .filter { !$0.isUntitled && $0.kind == .text }
            .map { (url: $0.url, content: $0.text) }
        tracker.commitSessionEnd(files: entries)
    }
}

/// One visible row in the sidebar's flattened file tree.
struct FileRow: Identifiable, Equatable {
    /// Absolute path — stable across rebuilds.
    let id: String
    /// Display name; for a compacted chain, `parent.child`.
    let name: String
    let isDirectory: Bool
    let depth: Int
    let isExpanded: Bool

    var isHidden: Bool { name.hasPrefix(".") }
}

/// One tab in the editor's tab strip.
struct EditorTab: Identifiable, Equatable {
    /// Absolute path of the backing file (temp path for untitled docs).
    var id: String
    var title: String
    /// MinimalistCore language identifier (highlight.js naming).
    var languageID: String
    var kind: DocumentKind = .text
    var isUntitled = false
    /// Preview tabs render italic and are replaced by the next preview,
    /// exactly like the macOS single-slot preview tab.
    var isPreview = false
    /// Markdown / AsciiDoc files can toggle into the reader view.
    var supportsReader = false
    var showReader = false
}
