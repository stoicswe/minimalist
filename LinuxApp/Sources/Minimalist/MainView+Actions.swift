import Adwaita
import Foundation
import MinimalistCore

extension MainView {

    // MARK: - Session

    /// Reopen the folder, tabs, and active document from the last run.
    func restoreSession() {
        let session = AppState.loadSession()
        // Don't write the half-restored state back over the file.
        restoring = true
        if let path = session.folderPath, FileManager.default.fileExists(atPath: path) {
            openFolder(URL(fileURLWithPath: path))
        }
        for path in session.openFilePaths where FileManager.default.isReadableFile(atPath: path) {
            openFile(URL(fileURLWithPath: path), preview: false)
        }
        if let active = session.activeFilePath, tabs.contains(where: { $0.id == active }) {
            activateTab(active)
        }
        restoring = false
        // `@State` reads stay live through the property wrapper, so this
        // closure sees the current tabs whenever the window closes.
        SessionHook.shared.snapshot = { (tabs, activeTabID) }
        SessionHook.shared.onQuit = { tabs, active in
            onMain { DocumentStore.shared.endSession(tabs: tabs, activeTabID: active) }
        }
    }

    /// Persist the window state after anything that changes it. Cheap
    /// enough to do eagerly, which also means a crash doesn't lose the
    /// session the way a quit-time-only save would.
    func persistSession() {
        guard !restoring else { return }
        let currentTabs = tabs
        let active = activeTabID
        onMain {
            AppState.save(DocumentStore.shared.captureSession(tabs: currentTabs, activeTabID: active))
        }
    }

    // MARK: - Folder & sidebar

    func openFolder(_ url: URL) {
        onMain { DocumentStore.shared.loadFolder(url: url) }
        folderName = url.lastPathComponent
        expanded = [url.path]
        refreshRows()
        branch = onMain { DocumentStore.shared.branch() }
        persistSession()
    }

    func refreshRows() {
        let expandedPaths = expanded
        rows = onMain { DocumentStore.shared.visibleRows(expanded: expandedPaths) }
    }

    func rowTapped(_ row: FileRow) {
        if row.isDirectory {
            if expanded.contains(row.id) {
                expanded.remove(row.id)
            } else {
                expanded.insert(row.id)
            }
            refreshRows()
        } else {
            // Single click previews, matching the macOS sidebar; a double
            // click (see `installPin`) pins the tab.
            openFile(URL(fileURLWithPath: row.id), preview: true)
        }
    }

    // MARK: - Opening documents

    func openFile(_ url: URL, preview: Bool, scrollTo line: Int? = nil) {
        // Folders belong to the tree, not to a tab.
        guard !FileOps.isDirectory(url) else { return }
        let path = url.path
        if tabs.contains(where: { $0.id == path }) {
            activateTab(path)
            if let line { jump(to: line) }
            if !preview { pin(path) }
            return
        }
        let opened = onMain { () -> (language: String, kind: DocumentKind)? in
            guard let doc = DocumentStore.shared.openDocument(at: url) else { return nil }
            doc.isPreview = preview
            return (doc.language, doc.kind)
        }
        guard let opened else {
            report("Couldn't open \(url.lastPathComponent).")
            return
        }
        let tab = EditorTab(
            id: path,
            title: url.lastPathComponent,
            languageID: opened.language,
            kind: opened.kind,
            isPreview: preview,
            supportsReader: DocumentKindDetector.supportsReaderView(url)
        )

        // Preview tabs occupy a single slot: the next preview replaces the
        // previous one instead of piling up.
        if preview, let index = tabs.firstIndex(where: { $0.isPreview }) {
            let outgoing = tabs[index].id
            onMain { DocumentStore.shared.close(path: outgoing) }
            tabs[index] = tab
        } else {
            tabs.append(tab)
        }
        activateTab(path)
        if let line { jump(to: line) }
        persistSession()
    }

    func newUntitled() {
        untitledCount += 1
        let name = untitledCount == 1 ? "Untitled" : "Untitled \(untitledCount)"
        let (path, languageID) = onMain { () -> (String, String) in
            let doc = DocumentStore.shared.newUntitled(named: name)
            return (doc.url.path, doc.language)
        }
        tabs.append(EditorTab(id: path, title: name, languageID: languageID, isUntitled: true))
        activateTab(path)
    }

    func activateTab(_ id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        if tabs.first(where: { $0.id == id })?.isUntitled == false {
            onMain { DocumentStore.shared.touchRecent(URL(fileURLWithPath: id)) }
        }
        chromeTick &+= 1
        persistSession()
    }

