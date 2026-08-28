import Foundation
import Observation

@MainActor
@Observable
public final class FileNode: Identifiable {
    public let id = UUID()
    public let url: URL
    public let isDirectory: Bool
    public var children: [FileNode]?

    public init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    public var name: String { url.lastPathComponent }

    /// Force-reload this node's children from disk. Used after file
    /// operations (new / rename / duplicate / paste) so the sidebar
    /// reflects the change.
    public func reloadChildren() {
        children = nil
        loadChildrenIfNeeded()
    }

    public func loadChildrenIfNeeded() {
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
