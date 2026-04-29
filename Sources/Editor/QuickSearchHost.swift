import SwiftUI
import AppKit

/// Wraps any content view with the ⇧⇧ Spotlight-style search palette,
/// the double-shift trigger, and click-to-dismiss handling. Used by
/// `ContentView` so both the regular layout and the Zen layout get the
/// same search experience.
struct QuickSearchHost<Content: View>: View {
    @EnvironmentObject var workspace: Workspace
    @State private var showSearch = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            content()

            if showSearch {
                searchOverlay
            }
        }
        .background(
            DoubleShiftMonitor { showSearch.toggle() }
                .allowsHitTesting(false)
        )
    }

    private var searchOverlay: some View {
        ZStack(alignment: .top) {
            // Full-bleed click target. A ~zero opacity stays hit-testable
            // while letting the editor read through.
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { showSearch = false }
                .ignoresSafeArea()

            ZenSearchPalette(
                onJump: { url, line in
                    jumpToFile(url, line: line)
                    showSearch = false
                },
                onClose: { showSearch = false }
            )
            .frame(width: 540)
            .padding(.top, 96)
        }
    }

    private func jumpToFile(_ url: URL, line: Int?) {
        // ⌘S equivalent on departure — only when the doc has a real path.
        // Untitled documents would prompt for a save panel and break the
        // spotlight flow, so skip those.
        if let active = workspace.activeDocument,
           active.isDirty,
           !active.isUntitled,
           active.url != url
        {
            workspace.saveOrSaveAs(active)
        }
        workspace.open(url: url, scrollToLine: line)
    }
}
