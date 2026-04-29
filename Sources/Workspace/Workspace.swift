import SwiftUI
import AppKit

@MainActor
final class Workspace: ObservableObject {
    @Published var rootNode: FileNode?
    @Published var openDocuments: [Document] = []
    @Published var activeDocumentID: Document.ID?
    /// File URLs the user has touched recently — most recent first. Used
    /// by the Zen-mode search palette to surface "recently edited" files
    /// when the query is empty. Persisted across launches.
    @Published var recentURLs: [URL] = []

    private var bookmarkedFolderURL: URL?
    /// Per-workspace revision tracker (`.minimal/` git mirror + autosaves).
    /// Created lazily when a folder is opened or restored.
    private(set) var revisionTracker: RevisionTracker?

    /// Only the primary window writes to / reads from the persisted
    /// last-folder + open-files state. Other windows are transient.
    private let shouldPersist: Bool

    init(launch: WindowLaunch = .primary) {
        switch launch {
        case .primary:
            self.shouldPersist = true
            restoreLastFolder()
            restoreOpenFiles()
            restoreRecents()
        case .fresh:
            self.shouldPersist = false
        case .openFile(let url):
            self.shouldPersist = false
            // open() requires the published vars to exist; defer to next
            // tick so the @Published initial assignment lands first.
            DispatchQueue.main.async { [weak self] in self?.open(url: url) }
        case .openFolder(let url):
            self.shouldPersist = false
            DispatchQueue.main.async { [weak self] in self?.loadFolder(url: url) }
        }
    }

    deinit {
        bookmarkedFolderURL?.stopAccessingSecurityScopedResource()
    }

    var activeDocument: Document? {
        openDocuments.first { $0.id == activeDocumentID }
    }

    // MARK: - Folder management

