import SwiftUI
import AppKit

/// Spotlight-style search palette shown over the editor in Zen mode. Search
/// matches across:
///   - filenames in the workspace tree,
///   - line snippets in the active file,
///   - and (with an empty query) the most recently edited files.
struct ZenSearchPalette: View {
    @EnvironmentObject var workspace: Workspace
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false

    /// `line` is non-nil only for in-file matches. Receivers should open
    /// the file and (if line is set) scroll the editor to that line.
    let onJump: (URL, Int?) -> Void
    let onClose: () -> Void

    @State private var query: String = ""
    @State private var results: [ZenSearchResult] = []
    @State private var selectedIndex: Int = 0
    @FocusState private var fieldFocused: Bool
    /// While the query is exactly ".", the palette acts as a folder
    /// browser rooted at this URL. Defaults to the workspace root and
    /// updates as the user navigates folders.
    @State private var browseURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if browseURL != nil {
                Divider()
                browseHeader
            }
            if !results.isEmpty {
                Divider()
                resultsList
            }
        }
        .modifier(PaletteSurface(useGlass: windowGlass))
        .onAppear {
            fieldFocused = true
            recompute()
        }
        .onChange(of: query) { _, _ in
            recompute()
            selectedIndex = 0
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("Search files or content", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($fieldFocused)
                .onSubmit { activateSelected() }
                .onKeyPress(.upArrow) {
                    selectedIndex = max(0, selectedIndex - 1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    selectedIndex = min(max(0, results.count - 1), selectedIndex + 1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var browseHeader: some View {
        if let url = browseURL {
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(browseSubtitle(for: url))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { idx, result in
                    ResultRow(result: result, isSelected: idx == selectedIndex)
                        .contentShape(Rectangle())
                        .onTapGesture { activate(result) }
                        .onHover { hovering in
                            if hovering { selectedIndex = idx }
                        }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 380)
    }

    // MARK: - Actions

    private func activateSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        activate(results[selectedIndex])
    }

    private func activate(_ result: ZenSearchResult) {
        switch result.kind {
        case .file(let url), .recent(let url):
            onJump(url, nil)
        case .inFile(let url, let line):
            onJump(url, line)
        case .folder(let url), .parentFolder(let url):
            // Navigate the browser without closing the palette.
            browseURL = url
            selectedIndex = 0
            recompute()
        case .command(let cmd):
            run(cmd)
        }
    }

    // MARK: - Commands

    private func run(_ cmd: ZenCommand) {
        // Close the palette before showing the modal panel — the panel
        // and the SwiftUI overlay both want first-responder, and the
        // panel will land in front cleanly if our overlay is gone.
        let host = workspace.rootNode?.url
        onClose()
        DispatchQueue.main.async {
            switch cmd {
            case .newFile:   runNewFile(under: host)
            case .newFolder: runNewFolder(under: host)
            }
        }
    }

    private func runNewFile(under defaultDir: URL?) {
        let panel = NSSavePanel()
        panel.title = "New File"
        panel.prompt = "Create"
        panel.canCreateDirectories = true
        panel.directoryURL = defaultDir
        panel.nameFieldStringValue = "untitled.txt"
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            reloadTree(containing: url)
            onJump(url, nil)
        } catch {
            warn("Couldn't create file: \(error.localizedDescription)")
        }
    }

    private func runNewFolder(under defaultDir: URL?) {
        let panel = NSOpenPanel()
        panel.title = "Choose Parent Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultDir
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        // FileOperations.createFolder shows a name-prompt alert and
        // surfaces its own error sheet if the create fails.
        guard let created = FileOperations.createFolder(in: parent) else { return }
        reloadTree(containing: created)
    }

    private func warn(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Reload the file-tree branch containing `url` so the new entry
    /// appears in the sidebar. Walks the in-memory FileNode tree to find
    /// the parent and asks it to re-read its children.
    private func reloadTree(containing url: URL) {
        let parent = url.deletingLastPathComponent()
        if let node = findNode(workspace.rootNode, matching: parent) {
            node.reloadChildren()
        } else {
            workspace.rootNode?.reloadChildren()
        }
    }

    private func findNode(_ node: FileNode?, matching url: URL) -> FileNode? {
        guard let node else { return nil }
        if node.url.standardizedFileURL == url.standardizedFileURL { return node }
        for child in (node.children ?? []) {
            if let m = findNode(child, matching: url) { return m }
        }
        return nil
    }

    // MARK: - Computation

    private func recompute() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        // "." enters folder-browse mode. Subsequent character changes —
        // even non-empty — exit it (the user is back to typing a query).
        if trimmed == "." {
            if browseURL == nil { browseURL = workspace.rootNode?.url }
            results = browseResults()
            return
        }
        if browseURL != nil { browseURL = nil }

        if trimmed.isEmpty {
            results = recentResults()
            return
        }

        var combined: [ZenSearchResult] = []
        combined.append(contentsOf: commandResults(query: trimmed))
        combined.append(contentsOf: filenameResults(query: trimmed))
        combined.append(contentsOf: inFileResults(query: trimmed))
        results = combined
    }

    /// Match `query` against each command's keywords + title. A command
    /// is included when every word in the query is found somewhere in
    /// the keyword list or the title.
    private func commandResults(query: String) -> [ZenSearchResult] {
        let words = query.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !words.isEmpty else { return [] }
        return ZenCommand.allCases.compactMap { cmd in
            let titleLower = cmd.title.lowercased()
            let allWordsMatch = words.allSatisfy { word in
                titleLower.contains(word) ||
                cmd.keywords.contains(where: { $0.contains(word) })
            }
            guard allWordsMatch else { return nil }
            return ZenSearchResult(
                id: "cmd-\(cmd.rawValue)",
                kind: .command(cmd),
                title: cmd.title,
                subtitle: cmd.subtitle
            )
        }
    }

    /// Children of `browseURL`, with a `..` entry on top whenever we're
    /// not at the workspace root. Folders sort before files.
    private func browseResults() -> [ZenSearchResult] {
        guard let url = browseURL else { return [] }
        var rows: [ZenSearchResult] = []

        if let rootURL = workspace.rootNode?.url, url.standardizedFileURL != rootURL.standardizedFileURL {
            let parent = url.deletingLastPathComponent()
            rows.append(ZenSearchResult(
                id: "browse-up-\(parent.path)",
                kind: .parentFolder(parent),
                title: "..",
                subtitle: relativeSubtitle(for: parent)
            ))
        }

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        } catch {
            return rows
        }

        let sorted = entries.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
        }

        for entry in sorted {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            // Hide the workspace's own .minimal directory while browsing —
            // it's an implementation detail, not user content. Other
            // dotfiles stay (browsing is the natural place to reach them).
            if entry.lastPathComponent == ".minimal" { continue }
            rows.append(ZenSearchResult(
                id: "browse-\(isDir ? "dir" : "file")-\(entry.path)",
                kind: isDir ? .folder(entry) : .file(entry),
                title: entry.lastPathComponent,
                subtitle: isDir ? "Folder" : relativeSubtitle(for: entry)
            ))
        }
        return rows
    }

    private func browseSubtitle(for url: URL) -> String {
        guard let root = workspace.rootNode?.url else { return url.path }
        let rootPath = root.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath == rootPath { return root.lastPathComponent + "/" }
        if urlPath.hasPrefix(rootPath + "/") {
            return root.lastPathComponent + "/" + String(urlPath.dropFirst(rootPath.count + 1)) + "/"
        }
        return url.path
    }

    private func recentResults() -> [ZenSearchResult] {
        let urls = workspace.recentURLs.prefix(5)
        return urls.map { url in
            ZenSearchResult(
                id: "recent-\(url.path)",
                kind: .recent(url),
                title: url.lastPathComponent,
                subtitle: relativeSubtitle(for: url)
            )
        }
    }

    private func filenameResults(query: String, limit: Int = 8) -> [ZenSearchResult] {
        guard let root = workspace.rootNode else { return [] }
        let needle = query.lowercased()
        var candidates: [URL] = []
        collect(node: root, into: &candidates)
        let matches = candidates.filter {
            $0.lastPathComponent.lowercased().contains(needle)
        }
        // Prefer matches where the name *starts* with the query.
        let ranked = matches.sorted { a, b in
            let ah = a.lastPathComponent.lowercased().hasPrefix(needle)
            let bh = b.lastPathComponent.lowercased().hasPrefix(needle)
            if ah != bh { return ah }
            return a.lastPathComponent.count < b.lastPathComponent.count
        }
        return ranked.prefix(limit).map { url in
            ZenSearchResult(
                id: "file-\(url.path)",
                kind: .file(url),
                title: url.lastPathComponent,
                subtitle: relativeSubtitle(for: url)
            )
        }
    }

    private func collect(node: FileNode, into bucket: inout [URL]) {
        if node.isDirectory {
            // Skip hidden + workspace-internal dirs at the top level —
            // ".minimal", ".git", etc. don't deserve to clog results.
            if node.name.hasPrefix(".") { return }
            for child in (node.children ?? []) { collect(node: child, into: &bucket) }
        } else {
            if node.name.hasPrefix(".") { return }
            bucket.append(node.url)
        }
    }

    private func inFileResults(query: String, limit: Int = 6) -> [ZenSearchResult] {
        guard let active = workspace.activeDocument else { return [] }
        let needle = query.lowercased()
        let lines = active.text.components(separatedBy: "\n")
        var hits: [ZenSearchResult] = []
        for (i, line) in lines.enumerated() {
            guard line.lowercased().contains(needle) else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            hits.append(ZenSearchResult(
                id: "inline-\(active.url.path)-\(i)",
                kind: .inFile(active.url, line: i + 1),
                title: trimmed.isEmpty ? "(empty line)" : trimmed,
                subtitle: "\(active.displayName) · line \(i + 1)"
            ))
            if hits.count >= limit { break }
        }
        return hits
    }

    private func relativeSubtitle(for url: URL) -> String {
        guard let root = workspace.rootNode?.url else { return url.path }
        let rootPath = root.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        if urlPath.hasPrefix(rootPath + "/") {
            return String(urlPath.dropFirst(rootPath.count + 1))
        }
        return url.path
    }
}

// MARK: - Palette surface

/// Renders the palette's panel — uses macOS Tahoe's Liquid Glass with full
/// refraction when the user has Glass mode on, and falls back to the
/// regular material treatment otherwise. Either way the corner radius,
/// border, and drop shadow stay consistent.
private struct PaletteSurface: ViewModifier {
    let useGlass: Bool

    private static let cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        if useGlass {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
                .shadow(color: .black.opacity(0.30), radius: 28, x: 0, y: 10)
        } else {
            content
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.30), radius: 28, x: 0, y: 10)
        }
    }
}

