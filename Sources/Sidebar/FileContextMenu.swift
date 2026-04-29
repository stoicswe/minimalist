import SwiftUI

/// Right-click menu items shared by the sidebar's directory and file rows.
/// Wired through closures so the same menu structure can act on either a
/// folder (parent for new items) or a file (target for rename/duplicate).
struct FileContextMenu: View {
    enum Target { case file(URL), folder(URL) }

    let target: Target
    let workspace: Workspace
    @Binding var historyContext: HistoryContext?

    var body: some View {
        Group {
            // New file / new folder always make sense — for a folder
            // target the parent is the folder; for a file target the
            // parent is the file's enclosing folder.
            Button("New File…") {
                let parent = parentURL
                if let url = FileOperations.createFile(in: parent) {
                    refreshTree(after: url)
                    workspace.openPreview(url: url)
                }
            }
            Button("New Folder…") {
                let parent = parentURL
                if FileOperations.createFolder(in: parent) != nil {
                    refreshTree(after: parent)
                }
            }

            Divider()

            Button("Rename…") {
                guard let new = FileOperations.rename(targetURL) else { return }
                refreshTree(after: new)
            }
            Button("Duplicate") {
                guard let copy = FileOperations.duplicate(targetURL) else { return }
                refreshTree(after: copy)
            }

            Divider()

            Button("Copy") { FileOperations.copyToPasteboard(targetURL) }
            Button("Paste") {
                let parent = parentURL
                _ = FileOperations.pasteFromPasteboard(into: parent)
                refreshTree(after: parent)
            }
            .disabled(!FileOperations.pasteboardHasFile)

            Divider()

            Button("Reveal in Finder") { FileOperations.revealInFinder(targetURL) }

            Divider()

            Button("Delete…", role: .destructive) {
                let url = targetURL
                guard FileOperations.confirmDelete(url) else { return }
                if FileOperations.moveToTrash(url) {
                    workspace.purgeTabs(under: url)
                    refreshTree(after: url)
                }
            }

            // History entries — only meaningful for files.
            if case .file = target {
                Divider()
                Button("Show Revision History…") {
                    historyContext = .revisions(targetURL)
                }
                Button("Show Commit History…") {
                    historyContext = .commits(targetURL)
                }
            }
        }
    }

    private var targetURL: URL {
        switch target {
        case .file(let url): return url
        case .folder(let url): return url
        }
    }

    private var parentURL: URL {
        switch target {
        case .file(let url): return url.deletingLastPathComponent()
        case .folder(let url): return url
        }
    }

    /// After a file-system change, reload the affected branch of the tree
    /// and open the new file if one was created.
    private func refreshTree(after url: URL) {
        let parent = url.deletingLastPathComponent()
        guard let root = workspace.rootNode else { return }
        if let node = findNode(matching: parent, under: root) {
            node.reloadChildren()
        } else {
            // Fallback: reload root.
            root.reloadChildren()
        }
    }

    private func findNode(matching url: URL, under node: FileNode) -> FileNode? {
        if node.url.standardizedFileURL == url.standardizedFileURL { return node }
        for child in (node.children ?? []) {
            if let match = findNode(matching: url, under: child) { return match }
        }
        return nil
    }
}

/// Pushed into a binding so a parent view can present a sheet for either
/// the per-file revision viewer (`.minimal` tracking) or the repository's
/// commit log.
enum HistoryContext: Identifiable {
    case revisions(URL)
    case commits(URL)

    var id: String {
        switch self {
        case .revisions(let url): return "revisions-\(url.path)"
        case .commits(let url): return "commits-\(url.path)"
        }
    }

    var url: URL {
        switch self {
        case .revisions(let url), .commits(let url): return url
        }
    }
}
