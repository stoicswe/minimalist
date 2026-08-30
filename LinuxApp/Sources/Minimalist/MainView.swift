import Adwaita
import Foundation
import MinimalistCore

/// The window shell, styled after the macOS app: a sidebar with the
/// project header and branch pill, a pill tab strip, the GtkSourceView
/// editor with its minimap, and a floating status pill.
///
/// Layout and interaction logic live here; the per-area bodies are split
/// across `MainView+*.swift`.
struct MainView: View {

    var app: AdwaitaApp
    var window: AdwaitaWindow

    // Shell
    @State var sidebarVisible = true
    @State var zenMode = false
    @State var folderName = ""
    @State var branch = ""
    @State var branches: [String] = []
    @State var branchMenuVisible = false

    // Sidebar
    @State var rows: [FileRow] = []
    @State var expanded: Set<String> = []
    @State var contextRowID = ""
    @State var showContextMenu = false

    // Tabs & editor
    @State var tabs: [EditorTab] = []
    @State var activeTabID = ""
    @State var untitledCount = 0
    @State var scrollLine: Int?
    @State var scrollToken = 0
    /// Bumped whenever a model change needs the chrome to redraw (dirty
    /// dots, the status pill, settings) — Adwaita re-renders on `@State`
    /// changes, and the documents themselves aren't view state.
    @State var chromeTick = 0

    // File dialogs
    @State var openFileSignal = Signal()
    @State var openFolderSignal = Signal()
    @State var saveAsSignal = Signal()

    // Search palette
    @State var searchVisible = false
    @State var searchQuery = ""
    @State var searchIndex = 0
    @State var searchFocus = Signal()
    /// Workspace files, collected once when the palette opens so typing
    /// doesn't re-walk the tree on every keystroke.
    @State var searchCandidates: [String] = []

    // Dialogs
    @State var namePromptVisible = false
    @State var namePromptKind = NamePrompt.newFile
    @State var namePromptValue = ""
    @State var namePromptTarget = ""
    @State var deleteVisible = false
    @State var unsavedVisible = false
    @State var pendingCloseID = ""
    /// Set while a "Save" answer to the unsaved-changes prompt is waiting
    /// on Save As, so the tab closes once the file has a home.
    @State var closeAfterSave = false
    /// True while the session is being restored, so the half-restored
    /// state isn't written back over the saved one.
    @State var restoring = false
    @State var errorVisible = false
    @State var errorMessage = ""
    @State var newBranchVisible = false
    @State var newBranchName = ""
    @State var statusPopoverVisible = false
    @State var revisionsVisible = false
    @State var revisionSelection = ""
    @State var revisionRows: [RevisionRow] = []
    @State var commitsVisible = false
    @State var commitSelection = ""
    @State var commitRows: [CommitRow] = []
    /// Path whose history the open history dialog is showing.
    @State var historyTarget = ""
    @State var historyPreview = ""
    @State var preferencesVisible = false
    @State var shortcutsVisible = false
    @State var aboutVisible = false

    /// What a name prompt is being used for.
    enum NamePrompt: String {
        case newFile, newFolder, rename

        var heading: String {
            switch self {
            case .newFile: "New File"
            case .newFolder: "New Folder"
            case .rename: "Rename"
            }
        }
    }

    var activeTab: EditorTab? {
        tabs.first { $0.id == activeTabID }
    }

    /// The active document's text. Deliberately *not* `@State`: the
    /// editor binds through to the `Document`, so the text can never be
    /// one render out of step with `activeTabID` — which would otherwise
    /// push one document's contents into another's buffer.
    var activeText: String {
        text(of: activeTabID)
    }

    func text(of id: String) -> String {
        guard !id.isEmpty else { return "" }
        return onMain { DocumentStore.shared.document(for: id)?.text ?? "" }
    }

