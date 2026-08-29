import Adwaita
import CodeEditor
import Foundation
import MinimalistCore

/// v1 shell: header bar with file actions, sidebar file tree, tab strip,
/// GtkSourceView editor. Text documents only — media viewers, revision
/// history, and zen mode stay macOS-only for now.
struct MainView: View {

    var app: AdwaitaApp
    var window: AdwaitaWindow

    @State private var sidebarVisible = true
    @State private var folderName = ""
    @State private var branch = ""
    @State private var rows: [FileRow] = []
    @State private var expanded: Set<String> = []
    @State private var tabs: [EditorTab] = []
    @State private var activeTabID = ""
    @State private var editorText = ""
    @State private var baselineText = ""
    @State private var untitledCount = 0
    @State private var openFileSignal = Signal()
    @State private var openFolderSignal = Signal()
    @State private var saveAsSignal = Signal()

    private var activeTab: EditorTab? {
        tabs.first { $0.id == activeTabID }
    }

    private var isDirty: Bool {
        activeTab != nil && editorText != baselineText
    }

    private var windowTitle: String {
        guard let tab = activeTab else { return "{m.txt}" }
        return (isDirty ? "• " : "") + tab.title
    }

    var view: Body {
        OverlaySplitView(visible: $sidebarVisible) {
            sidebar
        } content: {
            content
        }
        .topToolbar {
            HeaderBar {
                Button("Open…") { openFileSignal.signal() }
                    .keyboardShortcut("o".ctrl())
                Button("Folder…") { openFolderSignal.signal() }
                    .keyboardShortcut("o".ctrl().shift())
                Button("New") { newUntitled() }
                    .keyboardShortcut("n".ctrl())
            } end: {
                branchLabel
                Button("Save") { saveActive() }
                    .keyboardShortcut("s".ctrl())
                    .style("suggested-action")
                Button("Close Tab") { closeActiveTab() }
                    .keyboardShortcut("w".ctrl())
            }
            .headerBarTitle {
                WindowTitle(subtitle: folderName, title: windowTitle)
            }
        }
        .fileImporter(open: $openFileSignal, onOpen: { url in openFile(url) })
        .folderImporter(open: $openFolderSignal, onOpen: { url in openFolder(url) })
        .fileExporter(
            open: $saveAsSignal,
            initialName: activeTab?.title,
            onSave: { url in saveActiveAs(to: url) }
        )
    }

    // MARK: - Subviews

    @ViewBuilder private var branchLabel: Body {
        if !branch.isEmpty {
            Text("⎇ \(branch)")
                .style("dim-label")
        }
    }

    @ViewBuilder private var sidebar: Body {
        ScrollView {
            if rows.isEmpty {
                Text(folderName.isEmpty ? "No folder open" : "Empty folder")
                    .style("dim-label")
                    .padding(20)
            } else {
                List(rows, id: \.id, selection: nil) { row in
                    rowView(row)
                }
                .sidebarStyle()
            }
        }
        .hscrollbarPolicy(.never)
    }

    @ViewBuilder private func rowView(_ row: FileRow) -> Body {
        Button(rowLabel(row)) { rowTapped(row) }
            .style("flat")
            .halign(.start)
            .padding(row.depth * 16, [.leading])
    }

    private func rowLabel(_ row: FileRow) -> String {
        guard row.isDirectory else { return row.name }
        return (row.isExpanded ? "▾ " : "▸ ") + row.name
    }

    @ViewBuilder private var content: Body {
        if tabs.isEmpty {
            StatusPage(
                "No Open Files",
                icon: .default(icon: .documentOpen),
                description: "Open a folder or file to get started"
            )
        } else {
            VStack {
                ToggleGroup(selection: tabSelection, values: tabs, id: \.id, label: \.title)
                    .padding(6)
                ScrollView {
                    codeEditor
                }
                .vexpand()
            }
        }
    }

    private var codeEditor: CodeEditor {
        var editor = CodeEditor(text: $editorText)
            .innerPadding()
            .lineNumbers()
        if let tab = activeTab,
           let language = LanguageMap.editorLanguage(for: tab.languageID) {
            editor = editor.language(language)
        }
        return editor
    }

    private var tabSelection: Binding<String> {
        .init {
            activeTabID
        } set: { newValue in
            activateTab(newValue)
        }
    }

