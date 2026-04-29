import SwiftUI
import UniformTypeIdentifiers

struct FileTreeView: View {
    @EnvironmentObject var workspace: Workspace
    @State private var historyContext: HistoryContext?
    @State private var isRootDropTarget = false
    /// URL of the row that's currently the target of an open context menu —
    /// drawn with an accent outline. Cleared when the menu finishes
    /// tracking (NSMenu.didEndTrackingNotification).
    @State private var rightClickedURL: URL?

    var body: some View {
        Group {
            if let root = workspace.rootNode {
                GeometryReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            FolderRowList(
                                node: root,
                                depth: 0,
                                expandedByDefault: true,
                                historyContext: $historyContext,
                                rightClickedURL: $rightClickedURL
                            )
                            // Trailing spacer that always fills the rest
                            // of the viewport so right-clicks anywhere
                            // below the last row land on the root menu.
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: max(80, proxy.size.height))
                                .contentShape(Rectangle())
                                .contextMenu {
                                    rootContextMenu(for: root.url)
                                }
                        }
                        .padding(.vertical, 6)
                    }
                    .scrollContentBackground(.hidden)
                    .background(
                        Color.accentColor
                            .opacity(isRootDropTarget ? 0.10 : 0)
                            .allowsHitTesting(false)
                    )
                    .onDrop(of: [.fileURL], isTargeted: $isRootDropTarget) { providers in
                        handleRootDrop(providers: providers, into: root.url)
                    }
                }
            } else {
                EmptySidebar()
            }
        }
        .sheet(item: $historyContext) { ctx in
            switch ctx {
            case .revisions(let url):
                RevisionHistoryView(url: url, workspace: workspace)
            case .commits(let url):
                CommitHistoryView(url: url, workspace: workspace)
            }
        }
        // Clear the right-click outline once the contextual menu is dismissed.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            rightClickedURL = nil
        }
    }

    @ViewBuilder
    private func rootContextMenu(for root: URL) -> some View {
        Button("New File…") {
            if let url = FileOperations.createFile(in: root) {
                workspace.rootNode?.reloadChildren()
                workspace.openPreview(url: url)
            }
        }
        Button("New Folder…") {
            if FileOperations.createFolder(in: root) != nil {
                workspace.rootNode?.reloadChildren()
            }
        }
    }

    private func handleRootDrop(providers: [NSItemProvider], into root: URL) -> Bool {
        var accepted = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = resolveDroppedURL(from: item) else { return }
                DispatchQueue.main.async {
                    let isInternal = isURL(url, inside: root)
                    if isInternal {
                        guard let moved = FileOperations.move(url, into: root) else { return }
                        workspace.reflectMove(from: url, to: moved)
                        if let parentNode = findNode(
                            matching: url.deletingLastPathComponent(),
                            under: workspace.rootNode
                        ) {
                            parentNode.reloadChildren()
                        }
                    } else {
                        guard FileOperations.copy(url, into: root) != nil else { return }
                    }
                    workspace.rootNode?.reloadChildren()
                }
            }
        }
        return accepted
    }
}

private struct EmptySidebar: View {
    @EnvironmentObject var workspace: Workspace
    var body: some View {
        VStack(spacing: 12) {
            Text("No folder open")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Open Folder") { workspace.openFolder() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FolderRowList: View {
    @EnvironmentObject var workspace: Workspace
    @ObservedObject var node: FileNode
    let depth: Int
    let expandedByDefault: Bool
    @Binding var historyContext: HistoryContext?
    @Binding var rightClickedURL: URL?
    @AppStorage(PreferenceKeys.accentPresetID)
    private var rightClickAccentID: String = AccentPresets.defaultID

    @State private var expanded: Bool = false
    @State private var loaded: Bool = false

    @State private var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            DirectoryRow(node: node, depth: depth, expanded: $expanded, dropHighlight: isDropTarget)
                .overlay(rightClickOutline(for: node.url))
                .background(RightClickReporter { rightClickedURL = node.url })
                .contextMenu {
                    FileContextMenu(
                        target: .folder(node.url),
                        workspace: workspace,
                        historyContext: $historyContext
                    )
                }
                .onTapGesture {
                    expanded.toggle()
                    if expanded && !loaded {
                        node.loadChildrenIfNeeded()
                        loaded = true
                    }
                }
                .onDrag {
                    NSItemProvider(object: node.url as NSURL)
                }
                .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
                    handleDrop(providers: providers, into: node.url)
                }

            if expanded, let children = node.children {
                ForEach(children) { child in
                    if child.isDirectory {
                        FolderRowList(
                            node: child,
                            depth: depth + 1,
                            expandedByDefault: false,
                            historyContext: $historyContext,
                            rightClickedURL: $rightClickedURL
                        )
                    } else {
                        FileRow(
                            node: child,
                            depth: depth + 1,
                            historyContext: $historyContext,
                            rightClickedURL: $rightClickedURL
                        )
                    }
                }
            }
        }
        .onAppear {
            if expandedByDefault && !loaded {
                expanded = true
                node.loadChildrenIfNeeded()
                loaded = true
            }
        }
    }

    @ViewBuilder
    private func rightClickOutline(for url: URL) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(AccentPresets.preset(forID: rightClickAccentID).color, lineWidth: 1.5)
            .opacity(rightClickedURL == url ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func handleDrop(providers: [NSItemProvider], into folder: URL) -> Bool {
        var accepted = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = resolveDroppedURL(from: item) else { return }
                DispatchQueue.main.async {
                    let workspaceRoot = workspace.rootNode?.url
                    let isInternal = workspaceRoot.map { isURL(url, inside: $0) } ?? false
                    if isInternal {
                        guard let moved = FileOperations.move(url, into: folder) else { return }
                        workspace.reflectMove(from: url, to: moved)
                        if let parentNode = findNode(matching: url.deletingLastPathComponent(),
                                                     under: workspace.rootNode) {
                            parentNode.reloadChildren()
                        }
                    } else {
                        guard FileOperations.copy(url, into: folder) != nil else { return }
                    }
                    node.reloadChildren()
                    if !expanded {
                        expanded = true
                        if !loaded {
                            node.loadChildrenIfNeeded()
                            loaded = true
                        }
                    }
                }
            }
        }
        return accepted
    }
}

