import Foundation

/// Pure file-system operations behind the sidebar's context menu, shared
/// by both front ends. Everything here is UI-free: the apps own the
/// name prompts, confirmations, and error alerts, and each platform
/// supplies its own "move to trash" (Finder's trash / GIO's trash).
public enum FileOps {

    public enum OpError: Error, LocalizedError {
        case alreadyExists(String)
        case invalidName
        case notPermitted(String)
        case underlying(String)

        public var errorDescription: String? {
            switch self {
            case .alreadyExists(let name): "A file or folder named “\(name)” already exists."
            case .invalidName: "That name isn't valid."
            case .notPermitted(let reason): reason
            case .underlying(let message): message
            }
        }
    }

    // MARK: - Create

    /// Create an empty file named `name` inside `parent`.
    @discardableResult
    public static func createFile(named name: String, in parent: URL) throws -> URL {
        let target = try validated(name: name, in: parent)
        do {
            try "".write(to: target, atomically: true, encoding: .utf8)
        } catch {
            throw OpError.underlying(error.localizedDescription)
        }
        return target
    }

    @discardableResult
    public static func createFolder(named name: String, in parent: URL) throws -> URL {
        let target = try validated(name: name, in: parent)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        } catch {
            throw OpError.underlying(error.localizedDescription)
        }
        return target
    }

    // MARK: - Rename / duplicate

    /// Rename `url` in place. Returns the new URL, or `url` itself when
    /// the name is unchanged.
    @discardableResult
    public static func rename(_ url: URL, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { throw OpError.invalidName }
        let target = url.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard target.standardizedFileURL != url.standardizedFileURL else { return url }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw OpError.alreadyExists(trimmed)
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            throw OpError.underlying(error.localizedDescription)
        }
        return target
    }

    /// Duplicate a file or folder, appending " copy" (or " copy 2", …)
    /// before the extension to avoid collisions.
    @discardableResult
    public static func duplicate(_ url: URL) throws -> URL {
        let parent = url.deletingLastPathComponent()
        let target = uniqueDestination(for: url.lastPathComponent, in: parent, forceSuffix: true)
        do {
            try FileManager.default.copyItem(at: url, to: target)
        } catch {
            throw OpError.underlying(error.localizedDescription)
        }
        return target
    }

    // MARK: - Copy / move

    /// Copy `source` into `destinationFolder`, auto-renaming on collision.
    @discardableResult
    public static func copy(_ source: URL, into destinationFolder: URL) throws -> URL {
        let target = uniqueDestination(for: source.lastPathComponent, in: destinationFolder)
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            throw OpError.underlying(error.localizedDescription)
        }
        return target
    }

    /// Move `source` into `destinationFolder`. Returns `source` unchanged
    /// when it already lives there. Refuses to move a folder into itself
    /// or one of its own descendants.
    @discardableResult
    public static func move(_ source: URL, into destinationFolder: URL) throws -> URL {
        let std = source.standardizedFileURL
        let destination = destinationFolder.standardizedFileURL
        // Compare paths, not URLs: `deletingLastPathComponent()` leaves a
        // trailing slash that makes two URLs for the same directory differ.
        if std.deletingLastPathComponent().path == destination.path { return source }
        if destination.path == std.path || destination.path.hasPrefix(std.path + "/") {
            throw OpError.notPermitted("Can't move a folder inside itself.")
        }
        let target = destination.appendingPathComponent(source.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw OpError.alreadyExists(source.lastPathComponent)
        }
        do {
            try FileManager.default.moveItem(at: source, to: target)
        } catch {
            throw OpError.underlying(error.localizedDescription)
        }
        return target
    }

    // MARK: - Helpers

    /// A URL inside `folder` that doesn't collide with an existing entry,
    /// appending " copy" / " copy N" before the extension as needed.
    /// `forceSuffix` skips the plain name (used by Duplicate, where the
    /// original always exists).
    public static func uniqueDestination(
        for filename: String,
        in folder: URL,
        forceSuffix: Bool = false
    ) -> URL {
        let initial = folder.appendingPathComponent(filename)
        if !forceSuffix, !FileManager.default.fileExists(atPath: initial.path) { return initial }

        let nsName = filename as NSString
        let ext = nsName.pathExtension
        let base = nsName.deletingPathExtension
        var attempt = 0
        while attempt < 1_000 {
            attempt += 1
            let suffix = attempt == 1 ? " copy" : " copy \(attempt)"
            var candidate = folder.appendingPathComponent(base + suffix)
            if !ext.isEmpty { candidate.appendPathExtension(ext) }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return initial
    }

    /// Whether `url` points at a directory on disk.
    public static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func validated(name: String, in parent: URL) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/") else { throw OpError.invalidName }
        let target = parent.appendingPathComponent(trimmed)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw OpError.alreadyExists(trimmed)
        }
        return target
    }
}
