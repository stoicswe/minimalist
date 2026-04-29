import Foundation
import AppKit

/// Two-way mirror between selected `UserDefaults` preferences and
/// `NSUbiquitousKeyValueStore`. When sync is enabled, theme / accent /
/// autocomplete / typography preferences flow through iCloud KVS so the
/// user's setup follows them across Macs signed in to the same Apple ID.
///
/// Notes:
///  - Only standard, OS-shipped font names sync. Custom fonts stay local
///    so the user doesn't end up with an unresolvable font on a device
///    that doesn't have it.
///  - When the user enables sync, cloud values win for any key already
///    present in the cloud store; keys the cloud doesn't have get pushed
///    from local. This makes "I set things up on Mac A, now I'm enabling
///    on Mac B" Just Work.
@MainActor
final class PreferenceSync {
    static let shared = PreferenceSync()
    private init() {}

    /// Keys to mirror in either direction.
    private static let syncedKeys: Set<String> = [
        // Appearance
        PreferenceKeys.colorScheme,
        PreferenceKeys.windowGlass,
        PreferenceKeys.syntaxThemeLight,
        PreferenceKeys.syntaxThemeDark,
        PreferenceKeys.showLineNumbers,
        PreferenceKeys.wordWrap,
        PreferenceKeys.editorBackgroundOverride,
        PreferenceKeys.editorBackgroundLight,
        PreferenceKeys.editorBackgroundDark,
        PreferenceKeys.editorBackgroundPattern,
        PreferenceKeys.editorBackgroundPatternAnimated,
        PreferenceKeys.editorBackgroundPatternSpeed,

        // Editor behavior
        PreferenceKeys.enableAutocomplete,
        PreferenceKeys.enableLanguageKeywords,

        // Accent
        PreferenceKeys.accentPresetID,
        PreferenceKeys.accentTintFolders,
        PreferenceKeys.accentTintTabs,
        PreferenceKeys.accentTintCurrentLine,
        PreferenceKeys.accentTintSidebar,

        // Typography (font names guarded — see standardFontNames).
        PreferenceKeys.editorFontName,
        PreferenceKeys.editorFontSize,
        PreferenceKeys.uiFontName,
        PreferenceKeys.uiFontSize,
    ]

    /// Subset of `syncedKeys` whose value is a font name string. We only
    /// push these when the chosen family ships with macOS.
    private static let fontNameKeys: Set<String> = [
        PreferenceKeys.editorFontName,
        PreferenceKeys.uiFontName,
    ]

    private let store = NSUbiquitousKeyValueStore.default
    private var defaultsObserver: NSObjectProtocol?
    private var iCloudObserver: NSObjectProtocol?

    /// Set when we're applying values pulled from iCloud — guards against
    /// the resulting `UserDefaults.didChangeNotification` looping a push
    /// straight back out.
    private var isApplyingRemote = false
    private(set) var isInstalled = false

    // MARK: - Lifecycle

    /// Read the user's preference and install (or remove) the sync hooks.
    /// Safe to call repeatedly — it only acts on transitions.
    func updateInstallationFromPreference() {
        let want = UserDefaults.standard.bool(forKey: PreferenceKeys.iCloudSyncEnabled)
        if want, !isInstalled {
            install()
        } else if !want, isInstalled {
            uninstall()
        }
    }

    private func install() {
        guard !isInstalled else { return }
        isInstalled = true

        iCloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.applyRemoteChanges(note: note) }
        }

        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pushChangedToCloud() }
        }

        // Reconcile current state with cloud now that we're tracking.
        reconcileOnInstall()
    }

    private func uninstall() {
        guard isInstalled else { return }
        isInstalled = false
        if let o = iCloudObserver {
            NotificationCenter.default.removeObserver(o)
            iCloudObserver = nil
        }
        if let o = defaultsObserver {
            NotificationCenter.default.removeObserver(o)
            defaultsObserver = nil
        }
    }

    // MARK: - Reconciliation

    /// On enable: cloud values win for keys it already has. Keys it
    /// doesn't have get populated from local (subject to the font
    /// allowlist).
    private func reconcileOnInstall() {
        // Pull what cloud has.
        store.synchronize()
        isApplyingRemote = true
        for key in Self.syncedKeys {
            guard let cloudVal = store.object(forKey: key) else { continue }
            if Self.fontNameKeys.contains(key),
               let name = cloudVal as? String,
               !Self.isStandardFont(name) {
                continue
            }
            UserDefaults.standard.set(cloudVal, forKey: key)
        }
        isApplyingRemote = false

        // Push everything cloud is missing.
        for key in Self.syncedKeys {
            if store.object(forKey: key) != nil { continue }
            guard let local = UserDefaults.standard.object(forKey: key) else { continue }
            if Self.fontNameKeys.contains(key),
               let name = local as? String,
               !Self.isStandardFont(name) {
                continue
            }
            store.set(local, forKey: key)
        }
        store.synchronize()

        // Let any UI reading these values re-render.
        NotificationCenter.default.post(name: .editorPreferencesChanged, object: nil)
    }

    // MARK: - Local → cloud

    private func pushChangedToCloud() {
        guard isInstalled, !isApplyingRemote else { return }
        for key in Self.syncedKeys {
            let value = UserDefaults.standard.object(forKey: key)
            if Self.fontNameKeys.contains(key),
               let name = value as? String,
               !Self.isStandardFont(name) {
                // Custom font picked locally — clear from cloud so other
                // devices fall back to system rather than a stale name.
                store.removeObject(forKey: key)
                continue
            }
            if let value {
                store.set(value, forKey: key)
            } else {
                store.removeObject(forKey: key)
            }
        }
        store.synchronize()
    }

    // MARK: - Cloud → local

    private func applyRemoteChanges(note: Notification) {
        let keys = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? []
        let touched = keys.filter { Self.syncedKeys.contains($0) }
        guard !touched.isEmpty else { return }

        isApplyingRemote = true
        for key in touched {
            if let cloudVal = store.object(forKey: key) {
                if Self.fontNameKeys.contains(key),
                   let name = cloudVal as? String,
                   !Self.isStandardFont(name) {
                    continue
                }
                UserDefaults.standard.set(cloudVal, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        isApplyingRemote = false
        NotificationCenter.default.post(name: .editorPreferencesChanged, object: nil)
    }

    // MARK: - Standard fonts

    /// Curated set of font families that ship with macOS. The empty
    /// string represents "system default" and is always treated as
    /// standard. Custom fonts a user installed on one Mac shouldn't get
    /// pushed to a Mac that doesn't have them.
    private static let standardFonts: Set<String> = [
        "",
        // Apple's own system faces
        "SF Pro", "SF Pro Display", "SF Pro Text", "SF Pro Rounded",
        "SF Compact", "SF Compact Display", "SF Compact Text", "SF Compact Rounded",
        "SF Mono", "New York",
        // Long-shipping system fonts
        "Andale Mono", "Arial", "Arial Black", "Arial Narrow",
        "Avenir", "Avenir Next", "Baskerville", "Charter",
        "Comic Sans MS", "Copperplate", "Courier", "Courier New",
        "Didot", "Futura", "Geneva", "Georgia", "Gill Sans",
        "Helvetica", "Helvetica Neue", "Hoefler Text", "Impact",
        "Lucida Grande", "Menlo", "Monaco", "Optima",
        "Palatino", "Times", "Times New Roman",
        "Trebuchet MS", "Verdana",
    ]

    static func isStandardFont(_ name: String) -> Bool {
        standardFonts.contains(name)
    }
}
