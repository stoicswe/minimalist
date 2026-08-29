import Adwaita
import Foundation
import MinimalistCore

extension MainView {

    @ViewBuilder var sidebar: Body {
        VStack {
            projectHeader
            ScrollView {
                if rows.isEmpty {
                    StatusPage(
                        folderName.isEmpty ? "No Folder Open" : "Empty Folder",
                        icon: .custom(name: "folder-symbolic"),
                        description: folderName.isEmpty
                            ? "Open a folder to browse it here"
                            : "Nothing to show yet"
                    )
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
        .fileDropTarget { urls in
            copyIntoWorkspace(urls, target: nil)
        }
    }

    /// Files dropped from another app are copied in, matching the macOS
    /// sidebar's external-drop behavior. `target` is the row they landed
    /// on — a folder receives them, a file's folder does.
    func copyIntoWorkspace(_ urls: [URL]?, target: String?) {
        guard let urls, !urls.isEmpty else { return }
        let destination: URL? = onMain {
            guard let root = DocumentStore.shared.folderURL else { return nil }
            guard let target, !target.isEmpty else { return root }
            let url = URL(fileURLWithPath: target)
            return FileOps.isDirectory(url) ? url : url.deletingLastPathComponent()
        }
        guard let destination else {
            report("Open a folder before dropping files into it.")
            return
        }
        for url in urls {
            do {
                _ = try FileOps.copy(url, into: destination)
            } catch {
                report(error.localizedDescription)
                return
            }
        }
        onMain { DocumentStore.shared.reloadTree(folder: destination) }
        refreshRows()
    }

    /// Folder name · branch pill, mirroring the macOS TopBar.
    @ViewBuilder var projectHeader: Body {
        HStack(spacing: 8) {
            Text(folderName.isEmpty ? "{m.txt}" : folderName)
                .ellipsize()
                .heading()
            if !branch.isEmpty {
                Text("·")
                    .dimLabel()
                branchButton
            }
        }
        .halign(.start)
        .padding(12)
    }

    @ViewBuilder var branchButton: Body {
        Menu(branch, icon: .custom(name: "media-playlist-shuffle-symbolic")) {
            MenuSection {
                ForEach(onMain { DocumentStore.shared.branches() }.map { Choice(id: $0) }) { item in
                    MenuButton(item.id == branch ? "● \(item.id)" : item.id) { checkout(item.id) }
                }
            }
            MenuSection {
                MenuButton("New Branch…") {
                    newBranchName = ""
                    newBranchVisible = true
                }
            }
        }
        .flat()
        .style("branch-pill")
        .tooltip("Current branch")
    }

    @ViewBuilder func rowView(_ row: FileRow) -> Body {
        Button(row.name) { rowTapped(row) }
            .child {
                HStack(spacing: 6) {
                    if row.isDirectory {
                        Image()
                            .iconName(row.isExpanded ? "pan-down-symbolic" : "pan-end-symbolic")
                            .dimLabel()
                        Image()
                            .iconName("folder-symbolic")
                            .style("folder-icon")
                    } else {
                        fileBadge(for: row.name)
                    }
                    Text(row.name)
                        .ellipsize()
                        .dimLabel(row.isHidden)
                }
                .halign(.start)
                .padding(row.depth * 14, [.leading])
            }
            .flat()
            .style("tree-row")
            .style("row-active", active: !row.isDirectory && row.id == activeTabID)
            .inspect { storage, _ in
                installContextMenu(storage, rowID: row.id)
                installPin(storage, rowID: row.id)
            }
            .popover(
                visible: .init { showContextMenu && contextRowID == row.id } set: { showContextMenu = $0 }
            ) {
                contextMenu
            }
            .fileDropTarget { urls in
                copyIntoWorkspace(urls, target: row.id)
            }
    }

    /// The colored monogram chip the macOS sidebar draws for each file.
    @ViewBuilder func fileBadge(for name: String) -> Body {
        let badge = FileTypeBadge.badge(forName: name)
        Text(badge.letter.isEmpty ? "·" : badge.letter)
            .style("file-badge")
            .style("badge-\(badge.hex.dropFirst())")
    }

    @ViewBuilder var contextMenu: Body {
        VStack(spacing: 2) {
            contextItem("New File…", icon: "document-new-symbolic") { promptName(.newFile) }
            contextItem("New Folder…", icon: "folder-new-symbolic") { promptName(.newFolder) }
            Separator()
            contextItem("Rename…", icon: "document-edit-symbolic") { promptName(.rename) }
            contextItem("Duplicate", icon: "edit-copy-symbolic") { duplicateContextTarget() }
            contextItem("Copy Path", icon: "edit-copy-symbolic") { copyContextPath() }
            contextItem("Open Folder", icon: "folder-open-symbolic") { revealContextTarget() }
            Separator()
            contextItem("Show Revision History…", icon: "document-open-recent-symbolic") {
                openRevisionHistory(for: contextRowID)
            }
            contextItem("Show Commit History…", icon: "media-playlist-shuffle-symbolic") {
                openCommitHistory(for: contextRowID)
            }
            Separator()
            contextItem("Delete…", icon: "user-trash-symbolic", destructive: true) {
                showContextMenu = false
                deleteVisible = true
            }
        }
        .padding(4)
        .frame(maxWidth: 240)
    }

    @ViewBuilder func contextItem(
        _ label: String,
        icon: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> Body {
        Button(label) {
            showContextMenu = false
            action()
        }
        .child {
            HStack(spacing: 8) {
                Image()
                    .iconName(icon)
                    .dimLabel()
                Text(label)
            }
            .halign(.start)
        }
        .flat()
        .destructive(destructive)
        .style("menu-item")
    }

    /// A `ForEach`- and `ComboRow`-friendly wrapper for plain strings.
    struct Choice: Identifiable, Equatable, CustomStringConvertible {
        let id: String
        var description: String { id }
    }
}