// MARK: - Result model + row

struct ZenSearchResult: Identifiable, Hashable {
    enum Kind: Hashable {
        case file(URL)
        case inFile(URL, line: Int)
        case recent(URL)
        /// Browse-mode entry: navigate into this folder.
        case folder(URL)
        /// Browse-mode entry: navigate up to this folder.
        case parentFolder(URL)
        /// Action / command — runs an effect when activated.
        case command(ZenCommand)
    }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
}

/// The set of palette-invocable commands. Add cases here to grow the
/// "command palette" surface; `keywords` controls how the typed query
/// matches against each command.
enum ZenCommand: String, CaseIterable, Hashable {
    case newFile
    case newFolder

    var title: String {
        switch self {
        case .newFile:   return "New File…"
        case .newFolder: return "New Folder…"
        }
    }

    var subtitle: String {
        switch self {
        case .newFile:   return "Create a new file in any folder"
        case .newFolder: return "Create a new folder under the workspace"
        }
    }

    var icon: String {
        switch self {
        case .newFile:   return "doc.badge.plus"
        case .newFolder: return "folder.badge.plus"
        }
    }

    var keywords: [String] {
        switch self {
        case .newFile:   return ["new", "create", "file", "make"]
        case .newFolder: return ["new", "create", "folder", "directory", "dir", "make"]
        }
    }
}

private struct ResultRow: View {
    let result: ZenSearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(result.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if case .recent = result.kind {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    @ViewBuilder
    private var iconView: some View {
        switch result.kind {
        case .file(let url), .recent(let url):
            FileIcon(isDirectory: false, isOpen: false, url: url)
        case .inFile:
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        case .folder(let url):
            FileIcon(isDirectory: true, isOpen: false, url: url)
        case .parentFolder:
            Image(systemName: "arrow.up.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        case .command(let cmd):
            Image(systemName: cmd.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}
