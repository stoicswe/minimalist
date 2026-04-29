import SwiftUI
import AppKit

@main
struct MinimalistApp: App {
    @NSApplicationDelegateAdaptor(MinimalistAppDelegate.self) private var appDelegate
    @AppStorage(PreferenceKeys.uiFontName) private var uiFontName: String = ""
    @AppStorage(PreferenceKeys.uiFontSize) private var uiFontSize: Double = 13
    @AppStorage(PreferenceKeys.colorScheme) private var colorSchemePref: String = "system"

    init() {
        // Run as early as possible so AppKit hasn't read controlAccentColor
        // for any cached context — menus, focus rings, default buttons, etc.
        AccentColorOverride.installOnce()
        // Hook iCloud KVS sync to the persisted preference. Safe to call
        // at launch — installs only when the user has enabled it.
        PreferenceSync.shared.updateInstallationFromPreference()
    }

    var body: some Scene {
        // Each window owns its own Workspace via WorkspaceWindow. The very
        // first window opens with `nil` value and is treated as `.primary`
        // (restores last folder + open files); ⌘⇧N and "Open in New Window"
        // open additional windows with explicit launch values.
        WindowGroup("Minimalist", id: "main", for: WindowLaunch.self) { $launch in
            WorkspaceWindow(launch: launch ?? .primary, appDelegate: appDelegate)
                .environment(\.font, currentUIFont)
                .preferredColorScheme(resolvedColorScheme)
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Minimalist") { showAboutPanel() }
            }
            CommandGroup(replacing: .newItem) {
                NewItemCommands()
            }
            CommandMenu("Tabs") {
                TabReorderCommands()
            }
            // Insert into the system's existing View menu instead of
            // creating a second one. `.sidebar` is the placement group
            // that lives in View; adding after it puts our items below
            // the standard sidebar/toolbar entries.
            CommandGroup(after: .sidebar) {
                Divider()
                ZenModeCommand()
                WordWrapCommand()
            }
        }

        Settings {
            // Wrapper picks up the latest accent preset via @AppStorage so
            // the Settings window's toggles, sliders, and selection
            // backgrounds reflect the user's choice live.
            SettingsHost()
        }
    }

    private var currentUIFont: Font {
        if !uiFontName.isEmpty {
            return .custom(uiFontName, size: uiFontSize)
        }
        return .system(size: uiFontSize)
    }

    private var resolvedColorScheme: ColorScheme? {
        switch colorSchemePref {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func showAboutPanel() {
        let icon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage ?? NSImage()
        let credits = NSAttributedString(
            string: "A minimalist code editor.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationIcon: icon,
            .applicationName: "Minimalist",
            .applicationVersion: "0.1.0",
            .credits: credits,
        ])
    }
}

/// Settings scene root. Lives separately from `WorkspaceWindow` because
/// the Settings scene doesn't inherit the workspace tint we apply on the
/// main windows — without this, toggles + selection bars in Preferences
/// fall back to the system accent.
private struct SettingsHost: View {
    @AppStorage(PreferenceKeys.accentPresetID)
    private var accentID: String = AccentPresets.defaultID
    @AppStorage(PreferenceKeys.colorScheme)
    private var colorSchemePref: String = "system"

    var body: some View {
        PreferencesView()
            .tint(AccentPresets.preset(forID: accentID).color)
            .preferredColorScheme(resolvedColorScheme)
    }

    private var resolvedColorScheme: ColorScheme? {
        switch colorSchemePref {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }
}

/// Per-window root view. Each window has its own Workspace, so the New
/// Window / Open in New Window flows produce truly independent state.
struct WorkspaceWindow: View {
    @StateObject private var workspace: Workspace
    private let isPrimary: Bool
    private let appDelegate: MinimalistAppDelegate

    @AppStorage(PreferenceKeys.accentPresetID)
    private var accentID: String = AccentPresets.defaultID

    init(launch: WindowLaunch, appDelegate: MinimalistAppDelegate) {
        self.isPrimary = (launch == .primary)
        self.appDelegate = appDelegate
        _workspace = StateObject(wrappedValue: Workspace(launch: launch))
    }

    var body: some View {
        ContentView()
            .environmentObject(workspace)
            .background(WindowWorkspaceBinder(workspace: workspace))
            // Propagates to SwiftUI controls and the menu-item highlight
            // for `.contextMenu` popups (NSMenu picks up the window's
            // accent through SwiftUI's tint plumbing).
            .tint(AccentPresets.preset(forID: accentID).color)
            .onAppear {
                // Only the primary window's workspace gets the
                // session-end commit hook — other windows are transient.
                if isPrimary {
                    appDelegate.workspace = workspace
                }
            }
    }
}

/// Walks up the SwiftUI -> NSWindow boundary so the WorkspaceCoordinator
/// can track which window currently holds a given Workspace. Required
/// because SwiftUI's `@FocusedValue` is empty until something inside the
/// window takes focus, which makes menu shortcuts (⌘N, ⌘S) unreliable
/// right after a window opens.
private struct WindowWorkspaceBinder: NSViewRepresentable {
    let workspace: Workspace

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                WorkspaceCoordinator.shared.bind(workspace: workspace, to: window)
            }
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        if let window = view.window {
            WorkspaceCoordinator.shared.bind(workspace: workspace, to: window)
        }
    }
}