    /// Promote a preview tab to a permanent one.
    func pin(_ id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs[index].isPreview else { return }
        tabs[index].isPreview = false
        onMain { DocumentStore.shared.document(for: id)?.isPreview = false }
        persistSession()
    }

    func moveActiveTab(by offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }) else { return }
        let target = index + offset
        guard tabs.indices.contains(target) else { return }
        let tab = tabs.remove(at: index)
        tabs.insert(tab, at: target)
        persistSession()
    }

    // MARK: - Saving & closing

    func saveActive() {
        guard let tab = activeTab else { return }
        let untitled = onMain { DocumentStore.shared.document(for: tab.id)?.isUntitled ?? false }
        if untitled {
            saveAsSignal.signal()
            return
        }
        if onMain({ DocumentStore.shared.save(path: tab.id, text: text(of: tab.id)) }) {
            chromeTick &+= 1
        } else {
            report("Couldn't save \(tab.title).")
        }
    }

    func saveActiveAs(to url: URL) {
        guard let tab = activeTab else { return }
        let text = text(of: tab.id)
        let languageID = onMain { () -> String? in
            guard let doc = DocumentStore.shared.document(for: tab.id) else { return nil }
            doc.text = text
            do {
                try doc.relocate(to: url)
            } catch {
                return nil
            }
            DocumentStore.shared.rekey(from: tab.id, to: url.path)
            DocumentStore.shared.revisionTracker?.commitOnSave(file: url, content: text)
            return doc.language
        }
        guard let languageID else {
            report("Couldn't save to \(url.lastPathComponent).")
            return
        }
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index] = EditorTab(
                id: url.path,
                title: url.lastPathComponent,
                languageID: languageID,
                kind: .text,
                supportsReader: DocumentKindDetector.supportsReaderView(url)
            )
        }
        activeTabID = url.path
        chromeTick &+= 1
        onMain { DocumentStore.shared.reloadTree(containing: url) }
        refreshRows()
        persistSession()
        if closeAfterSave {
            closeAfterSave = false
            closeTab(url.path)
        }
    }

    /// Close a tab, asking about unsaved changes first — the Linux face
    /// of the macOS Save / Don't Save / Cancel alert.
    func requestCloseTab(_ id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        if isDirty(id) {
            pendingCloseID = id
            unsavedVisible = true
        } else {
            closeTab(id)
        }
    }

    func discardAndClose() {
        let id = pendingCloseID
        pendingCloseID = ""
        closeTab(id)
    }

    func saveAndClose() {
        let id = pendingCloseID
        pendingCloseID = ""
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if tab.isUntitled {
            // Save As needs the exporter; `saveActiveAs` closes the tab
            // once the file lands.
            activateTab(id)
            closeAfterSave = true
            saveAsSignal.signal()
            return
        }
        if onMain({ DocumentStore.shared.save(path: id, text: text(of: id)) }) {
            closeTab(id)
        } else {
            report("Couldn't save \(tab.title).")
        }
    }

    func closeTab(_ id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        onMain { DocumentStore.shared.close(path: id) }
        tabs.remove(at: index)
        if activeTabID == id {
            if let next = tabs.indices.contains(index) ? tabs[index] : tabs.last {
                activateTab(next.id)
            } else {
                activeTabID = ""
            }
        }
        chromeTick &+= 1
        persistSession()
    }

    // MARK: - View toggles

    func toggleWordWrap() {
        onMain { DocumentStore.shared.settings.wordWrap.toggle() }
        chromeTick &+= 1
    }

    func toggleMinimap() {
        onMain { DocumentStore.shared.settings.showMinimap.toggle() }
        chromeTick &+= 1
    }

    func toggleReader() {
        guard let index = tabs.firstIndex(where: { $0.id == activeTabID }), tabs[index].supportsReader else {
            return
        }
        tabs[index].showReader.toggle()
    }

    func jump(to line: Int) {
        scrollLine = line
        scrollToken &+= 1
    }

    // MARK: - Document facts

    func isDirty(_ id: String) -> Bool {
        onMain { DocumentStore.shared.isDirty(id) }
    }

    func title(of id: String) -> String {
        tabs.first { $0.id == id }?.title ?? ""
    }

    func name(of path: String) -> String {
        path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent
    }

    func indentation(of tab: EditorTab) -> Indentation {
        onMain {
            DocumentStore.shared.document(for: tab.id)?.indentation
                ?? DocumentStore.shared.settings.indentation
        }
    }

    func lineEnding(of tab: EditorTab) -> LineEnding {
        onMain {
            DocumentStore.shared.document(for: tab.id)?.lineEnding
                ?? DocumentStore.shared.settings.lineEnding
        }
    }

    func setLanguage(_ id: String, for tabID: String) {
        onMain { DocumentStore.shared.document(for: tabID)?.language = id }
        if let index = tabs.firstIndex(where: { $0.id == tabID }) {
            tabs[index].languageID = id
        }
    }

    func setIndentation(kind: Indentation.Kind, width: Int, for tabID: String) {
        let updated = Indentation(kind: kind, width: width)
        onMain {
            guard let doc = DocumentStore.shared.document(for: tabID), doc.indentation != updated else {
                return
            }
            // Reformatting rewrites the leading whitespace of every line,
            // which the editor picks up through its document binding.
            doc.reformat(eol: doc.lineEnding, indentation: updated)
        }
        chromeTick &+= 1
    }

    func setLineEnding(_ ending: LineEnding, for tabID: String) {
        onMain { DocumentStore.shared.document(for: tabID)?.lineEnding = ending }
        chromeTick &+= 1
    }

    /// "Use as default" in the status popover: adopt this document's
    /// indentation and line endings for newly opened files.
    func adoptDocumentDefaults(for tab: EditorTab) {
        let indent = indentation(of: tab)
        let ending = lineEnding(of: tab)
        onMain {
            DocumentStore.shared.settings.indentKind = indent.kind.rawValue
            DocumentStore.shared.settings.indentWidth = indent.width
            DocumentStore.shared.settings.defaultLineEnding = ending.rawValue
            AppState.exportIndentationDefaults(DocumentStore.shared.settings)
        }
        statusPopoverVisible = false
    }

    // MARK: - Sidebar file operations

    func promptName(_ kind: NamePrompt) {
        namePromptKind = kind
        namePromptTarget = contextRowID
        switch kind {
        case .newFile: namePromptValue = "untitled.txt"
        case .newFolder: namePromptValue = "untitled folder"
        case .rename: namePromptValue = name(of: contextRowID)
        }
        namePromptVisible = true
    }

    func commitNamePrompt() {
        let target = URL(fileURLWithPath: namePromptTarget)
        let value = namePromptValue
        do {
            switch namePromptKind {
            case .newFile:
                let created = try FileOps.createFile(named: value, in: parentFolder(of: target))
                refreshAfterFileOperation(at: created)
                openFile(created, preview: false)
            case .newFolder:
                let created = try FileOps.createFolder(named: value, in: parentFolder(of: target))
                refreshAfterFileOperation(at: created)
            case .rename:
                let renamed = try FileOps.rename(target, to: value)
                onMain { DocumentStore.shared.reflectMove(from: target, to: renamed) }
                renameTabs(from: target, to: renamed)
                refreshAfterFileOperation(at: renamed)
            }
        } catch {
            report(error.localizedDescription)
        }
    }

    func duplicateContextTarget() {
        do {
            let copy = try FileOps.duplicate(URL(fileURLWithPath: contextRowID))
            refreshAfterFileOperation(at: copy)
        } catch {
            report(error.localizedDescription)
        }
    }

    func copyContextPath() {
        AdwaitaApp.copy(contextRowID)
    }

    func revealContextTarget() {
        let url = URL(fileURLWithPath: contextRowID)
        let folder = FileOps.isDirectory(url) ? url : url.deletingLastPathComponent()
        GTKBridge.openURI(folder.absoluteString)
    }

    func deleteContextTarget() {
        let url = URL(fileURLWithPath: contextRowID)
        guard GTKBridge.moveToTrash(url) else {
            report("Couldn't move “\(url.lastPathComponent)” to the trash.")
            return
        }
        for path in onMain({ DocumentStore.shared.paths(under: url) }) {
            closeTab(path)
        }
        refreshAfterFileOperation(at: url)
    }

    /// The folder new entries go into: the row itself when it's a folder,
    /// otherwise the folder containing it.
    private func parentFolder(of url: URL) -> URL {
        if url.path.isEmpty {
            return onMain { DocumentStore.shared.folderURL } ?? FileManager.default.homeDirectoryForCurrentUser
        }
        return FileOps.isDirectory(url) ? url : url.deletingLastPathComponent()
    }

    private func refreshAfterFileOperation(at url: URL) {
        onMain { DocumentStore.shared.reloadTree(containing: url) }
        refreshRows()
    }

    private func renameTabs(from oldURL: URL, to newURL: URL) {
        let oldPath = oldURL.standardizedFileURL.path
        let newPath = newURL.standardizedFileURL.path
        for index in tabs.indices {
            let path = tabs[index].id
            if path == oldPath {
                tabs[index].id = newPath
                tabs[index].title = newURL.lastPathComponent
            } else if path.hasPrefix(oldPath + "/") {
                tabs[index].id = newPath + String(path.dropFirst(oldPath.count))
            }
        }
        if activeTabID == oldPath { activeTabID = newPath }
        persistSession()
    }

    // MARK: - Git

    func checkout(_ name: String) {
        if let error = onMain({ DocumentStore.shared.checkout(name) }) {
            report(error)
            return
        }
        branch = onMain { DocumentStore.shared.branch() }
        onMain { DocumentStore.shared.reloadTree() }
        refreshRows()
    }

    func createBranch() {
        let name = newBranchName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let error = onMain({ DocumentStore.shared.createBranch(name) }) {
            report(error)
            return
        }
        checkout(name)
    }

    // MARK: - Errors

    func report(_ message: String) {
        errorMessage = message
        errorVisible = true
    }

    // MARK: - GTK event wiring

    /// Window-level key handling: ⇧⇧ opens the search palette (as in the
    /// macOS app) and Escape closes it. Installed once per widget.
    func installKeyHandling(_ storage: ViewStorage) {
        guard storage.fields["keys-installed"] == nil,
              let root = GTKBridge.root(of: storage.opaquePointer)
        else { return }
        storage.fields["keys-installed"] = true
        GTKBridge.onKeyPressed(root) { keyval, _ in
            handleKey(keyval)
        }
    }

    private func handleKey(_ keyval: UInt32) -> Bool {
        let shiftLeft: UInt32 = 0xffe1
        let shiftRight: UInt32 = 0xffe2
        let escape: UInt32 = 0xff1b
        let up: UInt32 = 0xff52
        let down: UInt32 = 0xff54
        let enter: UInt32 = 0xff0d
        let keypadEnter: UInt32 = 0xff8d

        if searchVisible {
            switch keyval {
            case escape:
                closeSearch()
                return true
            case up:
                searchIndex = max(0, searchIndex - 1)
                return true
            case down:
                searchIndex = min(max(0, searchResults.count - 1), searchIndex + 1)
                return true
            case enter, keypadEnter:
                activateSearchSelection()
                return true
            default:
                break
            }
        } else if keyval == escape, zenMode {
            zenMode = false
            return true
        }

        if keyval == shiftLeft || keyval == shiftRight {
            let now = Date()
            if let last = ShiftTracker.shared.lastPress, now.timeIntervalSince(last) < 0.4 {
                ShiftTracker.shared.lastPress = nil
                openSearch()
                return true
            }
            ShiftTracker.shared.lastPress = now
        } else {
            ShiftTracker.shared.lastPress = nil
        }
        return false
    }

    /// Right-click on a sidebar row opens the context menu for that row.
    func installContextMenu(_ storage: ViewStorage, rowID: String) {
        guard storage.fields["context-installed"] == nil else { return }
        storage.fields["context-installed"] = true
        GTKBridge.onSecondaryClick(storage.opaquePointer) {
            contextRowID = rowID
            showContextMenu = true
        }
    }

    /// Double-clicking a sidebar row pins the preview tab it opens.
    func installPin(_ storage: ViewStorage, rowID: String) {
        guard storage.fields["pin-installed"] == nil else { return }
        storage.fields["pin-installed"] = true
        GTKBridge.onDoubleClick(storage.opaquePointer) {
            openFile(URL(fileURLWithPath: rowID), preview: false)
        }
    }

    /// Double-clicking a preview tab pins it, matching macOS.
    func installPinTab(_ storage: ViewStorage, tabID: String) {
        guard storage.fields["pin-installed"] == nil else { return }
        storage.fields["pin-installed"] = true
        GTKBridge.onDoubleClick(storage.opaquePointer) { pin(tabID) }
    }
}

/// Tracks the last bare-Shift press for the double-shift palette gesture.
final class ShiftTracker {
    static let shared = ShiftTracker()
    var lastPress: Date?
}

/// Lets the window's close handler reach the view's tab state at quit
/// time, where the "session end" commit and final snapshot are written.
final class SessionHook {
    static let shared = SessionHook()
    var snapshot: () -> (tabs: [EditorTab], active: String) = { ([], "") }
    var onQuit: ([EditorTab], String) -> Void = { _, _ in }

    func quit() {
        let state = snapshot()
        onQuit(state.tabs, state.active)
    }
}
