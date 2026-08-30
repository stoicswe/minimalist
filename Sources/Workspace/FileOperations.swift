import Foundation
import AppKit
import MinimalistCore

/// File-system operations triggered from the sidebar context menu.
///
/// The file-system work itself lives in `MinimalistCore.FileOps` (shared
/// with the Linux app); this layer owns the macOS-specific parts — the
/// name prompts, the confirmation and error alerts, the pasteboard, the
/// Finder, and the Trash. All operations show an `NSAlert` if they fail,
/// since the user invoked them explicitly and a silent failure would be
/// confusing.
enum FileOperations {
    // MARK: - Create

    /// Create an empty file in `parent`. Prompts for a name. Returns the
    /// new file's URL on success, nil if cancelled or on error.
    @discardableResult
    static func createFile(in parent: URL) -> URL? {
        guard let name = promptForName(
            title: "New File",
            message: "Name the new file:",
            defaultValue: "untitled.txt"
        ) else { return nil }
        return attempt { try FileOps.createFile(named: name, in: parent) }
    }

    @discardableResult
    static func createFolder(in parent: URL) -> URL? {
        guard let name = promptForName(
            title: "New Folder",
            message: "Name the new folder:",
            defaultValue: "untitled folder"
        ) else { return nil }
        return attempt { try FileOps.createFolder(named: name, in: parent) }
    }

    // MARK: - Rename / duplicate

    @discardableResult
    static func rename(_ url: URL) -> URL? {
        guard let newName = promptForName(
            title: "Rename",
            message: "New name:",
            defaultValue: url.lastPathComponent
        ) else { return nil }
        guard let renamed = attempt({ try FileOps.rename(url, to: newName) }) else { return nil }
        // Unchanged name — nothing for the caller to update.
        return renamed == url ? nil : renamed
    }

    /// Duplicate a file or folder, appending " copy" (or " copy 2", etc.)
    /// before the extension to avoid collisions.
    @discardableResult
    static func duplicate(_ url: URL) -> URL? {
        attempt { try FileOps.duplicate(url) }
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
        return urls.compactMap { src in
            attempt(
                { try FileOps.copy(src, into: parent) },
                prefix: "Couldn't paste \(src.lastPathComponent): "
            )
        }
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
        attempt { try FileOps.copy(source, into: destinationFolder) }
    }

    // MARK: - Move

    /// Move `source` into `destinationFolder`. No-op (returns the source
    /// URL) if it's already there. Returns nil — silently for a drop onto
    /// itself, with an alert on collision — when the move can't happen.
    @discardableResult
    static func move(_ source: URL, into destinationFolder: URL) -> URL? {
        do {
            return try FileOps.move(source, into: destinationFolder)
        } catch FileOps.OpError.notPermitted {
            // Dropping a folder onto itself or a descendant: not an error
            // worth an alert, the drag just doesn't do anything.
            return nil
        } catch {
            showAlert(message: error.localizedDescription)
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
        let isFolder = FileOps.isDirectory(url)
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

    /// Run a `FileOps` call, surfacing any failure as an alert.
    private static func attempt(_ operation: () throws -> URL, prefix: String = "") -> URL? {
        do {
            return try operation()
        } catch {
            showAlert(message: prefix + error.localizedDescription)
            return nil
        }
    }

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
