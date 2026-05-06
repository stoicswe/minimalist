import AppKit
import SwiftUI
import ObjectiveC.runtime

/// Hooks into the AppKit lifecycle so we can record a `.minimal` session
/// commit on app quit and snapshot every open window's state for
/// restoration on next launch. SwiftUI's `WindowGroup` doesn't expose
/// `applicationWillTerminate`, so we bridge through this minimal delegate.
final class MinimalistAppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `MinimalistApp.onAppear` so we can reach the active workspace
    /// without rebuilding it here. Used as a fallback for the session-end
    /// commit when no workspaces are registered with the coordinator.
    weak var workspace: Workspace? {
        didSet { drainPendingOpenURLs() }
    }

    /// URLs delivered by `application(_:open:)` before any workspace had
    /// registered yet — typically when launching from Finder via "Open
    /// With Minimalist". Drained as soon as a workspace is available.
    private var pendingOpenURLs: [URL] = []

    /// Receives file URLs from Finder ("Open With…", drag-onto-icon,
    /// double-click after registering CFBundleDocumentTypes). Routes them
    /// into the active workspace's tabs, queueing if no window is up yet.
    func application(_ application: NSApplication, open urls: [URL]) {
        if WorkspaceCoordinator.shared.current != nil || workspace != nil {
            openInActiveWorkspace(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
            // Belt-and-suspenders: SwiftUI's primary window registers via
            // WindowWorkspaceBinder shortly after launch. If that ever
            // fails, retry a few times before giving up.
            scheduleDrainRetry(retriesRemaining: 20)
        }
    }

    private func scheduleDrainRetry(retriesRemaining: Int) {
        guard retriesRemaining > 0, !pendingOpenURLs.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            if WorkspaceCoordinator.shared.current != nil || self.workspace != nil {
                self.drainPendingOpenURLs()
            } else {
                self.scheduleDrainRetry(retriesRemaining: retriesRemaining - 1)
            }
        }
    }

    private func drainPendingOpenURLs() {
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        openInActiveWorkspace(urls)
    }

    private func openInActiveWorkspace(_ urls: [URL]) {
        MainActor.assumeIsolated {
            guard let workspace = WorkspaceCoordinator.shared.current ?? self.workspace else { return }
            for url in urls {
                let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isFolder {
                    workspace.adoptFolder(at: url)
                } else {
                    workspace.open(url: url)
                }
            }
            // Bring the window forward in case Finder didn't already do it.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Snapshot every open window so they all come back on relaunch —
        // not just the primary. Order is most-recently-key first so the
        // window the user last interacted with becomes the new primary.
        // applicationWillTerminate is delivered on the main thread, so we
        // can synchronously hop into the coordinator's MainActor isolation.
        MainActor.assumeIsolated {
            let workspaces = WorkspaceCoordinator.shared.allWorkspaces
            let snapshots = workspaces.map { $0.captureSnapshot() }
            SavedWindowsStore.save(snapshots)

            // Best-effort session-end commit on each workspace's git
            // mirror. Failures here shouldn't block shutdown.
            for ws in workspaces {
                ws.recordSessionEnd()
            }
            if workspaces.isEmpty {
                workspace?.recordSessionEnd()
            }
        }
    }
}

// MARK: - System accent override

/// Replaces the AppKit accent / selection color getters for our process so
/// menu highlights, focus rings, default buttons, and selection bars use
/// the user's chosen preset. SwiftUI's `.tint(...)` doesn't reach NSMenu —
/// this is the cleanest way to make those AppKit-painted surfaces match.
enum AccentColorOverride {
    private static var installed = false

    static func installOnce() {
        guard !installed else { return }
        installed = true

        // Class methods live on the metaclass — that's what we patch.
        guard let meta = object_getClass(NSColor.self) else { return }
        guard
            let accentMethod = class_getClassMethod(NSColor.self, #selector(NSColor.mn_accentColor)),
            let unemphasizedMethod = class_getClassMethod(NSColor.self, #selector(NSColor.mn_unemphasizedAccentColor))
        else { return }

        let accentIMP = method_getImplementation(accentMethod)
        let unemphasizedIMP = method_getImplementation(unemphasizedMethod)
        let typeEncoding = method_getTypeEncoding(accentMethod)

        // Different AppKit surfaces consult different system colors —
        // menu highlight in particular tends to read
        // selectedContentBackgroundColor on modern macOS, while focus
        // rings read keyboardFocusIndicatorColor. Patch all of them so
        // the chosen accent shows up everywhere AppKit paints accents.
        let installs: [(String, IMP)] = [
            ("controlAccentColor",                         accentIMP),
            ("selectedContentBackgroundColor",             accentIMP),
            ("unemphasizedSelectedContentBackgroundColor", unemphasizedIMP),
            ("keyboardFocusIndicatorColor",                accentIMP),
        ]
        for (name, imp) in installs {
            let sel = NSSelectorFromString(name)
            // Use class_replaceMethod so each selector ends up pointing
            // at our IMP — using method_exchangeImplementations would
            // chain-swap the replacement's IMP after the first call.
            _ = class_replaceMethod(meta, sel, imp, typeEncoding)
        }

        // Nudge AppKit to drop any cached system-color values it may have
        // already resolved before this point.
        NotificationCenter.default.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
    }
}

extension NSColor {
    @objc class func mn_accentColor() -> NSColor {
        return AccentPresets.current.nsColor
    }

    @objc class func mn_unemphasizedAccentColor() -> NSColor {
        return AccentPresets.current.nsColor.withAlphaComponent(0.55)
    }
}