    func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        adoptFolder(at: url)
    }

    /// Public entry point for loading a folder — used by menu commands
    /// that already have a URL in hand (e.g., "Open in Same Window" after
    /// the user has picked a folder via the open panel).
    func adoptFolder(at url: URL) {
        loadFolder(url: url)
        persistFolderBookmark(for: url)
    }

    private func loadFolder(url: URL) {
        bookmarkedFolderURL?.stopAccessingSecurityScopedResource()
        bookmarkedFolderURL = url
        rootNode = FileNode(url: url, isDirectory: true)
        rootNode?.loadChildrenIfNeeded()
        revisionTracker = RevisionTracker(workspaceURL: url)
    }

    private func persistFolderBookmark(for url: URL) {
        guard shouldPersist else { return }
        do {
            let data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: PreferenceKeys.lastFolderBookmark)
        } catch {
            // Non-fatal: persistence won't work but the folder still opens this session.
        }
    }

    private func restoreLastFolder() {
        guard let data = UserDefaults.standard.data(forKey: PreferenceKeys.lastFolderBookmark) else { return }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard url.startAccessingSecurityScopedResource() else { return }
            bookmarkedFolderURL = url
            rootNode = FileNode(url: url, isDirectory: true)
            rootNode?.loadChildrenIfNeeded()
            revisionTracker = RevisionTracker(workspaceURL: url)
            if stale { persistFolderBookmark(for: url) }
        } catch {
            UserDefaults.standard.removeObject(forKey: PreferenceKeys.lastFolderBookmark)
        }
    }

    // MARK: - File opening

    func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url: url)
    }

    /// Open a file. If it's already open, just activates the tab.
    /// Otherwise, opens it as a permanent (pinned) tab.
    func open(url: URL) {
        open(url: url, scrollToLine: nil)
    }

    /// Open the file (re-using an existing tab when present) and, if
    /// `scrollToLine` is set, ask the editor to scroll to that 1-based
    /// line number on its next layout pass.
    func open(url: URL, scrollToLine line: Int?) {
        if let existing = openDocuments.first(where: { $0.url == url }) {
            existing.isPreview = false
            activeDocumentID = existing.id
            existing.pendingScrollLine = line
            persistOpenFiles()
            touchRecent(url)
            return
        }
        guard let doc = Document(url: url) else {
            NSSound.beep()
            return
        }
        doc.isPreview = false
        doc.pendingScrollLine = line
        openDocuments.append(doc)
        activeDocumentID = doc.id
        persistOpenFiles()
        touchRecent(url)
    }

    /// Open a file in preview (italic, single-slot) mode. If a preview tab
    /// already exists, its document is replaced rather than adding a new tab.
    func openPreview(url: URL) {
        // If already open, reuse — but don't downgrade an already-pinned tab.
        if let existing = openDocuments.first(where: { $0.url == url }) {
            activeDocumentID = existing.id
            return
        }
        guard let doc = Document(url: url) else {
            NSSound.beep()
            return
        }
        doc.isPreview = true

        if let previewIdx = openDocuments.firstIndex(where: { $0.isPreview }) {
            // Clean up any temp backing of the outgoing preview doc.
            openDocuments[previewIdx].discardTempBacking()
            openDocuments[previewIdx] = doc
        } else {
            openDocuments.append(doc)
        }
        activeDocumentID = doc.id
        // Don't persist preview tabs.
    }

    /// Pin a document so it stops being a preview / replaceable tab.
    func pin(_ document: Document) {
        guard document.isPreview else { return }
        document.isPreview = false
        persistOpenFiles()
    }

    /// Reorder an open document. `to` is the desired final index in the
    /// `openDocuments` array.
    func moveDocument(from: Int, to: Int) {
        guard from != to,
              openDocuments.indices.contains(from),
              openDocuments.indices.contains(to)
        else { return }
        let doc = openDocuments.remove(at: from)
        openDocuments.insert(doc, at: to)
        persistOpenFiles()
    }

    /// Push the active tab one slot toward the leading edge. No-op if it's
    /// already first or there is no active document.
    func moveActiveTabLeft() {
        guard let active = activeDocument,
              let idx = openDocuments.firstIndex(where: { $0.id == active.id }),
              idx > 0
        else { return }
        moveDocument(from: idx, to: idx - 1)
    }

    /// Push the active tab one slot toward the trailing edge. No-op if it's
    /// already last or there is no active document.
    func moveActiveTabRight() {
        guard let active = activeDocument,
              let idx = openDocuments.firstIndex(where: { $0.id == active.id }),
              idx < openDocuments.count - 1
        else { return }
        moveDocument(from: idx, to: idx + 1)
    }

    // MARK: - New untitled

    func newUntitled() {
        let tempURL = makeTempUntitledURL()
        let doc = Document(untitledAt: tempURL, displayName: nextUntitledName())
        openDocuments.append(doc)
        activeDocumentID = doc.id
    }

    private func makeTempUntitledURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Minimalist", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Untitled-\(UUID().uuidString).txt")
    }

    private func nextUntitledName() -> String {
        let existing = openDocuments
            .filter { $0.isUntitled }
            .compactMap { doc -> Int? in
                let name = doc.displayName
                if name == "Untitled" { return 0 }
                let prefix = "Untitled "
                guard name.hasPrefix(prefix) else { return nil }
                return Int(name.dropFirst(prefix.count))
            }
        if existing.isEmpty { return "Untitled" }
        let next = (existing.max() ?? 0) + 1
        return "Untitled \(next)"
    }

    // MARK: - Close & save

    func closeActive() {
        guard let doc = activeDocument else { return }
        requestClose(doc)
    }

    /// Close the document, prompting if there are unsaved changes.
    func requestClose(_ document: Document) {
        if document.isDirty {
            let response = runUnsavedChangesAlert(for: document)
            switch response {
            case .alertFirstButtonReturn:   // Save
                if saveOrSaveAs(document) { closeImmediately(document) }
            case .alertSecondButtonReturn:  // Don't Save / Discard
                closeImmediately(document)
            default:                        // Cancel
                return
            }
        } else {
            closeImmediately(document)
        }
    }

    private func closeImmediately(_ document: Document) {
        document.discardTempBacking()
        guard let idx = openDocuments.firstIndex(where: { $0.id == document.id }) else { return }
        openDocuments.remove(at: idx)
        if activeDocumentID == document.id {
            activeDocumentID = openDocuments[safe: idx]?.id ?? openDocuments.last?.id
        }
        persistOpenFiles()
    }

    /// Drop any open tabs whose backing file lives under `url` (which can
    /// itself be a file or a folder). Used after a file/folder gets
    /// trashed from the sidebar.
    func purgeTabs(under url: URL) {
        let path = url.standardizedFileURL.path
        let affected = openDocuments.filter {
            let docPath = $0.url.standardizedFileURL.path
            return docPath == path || docPath.hasPrefix(path + "/")
        }
        for doc in affected {
            closeImmediately(doc)
        }
    }

    /// Update any open tabs whose backing path was just renamed from
    /// `oldURL` to `newURL` (handles both individual files and folders
    /// containing open files).
    func reflectMove(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.standardizedFileURL.path
        let newPath = newURL.standardizedFileURL.path
        for doc in openDocuments {
            let docPath = doc.url.standardizedFileURL.path
            if docPath == oldPath {
                doc.url = newURL
                doc.displayName = newURL.lastPathComponent
            } else if docPath.hasPrefix(oldPath + "/") {
                let suffix = String(docPath.dropFirst(oldPath.count))
                doc.url = URL(fileURLWithPath: newPath + suffix)
            }
        }
        persistOpenFiles()
    }

    private func runUnsavedChangesAlert(for document: Document) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(document.displayName)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal()
    }

    @discardableResult
    func saveActive() -> Bool {
        guard let doc = activeDocument else { return false }
        return saveOrSaveAs(doc)
    }

    /// Save the document. Untitled documents prompt for a destination.
    /// Returns true on success, false on cancel or failure.
    @discardableResult
    func saveOrSaveAs(_ document: Document) -> Bool {
        if document.isUntitled {
            return saveAs(document)
        }
        do {
            try document.save()
            // Manual ⌘S commits land in the workspace's `.minimal/files`
            // git mirror — *not* the user's repo. Autosaves are recorded
            // separately on each text-change debounce.
            revisionTracker?.commitOnSave(file: document.url, content: document.text)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    // MARK: - Revision tracker hooks

    /// Snapshot a document's current text into the autosave track. Cheap
    /// and best-effort — caller is responsible for debouncing the call.
    func recordAutosave(for document: Document) {
        guard !document.isUntitled, let tracker = revisionTracker else { return }
        tracker.recordAutosave(file: document.url, content: document.text)
        touchRecent(document.url)
    }

    /// Promote `url` to the front of the recent-files list.
    func touchRecent(_ url: URL) {
        recentURLs.removeAll { $0 == url }
        recentURLs.insert(url, at: 0)
        if recentURLs.count > 12 {
            recentURLs = Array(recentURLs.prefix(12))
        }
        persistRecents()
    }

    private func persistRecents() {
        guard shouldPersist else { return }
        let paths = recentURLs.map { $0.path }
        UserDefaults.standard.set(paths, forKey: PreferenceKeys.recentEditedPaths)
    }

    private func restoreRecents() {
        let paths = UserDefaults.standard.stringArray(forKey: PreferenceKeys.recentEditedPaths) ?? []
        recentURLs = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    /// Make a single "session end" commit covering every dirty / recently-
    /// edited document. Called on app quit.
    func recordSessionEnd() {
        guard let tracker = revisionTracker else { return }
        let entries = openDocuments
            .filter { !$0.isUntitled }
            .map { (url: $0.url, content: $0.text) }
        tracker.commitSessionEnd(files: entries)
    }

    @discardableResult
    private func saveAs(_ document: Document) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.displayName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = []
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let target = panel.url else { return false }
        do {
            try document.relocate(to: target)
            persistOpenFiles()
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    // Backwards-compatible alias used elsewhere in the UI.
    func close(_ document: Document) { requestClose(document) }

    // MARK: - Activate

    func activate(_ document: Document) {
        activeDocumentID = document.id
        if shouldPersist {
            // Only persist the active path for tabs that themselves get
            // persisted (real files, pinned). Untitled or preview tabs
            // would point at paths that won't be in the open-files list
            // after relaunch — clear the stored active so restore falls
            // back cleanly to the first open doc.
            if document.isUntitled || document.isPreview {
                UserDefaults.standard.removeObject(forKey: PreferenceKeys.activeFilePath)
            } else {
                UserDefaults.standard.set(document.url.path, forKey: PreferenceKeys.activeFilePath)
            }
        }
        if !document.isUntitled {
            touchRecent(document.url)
        }
    }

    // MARK: - Persistence of open files

    /// Persist the paths of pinned (non-preview, non-untitled) open files
    /// plus the active one, so they can be restored on next launch.
    func persistOpenFiles() {
        guard shouldPersist else { return }
        let paths = openDocuments
            .filter { !$0.isUntitled && !$0.isPreview }
            .map { $0.url.path }
        UserDefaults.standard.set(paths, forKey: PreferenceKeys.openFilePaths)
        if let active = activeDocument, !active.isUntitled, !active.isPreview {
            UserDefaults.standard.set(active.url.path, forKey: PreferenceKeys.activeFilePath)
        } else {
            UserDefaults.standard.removeObject(forKey: PreferenceKeys.activeFilePath)
        }
    }

    private func restoreOpenFiles() {
        guard let paths = UserDefaults.standard.stringArray(forKey: PreferenceKeys.openFilePaths)
        else { return }

        let activePath = UserDefaults.standard.string(forKey: PreferenceKeys.activeFilePath)
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.isReadableFile(atPath: url.path) else { continue }
            guard let doc = Document(url: url) else { continue }
            doc.isPreview = false
            openDocuments.append(doc)
        }

        if let activePath, let match = openDocuments.first(where: { $0.url.path == activePath }) {
            activeDocumentID = match.id
        } else {
            activeDocumentID = openDocuments.first?.id
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
