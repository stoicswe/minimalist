import Foundation

@MainActor
final class FileNode: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    @Published var children: [FileNode]?

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    var name: String { url.lastPathComponent }

    /// Force-reload this node's children from disk. Used after file
    /// operations (new / rename / duplicate / paste) so the sidebar
    /// reflects the change.
    func reloadChildren() {
        children = nil
        loadChildrenIfNeeded()
    }

    func loadChildrenIfNeeded() {
        guard isDirectory, children == nil else { return }
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        } catch {
            children = []
            return
        }

        children = urls
            // Hide our internal revision-tracking folder from the tree —
            // the user shouldn't have to look at or edit `.minimal/`.
            .filter { $0.lastPathComponent != ".minimal" }
            .map { url -> FileNode in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                return FileNode(url: url, isDirectory: values?.isDirectory ?? false)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }
}
