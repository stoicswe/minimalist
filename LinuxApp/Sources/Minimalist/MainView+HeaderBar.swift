import Adwaita
import Foundation
import MinimalistCore

extension MainView {

    /// Window title: the active document, with the macOS app's `•`
    /// unsaved marker.
    var windowTitle: String {
        guard let tab = activeTab else { return "{m.txt}" }
        _ = chromeTick
        return (isDirty(tab.id) ? "• " : "") + tab.title
    }

    @ViewBuilder var headerBar: Body {
        HeaderBar {
            Button(icon: .custom(name: "sidebar-show-symbolic")) { sidebarVisible.toggle() }
                .keyboardShortcut("b".ctrl())
                .flat()
            Button(icon: .custom(name: "document-open-symbolic")) { openFileSignal.signal() }
                .keyboardShortcut("o".ctrl())
                .flat()
            Button(icon: .custom(name: "folder-open-symbolic")) { openFolderSignal.signal() }
                .keyboardShortcut("o".ctrl().shift())
                .flat()
            Button(icon: .custom(name: "document-new-symbolic")) { newUntitled() }
                .keyboardShortcut("n".ctrl())
                .flat()
        } end: {
            Menu(icon: .custom(name: "open-menu-symbolic")) {
                menuContent
            }
            .primary()
            .tooltip("Main Menu")
            Button(icon: .custom(name: "system-search-symbolic")) { openSearch() }
                .keyboardShortcut("p".ctrl())
                .flat()
                .tooltip("Search files (⇧⇧)")
            if activeTab?.supportsReader == true {
                Button(icon: .custom(name: "view-reveal-symbolic")) { toggleReader() }
                    .flat()
                    .tooltip("Reader view")
            }
            Button(icon: .custom(name: "document-save-symbolic")) { saveActive() }
                .keyboardShortcut("s".ctrl())
                .flat()
                .tooltip("Save")
        }
        .headerBarTitle {
            WindowTitle(subtitle: folderName, title: windowTitle)
        }
        .style("flat")
    }

    @ViewBuilder var menuContent: Body {
        MenuSection {
            MenuButton("Save As…") { saveAsSignal.signal() }
                .keyboardShortcut("s".ctrl().shift())
            MenuButton("Close Tab") { requestCloseTab(activeTabID) }
                .keyboardShortcut("w".ctrl())
        }
        MenuSection {
            MenuButton("Move Tab Left") { moveActiveTab(by: -1) }
                .keyboardShortcut("Left".ctrl().alt())
            MenuButton("Move Tab Right") { moveActiveTab(by: 1) }
                .keyboardShortcut("Right".ctrl().alt())
        }
        MenuSection {
            MenuButton("Toggle Word Wrap") { toggleWordWrap() }
                .keyboardShortcut("w".ctrl().alt())
            MenuButton("Toggle Minimap") { toggleMinimap() }
            MenuButton("Zen Mode") { zenMode.toggle() }
                .keyboardShortcut("z".ctrl().alt())
        }
        MenuSection {
            MenuButton("Revision History…") { openRevisionHistory() }
            MenuButton("Commit History…") { openCommitHistory() }
        }
        MenuSection {
            MenuButton("Preferences") { preferencesVisible = true }
                .keyboardShortcut("comma".ctrl())
            MenuButton("Keyboard Shortcuts") { shortcutsVisible = true }
                .keyboardShortcut("question".ctrl())
        }
    }
}
