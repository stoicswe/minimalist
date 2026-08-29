import Adwaita
import CodeEditor
import Foundation
import MinimalistCore

/// v1 shell styled after the macOS app: sidebar with project header and
/// branch pill, text-tab strip with a pill highlight on the active tab,
/// GtkSourceView editor with a floating status pill and sidebar toggle.
/// Text documents only — media viewers, revision history, and zen mode
/// stay macOS-only for now.
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
            contentPane
        }
        .topToolbar {
            HeaderBar {
                Button(icon: .custom(name: "document-open-symbolic")) { openFileSignal.signal() }
                    .keyboardShortcut("o".ctrl())
                    .flat()
                Button(icon: .custom(name: "folder-open-symbolic")) { openFolderSignal.signal() }
                    .keyboardShortcut("o".ctrl().shift())
                    .flat()
                Button(icon: .custom(name: "document-new-symbolic")) { newUntitled() }
                    .keyboardShortcut("n".ctrl())
                    .flat()
            } end: {
                Button(icon: .custom(name: "document-save-symbolic")) { saveActive() }
                    .keyboardShortcut("s".ctrl())
                    .flat()
                Button(icon: .custom(name: "window-close-symbolic")) { closeActiveTab() }
                    .keyboardShortcut("w".ctrl())
                    .flat()
            }
            .headerBarTitle {
                WindowTitle(subtitle: folderName, title: windowTitle)
            }
            .style("flat")
        }
        .css { Self.appCSS }
        .fileImporter(open: $openFileSignal, onOpen: { url in openFile(url) })
        .folderImporter(open: $openFolderSignal, onOpen: { url in openFolder(url) })
        .fileExporter(
            open: $saveAsSignal,
            initialName: activeTab?.title,
            onSave: { url in saveActiveAs(to: url) }
        )
    }

    // MARK: - Sidebar

    @ViewBuilder private var sidebar: Body {
        VStack {
            projectHeader
            ScrollView {
                if rows.isEmpty {
                    Text(folderName.isEmpty ? "No folder open" : "Empty folder")
                        .dimLabel()
                        .padding(20)
                } else {
                    List(rows, id: \.id, selection: nil) { row in
                        rowView(row)
                    }
                    .sidebarStyle()
                }
            }
            .hscrollbarPolicy(.never)
            .vexpand()
        }
    }

    @ViewBuilder private var projectHeader: Body {
        HStack(spacing: 8) {
            Text(folderName.isEmpty ? "{m.txt}" : folderName)
                .heading()
            if !branch.isEmpty {
                Text("⎇ \(branch)")
                    .caption()
                    .style("branch-pill")
            }
        }
        .halign(.start)
        .padding(12)
    }

    @ViewBuilder private func rowView(_ row: FileRow) -> Body {
        Button(row.name) { rowTapped(row) }
            .child {
                HStack(spacing: 8) {
                    if row.isDirectory {
                        Image()
                            .iconName(row.isExpanded ? "pan-down-symbolic" : "pan-end-symbolic")
                            .dimLabel()
                        Image()
                            .iconName("folder-symbolic")
                            .dimLabel()
                    } else {
                        Image()
                            .iconName(Self.fileIcon(for: row.name))
                            .dimLabel()
                    }
                    Text(row.name)
                        .dimLabel(row.name.hasPrefix("."))
                }
                .halign(.start)
                .padding(row.depth * 14, [.leading])
            }
            .flat()
            .style("tree-row")
            .style("row-active", active: !row.isDirectory && row.id == activeTabID)
    }

    /// Symbolic icon for a file row, by extension. Sticks to names that
    /// ship with adwaita-icon-theme so nothing renders as image-missing.
    private static func fileIcon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "bmp", "ico":
            return "image-x-generic-symbolic"
        case "mp3", "wav", "flac", "ogg", "m4a":
            return "audio-x-generic-symbolic"
        case "mp4", "mkv", "mov", "webm", "avi":
            return "video-x-generic-symbolic"
        case "zip", "tar", "gz", "xz", "bz2", "7z", "rar":
            return "package-x-generic-symbolic"
        case "sh", "bash", "zsh", "fish":
            return "utilities-terminal-symbolic"
        default:
            return "text-x-generic-symbolic"
        }
    }

    // MARK: - Content

    @ViewBuilder private var contentPane: Body {
        VStack {
            editorArea
        }
        .overlay {
            overlayControls
        }
    }

    @ViewBuilder private var editorArea: Body {
        if tabs.isEmpty {
            StatusPage(
                "No Open Files",
                icon: .default(icon: .documentOpen),
                description: "Open a folder or file to get started"
            )
        } else {
            VStack {
                tabStrip
                ScrollView {
                    codeEditor
                }
                .vexpand()
            }
        }
    }

    @ViewBuilder private var tabStrip: Body {
        ForEach(tabs, id: \.id) { tab in
            Button(tabTitle(tab)) { activateTab(tab.id) }
                .style("tab-item")
                .style("tab-active", active: tab.id == activeTabID)
        }
        .orientation(.horizontal)
        .halign(.start)
        .padding(6)
    }

    private func tabTitle(_ tab: EditorTab) -> String {
        (tab.id == activeTabID && isDirty ? "• " : "") + tab.title
    }

    @ViewBuilder private var overlayControls: Body {
        Button(icon: .custom(name: "sidebar-show-symbolic")) { sidebarVisible.toggle() }
            .circular()
            .style("float-btn")
            .halign(.end)
            .valign(.start)
            .padding(14, [.top, .trailing])
        if let tab = activeTab {
            Text(statusLine(for: tab))
                .caption()
                .monospace()
                .style("status-pill")
                .halign(.end)
                .valign(.end)
                .padding(14, [.bottom, .trailing])
        }
    }

    private func statusLine(for tab: EditorTab) -> String {
        let language = tab.languageID.isEmpty ? "PLAIN TEXT" : tab.languageID.uppercased()
        let lineEnding = editorText.contains("\r\n") ? "CRLF" : "LF"
        return "\(language)  |  \(lineEnding)"
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

    // MARK: - Styling

    /// Styling for the parts of the macOS design that have no stock
    /// libadwaita equivalent: pill tabs, the branch pill, tree rows, and
    /// the floating editor controls.
    private static let appCSS = """
    .branch-pill {
        background-color: alpha(@accent_bg_color, 0.15);
        color: @accent_color;
        border-radius: 999px;
        padding: 2px 10px;
    }
    button.tab-item {
        background: none;
        border-radius: 10px;
        padding: 3px 14px;
        margin: 0 2px;
        min-height: 0;
        color: alpha(@window_fg_color, 0.7);
    }
    button.tab-item.tab-active {
        background-color: alpha(@window_fg_color, 0.08);
        color: @window_fg_color;
    }
    button.tree-row {
        border-radius: 8px;
        padding: 2px 8px;
        min-height: 0;
    }
    button.tree-row.row-active {
        background-color: alpha(@window_fg_color, 0.1);
    }
    .status-pill {
        background-color: mix(@view_bg_color, @view_fg_color, 0.05);
        border: 1px solid alpha(@view_fg_color, 0.1);
        border-radius: 999px;
        padding: 5px 14px;
        box-shadow: 0 2px 6px alpha(black, 0.15);
    }
    button.float-btn {
        background-color: mix(@view_bg_color, @view_fg_color, 0.05);
        border: 1px solid alpha(@view_fg_color, 0.1);
        box-shadow: 0 2px 6px alpha(black, 0.15);
    }
    """

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