/// True when `url` lives at or below `root`.
private func isURL(_ url: URL, inside root: URL) -> Bool {
    let urlPath = url.standardizedFileURL.path
    let rootPath = root.standardizedFileURL.path
    return urlPath == rootPath || urlPath.hasPrefix(rootPath + "/")
}

/// Walk a tree to find a node whose URL matches `url`.
@MainActor
private func findNode(matching url: URL, under node: FileNode?) -> FileNode? {
    guard let node else { return nil }
    if node.url.standardizedFileURL == url.standardizedFileURL { return node }
    for child in (node.children ?? []) {
        if let match = findNode(matching: url, under: child) { return match }
    }
    return nil
}

/// NSItemProvider hands fileURL items back as Data, NSURL, or URL
/// depending on the source. Normalize to URL.
private func resolveDroppedURL(from item: Any?) -> URL? {
    if let url = item as? URL { return url }
    if let url = item as? NSURL { return url as URL }
    if let data = item as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)
    }
    return nil
}

private struct DirectoryRow: View {
    @ObservedObject var node: FileNode
    let depth: Int
    @Binding var expanded: Bool
    var dropHighlight: Bool = false

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            FileIcon(isDirectory: true, isOpen: expanded, url: node.url)
                .frame(width: 16, height: 16)
            Text(node.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 12 + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .opacity(node.name.hasPrefix(".") ? 0.50 : 1)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if dropHighlight {
            Color.accentColor.opacity(0.18)
        } else if hovering {
            Color.primary.opacity(0.05)
        } else {
            Color.clear
        }
    }
}

private struct FileRow: View {
    @EnvironmentObject var workspace: Workspace
    @ObservedObject var node: FileNode
    let depth: Int
    @Binding var historyContext: HistoryContext?
    @Binding var rightClickedURL: URL?
    @AppStorage(PreferenceKeys.accentPresetID)
    private var rightClickAccentID: String = AccentPresets.defaultID

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 10)
            FileIcon(isDirectory: false, isOpen: false, url: node.url)
                .frame(width: 16, height: 16)
            Text(node.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 12 + 8)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .opacity(node.name.hasPrefix(".") ? 0.50 : 1)
        .background(rowBackground)
        .background(RightClickReporter { rightClickedURL = node.url })
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(AccentPresets.preset(forID: rightClickAccentID).color, lineWidth: 1.5)
                .opacity(rightClickedURL == node.url ? 1 : 0)
                .allowsHitTesting(false)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { workspace.open(url: node.url) }
        .onTapGesture(count: 1) { workspace.openPreview(url: node.url) }
        .contextMenu {
            FileContextMenu(
                target: .file(node.url),
                workspace: workspace,
                historyContext: $historyContext
            )
        }
        .onDrag {
            NSItemProvider(object: node.url as NSURL)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        let isActive = workspace.activeDocument?.url == node.url
        if isActive {
            Color.primary.opacity(0.08)
        } else if hovering {
            Color.primary.opacity(0.05)
        } else {
            Color.clear
        }
    }
}

/// Invisible NSView that fires a callback when a right-click lands inside
/// its frame, without consuming the event — so SwiftUI's `.contextMenu`
/// still opens. Used to capture *which* row was the target so we can draw
/// an outline around it.
private struct RightClickReporter: NSViewRepresentable {
    var onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ReporterView()
        view.callback = onRightClick
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ReporterView)?.callback = onRightClick
    }

    final class ReporterView: NSView {
        var callback: (() -> Void)?
        private var monitor: Any?

        // Stay out of the responder chain entirely so taps & right-clicks
        // hit the SwiftUI row underneath us. We only listen via the
        // window-level NSEvent monitor below.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self,
                      let window = self.window,
                      event.window === window
                else { return event }
                let pt = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(pt) {
                    self.callback?()
                }
                return event
            }
        }

        deinit { removeMonitor() }

        private func removeMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }
    }
}