    var view: Body {
        OverlaySplitView(visible: .init { sidebarVisible && !zenMode } set: { sidebarVisible = $0 }) {
            sidebar
        } content: {
            contentPane
        }
        .topToolbar(visible: !zenMode) {
            headerBar
        }
        .css { style }
        .inspect { storage, _ in installKeyHandling(storage) }
        .fileImporter(open: $openFileSignal, onOpen: { url in openFile(url, preview: false) })
        .folderImporter(open: $openFolderSignal, onOpen: { url in openFolder(url) })
        .fileExporter(
            open: $saveAsSignal,
            initialName: activeTab?.title,
            onSave: { url in saveActiveAs(to: url) }
        )
        .alertDialog(
            visible: $unsavedVisible,
            heading: "Save changes to “\(title(of: pendingCloseID))”?",
            body: "Your changes will be lost if you don't save them.",
            id: "unsaved"
        )
        .response("Cancel", role: .close) { pendingCloseID = "" }
        .response("Don't Save") { discardAndClose() }
        .response("Save", appearance: .suggested, role: .default) { saveAndClose() }
        .alertDialog(
            visible: $deleteVisible,
            heading: "Move “\(name(of: contextRowID))” to the Trash?",
            body: FileOps.isDirectory(URL(fileURLWithPath: contextRowID))
                ? "The folder and all of its contents will be moved to the Trash."
                : "The file will be moved to the Trash.",
            id: "delete"
        )
        .response("Cancel", role: .close) { }
        .response("Move to Trash", appearance: .destructive) { deleteContextTarget() }
        .alertDialog(visible: $errorVisible, heading: "Something went wrong", body: errorMessage, id: "error")
        .response("OK", role: .close) { }
        .alertDialog(visible: $namePromptVisible, heading: namePromptKind.heading, id: "name") {
            Form {
                EntryRow("Name", text: $namePromptValue)
            }
            .padding(6)
        }
        .response("Cancel", role: .close) { }
        .response("OK", appearance: .suggested, role: .default) { commitNamePrompt() }
        .alertDialog(visible: $newBranchVisible, heading: "New Branch", id: "branch") {
            Form {
                EntryRow("Branch name", text: $newBranchName)
            }
            .padding(6)
        }
        .response("Cancel", role: .close) { }
        .response("Create", appearance: .suggested, role: .default) { createBranch() }
        // Every dialog needs its own id: the wrappers all share this
        // view's storage and park their widget under "dialog" + id, so
        // two dialogs without ids silently overwrite each other — the
        // second one never presents. `aboutDialog` has no id parameter
        // and always uses the bare "dialog" key, so it owns that one.
        .dialog(
            visible: $revisionsVisible,
            title: "Revision History",
            id: "revisions",
            width: 720,
            height: 520
        ) {
            revisionHistory
        }
        .dialog(
            visible: $commitsVisible,
            title: "Commit History",
            id: "commits",
            width: 760,
            height: 560
        ) {
            commitHistory
        }
        .dialog(
            visible: $preferencesVisible,
            title: "Preferences",
            id: "preferences",
            width: 620,
            height: 640
        ) {
            preferencesContent
        }
        .aboutDialog(
            visible: $aboutVisible,
            app: AppInfo.name,
            developer: AppInfo.developer,
            version: AppInfo.version,
            icon: .custom(name: AppInfo.iconName),
            details: [
                .comment(AppInfo.blurb),
                .copyright(AppInfo.copyright),
                .developers(["\(AppInfo.developer) \(AppInfo.profileURL?.absoluteString ?? "")"]),
                .licenseType(.mitX11)
            ],
            links: [
                // The macOS tip jar is a StoreKit purchase; on Linux the
                // equivalent is the project's GitHub Sponsor button.
                .add(AppInfo.sponsorURL, title: "Sponsor this project"),
                .website(AppInfo.projectURL),
                .issues(AppInfo.issuesURL),
                .add(AppInfo.blueskyURL, title: "Bluesky (\(AppInfo.blueskyHandle))"),
                .add(AppInfo.emailURL, title: AppInfo.email)
            ]
        )
        .dialog(
            visible: $shortcutsVisible,
            title: "Keyboard Shortcuts",
            id: "shortcuts",
            width: 520,
            height: 620
        ) {
            shortcutsContent
        }
        .onAppear { Idle { restoreSession() } }
    }
}
