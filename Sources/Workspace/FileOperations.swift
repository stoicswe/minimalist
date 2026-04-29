import Foundation
import AppKit

/// File-system operations triggered from the sidebar context menu.
/// All operations show an `NSAlert` if they fail, since the user invoked
/// them explicitly and a silent failure would be confusing.
enum FileOperations {
    // MARK: - Create

    /// Create an empty file in `parent`. Prompts for a name. If the file
    /// already exists, prompts again. Returns the new file's URL on
    /// success, nil if cancelled.
    @discardableResult
    static func createFile(in parent: URL) -> URL? {
        guard let name = promptForName(
            title: "New File",
            message: "Name the new file:",
            defaultValue: "untitled.txt"
        ) else { return nil }
        let target = parent.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) {
            showAlert(message: "A file or folder named “\(name)” already exists.")
            return nil
        }
        do {
            try "".write(to: target, atomically: true, encoding: .utf8)
            return target
        } catch {
            showAlert(message: "Couldn't create file: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    static func createFolder(in parent: URL) -> URL? {
        guard let name = promptForName(
            title: "New Folder",
            message: "Name the new folder:",
            defaultValue: "untitled folder"
        ) else { return nil }
        let target = parent.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) {
            showAlert(message: "A file or folder named “\(name)” already exists.")
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            return target
        } catch {
            showAlert(message: "Couldn't create folder: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Rename / duplicate

    @discardableResult
    static func rename(_ url: URL) -> URL? {
        guard let newName = promptForName(
            title: "Rename",
            message: "New name:",
            defaultValue: url.lastPathComponent
        ) else { return nil }
        let target = url.deletingLastPathComponent().appendingPathComponent(newName)
        guard target != url else { return nil }
        if FileManager.default.fileExists(atPath: target.path) {
            showAlert(message: "“\(newName)” already exists.")
            return nil
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            showAlert(message: "Couldn't rename: \(error.localizedDescription)")
            return nil
        }
    }

    /// Duplicate a file or folder, appending " copy" (or " copy 2", etc.)
    /// before the extension to avoid collisions.
    @discardableResult
    static func duplicate(_ url: URL) -> URL? {
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let parent = url.deletingLastPathComponent()
        var attempt = 0
        var target: URL
        repeat {
            attempt += 1
            let suffix = attempt == 1 ? " copy" : " copy \(attempt)"
            let candidateName = base + suffix
            target = parent.appendingPathComponent(candidateName)
            if !ext.isEmpty {
                target.appendPathExtension(ext)
            }
        } while FileManager.default.fileExists(atPath: target.path) && attempt < 100
        do {
            try FileManager.default.copyItem(at: url, to: target)
            return target
        } catch {
            showAlert(message: "Couldn't duplicate: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Copy / paste

    /// Put a file URL on the general pasteboard for later paste.
    static func copyToPasteboard(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([url as NSURL])
    }

    /// Read file URLs off the pasteboard and copy each into `parent`.
    /// Returns the new URLs created.
    @discardableResult
    static func pasteFromPasteboard(into parent: URL) -> [URL] {
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        else { return [] }
        var created: [URL] = []
        for src in urls {
            var target = parent.appendingPathComponent(src.lastPathComponent)
            // Avoid collision by appending " copy" if needed.
            if FileManager.default.fileExists(atPath: target.path) {
                let ext = target.pathExtension
                let base = target.deletingPathExtension().lastPathComponent
                target = parent
                    .appendingPathComponent(base + " copy")
                if !ext.isEmpty { target.appendPathExtension(ext) }
            }
            do {
                try FileManager.default.copyItem(at: src, to: target)
                created.append(target)
            } catch {
                showAlert(message: "Couldn't paste \(src.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return created
    }

    /// Whether the pasteboard currently holds at least one file URL we
    /// could paste. Used to enable/disable the menu item.
    static var pasteboardHasFile: Bool {
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        else { return false }
        return !urls.isEmpty
    }

    // MARK: - Reveal in Finder

    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Copy

    /// Copy `source` into `destinationFolder`. On collision auto-appends
    /// " copy", " copy 2", etc. before the extension. Returns the new
    /// URL on success, nil on failure.
    @discardableResult
    static func copy(_ source: URL, into destinationFolder: URL) -> URL? {
        let target = uniqueDestination(
            for: source.lastPathComponent,
            in: destinationFolder
        )
        do {
            try FileManager.default.copyItem(at: source, to: target)
            return target
        } catch {
            showAlert(message: "Couldn't copy: \(error.localizedDescription)")
            return nil
        }
    }

    /// Find a destination URL inside `folder` that doesn't collide with
    /// an existing entry. Splits the file's basename + extension and
    /// appends " copy" / " copy N" before the extension as needed.
    private static func uniqueDestination(for filename: String, in folder: URL) -> URL {
        let initial = folder.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: initial.path) { return initial }

        let nsName = filename as NSString
        let ext = nsName.pathExtension
        let base = nsName.deletingPathExtension
        var attempt = 0
        while attempt < 1000 {
            attempt += 1
            let suffix = attempt == 1 ? " copy" : " copy \(attempt)"
            var candidate = folder.appendingPathComponent(base + suffix)
            if !ext.isEmpty { candidate.appendPathExtension(ext) }
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return initial
    }

    // MARK: - Move

    /// Move `source` into `destinationFolder`. No-op (returns the source
    /// URL) if it's already there, or if the source is the destination
    /// folder itself / an ancestor of it. On collision shows an alert and
    /// returns nil.
    @discardableResult
    static func move(_ source: URL, into destinationFolder: URL) -> URL? {
        let std = source.standardizedFileURL
        let destStd = destinationFolder.standardizedFileURL
        // Already inside destinationFolder — nothing to do.
        if std.deletingLastPathComponent() == destStd { return source }
        // Can't drop a folder into itself or any of its descendants.
        if destStd.path == std.path { return nil }
        if destStd.path.hasPrefix(std.path + "/") { return nil }

        let target = destStd.appendingPathComponent(source.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) {
            showAlert(message: "“\(source.lastPathComponent)” already exists in \(destinationFolder.lastPathComponent).")
            return nil
        }
        do {
            try FileManager.default.moveItem(at: source, to: target)
            return target
        } catch {
            showAlert(message: "Couldn't move: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Delete

    /// Move the file or folder to the Trash. Returns true on success.
    /// Caller is expected to have already shown a confirmation dialog.
    @discardableResult
    static func moveToTrash(_ url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return true
        } catch {
            showAlert(message: "Couldn't delete: \(error.localizedDescription)")
            return false
        }
    }

    /// Show a destructive-style confirmation alert. Returns true if the
    /// user confirmed.
    static func confirmDelete(_ url: URL) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        alert.messageText = "Move “\(url.lastPathComponent)” to the Trash?"
        alert.informativeText = isFolder
            ? "The folder and all of its contents will be moved to the Trash."
            : "The file will be moved to the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        // Make Cancel the keyboard default so a stray Return doesn't delete.
        if let cancelBtn = alert.buttons.last {
            cancelBtn.keyEquivalent = "\r"
            alert.buttons.first?.keyEquivalent = ""
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Helpers

    private static func promptForName(
        title: String,
        message: String,
        defaultValue: String
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        // Pre-select the basename so typing replaces it cleanly.
        DispatchQueue.main.async {
            field.becomeFirstResponder()
            field.selectText(nil)
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: defaultValue.count)
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func showAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