    // MARK: - Folder & sidebar actions

    private func openFolder(_ url: URL) {
        onMain { DocumentStore.shared.loadFolder(url: url) }
        folderName = url.lastPathComponent
        expanded = []
        refreshRows()
        branch = GitService(workingDirectory: url).currentBranch() ?? ""
    }

    private func refreshRows() {
        let expandedPaths = expanded
        rows = onMain { DocumentStore.shared.visibleRows(expanded: expandedPaths) }
    }

    private func rowTapped(_ row: FileRow) {
        if row.isDirectory {
            if expanded.contains(row.id) {
                expanded.remove(row.id)
            } else {
                expanded.insert(row.id)
            }
            refreshRows()
        } else {
            openFile(URL(fileURLWithPath: row.id))
        }
    }

    // MARK: - Tabs & documents

    private func openFile(_ url: URL) {
        let path = url.path
        if tabs.contains(where: { $0.id == path }) {
            activateTab(path)
            return
        }
        let opened = onMain { () -> (languageID: String, isText: Bool)? in
            guard let doc = DocumentStore.shared.openDocument(at: url) else { return nil }
            return (doc.language, doc.kind == .text)
        }
        // v1 edits text documents only; other kinds have no viewer yet.
        guard let opened, opened.isText else { return }
        tabs.append(EditorTab(id: path, title: url.lastPathComponent, languageID: opened.languageID))
        activateTab(path)
    }

    private func newUntitled() {
        untitledCount += 1
        let name = untitledCount == 1 ? "Untitled" : "Untitled \(untitledCount)"
        let (path, languageID) = onMain { () -> (String, String) in
            let doc = DocumentStore.shared.newUntitled(named: name)
            return (doc.url.path, doc.language)
        }
        tabs.append(EditorTab(id: path, title: name, languageID: languageID))
        activateTab(path)
    }

    private func activateTab(_ id: String) {
        guard id != activeTabID, tabs.contains(where: { $0.id == id }) else { return }
        stashActive()
        activeTabID = id
        loadActive()
    }

    /// Push the editor buffer back into the active tab's Document so
    /// switching tabs never loses text.
    private func stashActive() {
        guard let tab = activeTab else { return }
        let text = editorText
        onMain { DocumentStore.shared.document(for: tab.id)?.text = text }
    }

    private func loadActive() {
        guard let tab = activeTab else {
            editorText = ""
            baselineText = ""
            return
        }
        let (text, baseline) = onMain { () -> (String, String) in
            let doc = DocumentStore.shared.document(for: tab.id)
            return (doc?.text ?? "", DocumentStore.shared.baseline(for: tab.id))
        }
        editorText = text
        baselineText = baseline
    }

    private func saveActive() {
        guard let tab = activeTab else { return }
        let untitled = onMain { DocumentStore.shared.document(for: tab.id)?.isUntitled ?? false }
        if untitled {
            saveAsSignal.signal()
            return
        }
        let text = editorText
        if onMain({ DocumentStore.shared.save(path: tab.id, text: text) }) {
            baselineText = text
        }
    }

    private func saveActiveAs(to url: URL) {
        guard let tab = activeTab else { return }
        let text = editorText
        let languageID = onMain { () -> String? in
            guard let doc = DocumentStore.shared.document(for: tab.id) else { return nil }
            doc.text = text
            do {
                try doc.relocate(to: url)
            } catch {
                return nil
            }
            DocumentStore.shared.rekey(from: tab.id, to: url.path, baseline: text)
            return doc.language
        }
        guard let languageID else { return }
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs[index] = EditorTab(
                id: url.path,
                title: url.lastPathComponent,
                languageID: languageID
            )
        }
        activeTabID = url.path
        baselineText = text
        // The saved file may now appear in the open folder's tree.
        onMain { DocumentStore.shared.reloadTree() }
        refreshRows()
    }

    private func closeActiveTab() {
        guard let tab = activeTab,
              let index = tabs.firstIndex(where: { $0.id == tab.id })
        else { return }
        onMain { DocumentStore.shared.close(path: tab.id) }
        tabs.remove(at: index)
        activeTabID = ""
        if let next = tabs.indices.contains(index) ? tabs[index] : tabs.last {
            activateTab(next.id)
        } else {
            editorText = ""
            baselineText = ""
        }
    }

}