/// Tracks the workspace owned by each Minimalist window plus which one is
/// currently key, so menu commands can always reach the right one.
@MainActor
final class WorkspaceCoordinator {
    static let shared = WorkspaceCoordinator()

    private var registry: [ObjectIdentifier: Workspace] = [:]
    private weak var lastKeyWindow: NSWindow?
    private var observersInstalled = false

    var current: Workspace? {
        if let key = NSApp.keyWindow ?? NSApp.mainWindow ?? lastKeyWindow,
           let ws = registry[ObjectIdentifier(key)] {
            return ws
        }
        // Fallback to any registered workspace.
        return registry.values.first
    }

    func bind(workspace: Workspace, to window: NSWindow) {
        installObserversIfNeeded()
        registry[ObjectIdentifier(window)] = workspace
        lastKeyWindow = window
    }

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let window = note.object as? NSWindow else { return }
                if self.registry[ObjectIdentifier(window)] != nil {
                    self.lastKeyWindow = window
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main
        ) { [weak self] note in
            Task { @MainActor in
                guard let self, let window = note.object as? NSWindow else { return }
                self.registry.removeValue(forKey: ObjectIdentifier(window))
            }
        }
    }
}

// MARK: - Menu commands

/// New / Open commands. Resolves the active workspace through the
/// `WorkspaceCoordinator` (rather than `@FocusedValue`) since menu
/// shortcuts must work even before any view inside the window has taken
/// focus.
private struct NewItemCommands: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKeys.openLocationBehavior)
    private var openBehavior: String = OpenLocationBehavior.default

    var body: some View {
        Group {
            Button("New") { WorkspaceCoordinator.shared.current?.newUntitled() }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Window") { openWindow(id: "main", value: WindowLaunch.fresh) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Open Folder…") { handleOpen(folder: true) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Open File…") { handleOpen(folder: false) }
                .keyboardShortcut("o", modifiers: .command)
            Divider()
            Button("Save") { WorkspaceCoordinator.shared.current?.saveActive() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Close Tab") { WorkspaceCoordinator.shared.current?.closeActive() }
                .keyboardShortcut("w", modifiers: .command)
        }
    }

    private func handleOpen(folder: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !folder
        panel.canChooseDirectories = folder
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let workspace = WorkspaceCoordinator.shared.current
        let resolved = OpenLocationDecider.resolve(
            preference: openBehavior,
            hasCurrentWindow: workspace != nil,
            isFolder: folder,
            url: url
        )

        switch resolved {
        case .sameWindow:
            if folder {
                workspace?.adoptFolder(at: url)
            } else {
                workspace?.open(url: url)
            }
        case .newWindow:
            openWindow(id: "main", value: folder
                ? WindowLaunch.openFolder(url)
                : WindowLaunch.openFile(url))
        case .cancel:
            break
        }
    }
}

private struct ZenModeCommand: View {
    @AppStorage(PreferenceKeys.zenMode) private var zenMode: Bool = false

    var body: some View {
        Button(zenMode ? "Exit Zen Mode" : "Enter Zen Mode") {
            zenMode.toggle()
        }
        .keyboardShortcut("z", modifiers: [.command, .control])
    }
}

/// Toggle word wrap from the View menu. The toggle title flips so the
/// command always reads as the action you'd take next.
private struct WordWrapCommand: View {
    @AppStorage(PreferenceKeys.wordWrap) private var wordWrap: Bool = true

    var body: some View {
        Button(wordWrap ? "Disable Word Wrap" : "Enable Word Wrap") {
            wordWrap.toggle()
            NotificationCenter.default.post(name: .editorPreferencesChanged, object: nil)
        }
        .keyboardShortcut("w", modifiers: [.command, .option])
    }
}

/// Tab reorder commands extracted into its own view so it shares the
/// coordinator-based workspace lookup pattern.
private struct TabReorderCommands: View {
    var body: some View {
        Group {
            Button("Move Tab Left") { WorkspaceCoordinator.shared.current?.moveActiveTabLeft() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Move Tab Right") { WorkspaceCoordinator.shared.current?.moveActiveTabRight() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }
    }
}

/// Decides — based on the user's preference and current state — where an
/// "Open File / Folder" should land.
enum OpenLocationDecider {
    enum Resolution { case sameWindow, newWindow, cancel }

    static func resolve(
        preference: String,
        hasCurrentWindow: Bool,
        isFolder: Bool,
        url: URL
    ) -> Resolution {
        // No window to land in → forced new window.
        if !hasCurrentWindow { return .newWindow }

        switch preference {
        case OpenLocationBehavior.same: return .sameWindow
        case OpenLocationBehavior.new: return .newWindow
        default: break
        }

        // Ask the user.
        let alert = NSAlert()
        alert.messageText = "Open in this window or a new window?"
        alert.informativeText = isFolder
            ? "“\(url.lastPathComponent)” will replace this window's folder, or open in its own window."
            : "“\(url.lastPathComponent)” can open in the current window's tabs, or in its own window."
        alert.addButton(withTitle: "This Window")
        alert.addButton(withTitle: "New Window")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:  return .sameWindow
        case .alertSecondButtonReturn: return .newWindow
        default:                       return .cancel
        }
    }
}
