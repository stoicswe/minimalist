import Adwaita
import Foundation
import MinimalistCore

extension MainView {

    /// Styling for the parts of the macOS design with no stock libadwaita
    /// equivalent: pill tabs, the branch pill, tree rows with their
    /// colored monograms, the floating status pill, and the palette.
    ///
    /// Built as a string on every update so the editor font and the
    /// per-file badge colors currently on screen stay in sync.
    var style: String {
        let settings = onMain { DocumentStore.shared.settings }
        return """
        button.branch-pill {
            background-color: alpha(@accent_bg_color, 0.15);
            background-image: none;
            color: @accent_color;
            border: none;
            box-shadow: none;
            border-radius: 999px;
            padding: 1px 8px;
            min-height: 24px;
        }
        button.branch-pill:hover {
            background-color: alpha(@accent_bg_color, 0.28);
        }
        .tab-bar { padding: 4px 6px; }
        box.tab-slot {
            border-radius: 10px;
            padding: 0 2px;
        }
        box.tab-slot.tab-active {
            background-color: alpha(@window_fg_color, 0.08);
        }
        button.tab-item {
            background: none;
            border-radius: 8px;
            padding: 2px 8px;
            min-height: 0;
            color: alpha(@window_fg_color, 0.7);
        }
        box.tab-slot.tab-active button.tab-item { color: @window_fg_color; }
        button.tab-close {
            background: none;
            min-height: 0;
            min-width: 18px;
            padding: 0 2px;
            opacity: 0.55;
        }
        button.tab-close:hover { opacity: 1; }
        .tab-preview { font-style: italic; }
        button.tree-row {
            border-radius: 8px;
            padding: 1px 8px;
            min-height: 0;
        }
        button.tree-row.row-active {
            background-color: alpha(@window_fg_color, 0.1);
        }
        button.menu-item {
            border-radius: 6px;
            padding: 4px 10px;
            min-height: 0;
        }
        .folder-icon { color: alpha(@accent_color, 0.85); }
        .file-badge {
            color: #ffffff;
            font-size: 8pt;
            font-weight: bold;
            border-radius: 4px;
            padding: 1px 3px;
            min-width: 18px;
        }
        \(badgeStyles)
        .status-pill {
            background-color: mix(@view_bg_color, @view_fg_color, 0.05);
            border: 1px solid alpha(@view_fg_color, 0.1);
            border-radius: 999px;
            padding: 3px 14px;
            min-height: 0;
            box-shadow: 0 2px 6px alpha(black, 0.15);
        }
        button.float-btn {
            background-color: mix(@view_bg_color, @view_fg_color, 0.05);
            border: 1px solid alpha(@view_fg_color, 0.1);
            box-shadow: 0 2px 6px alpha(black, 0.15);
        }
        button.float-btn.float-btn-active {
            background-color: alpha(@accent_bg_color, 0.25);
            color: @accent_color;
        }
        .palette {
            background-color: @view_bg_color;
            border: 1px solid alpha(@view_fg_color, 0.12);
            border-radius: 14px;
            box-shadow: 0 8px 24px alpha(black, 0.3);
        }
        button.palette-row {
            border-radius: 8px;
            padding: 4px 10px;
            min-height: 0;
        }
        button.palette-row.palette-row-active {
            background-color: alpha(@accent_bg_color, 0.2);
        }
        .reader { font-size: \(settings.editorFontSize + 2)pt; }
        .editor-view {
            font-family: "\(settings.editorFontFamily)", monospace;
            font-size: \(settings.editorFontSize)pt;
        }
        .editor-view.editor-bg-white text { background-color: #ffffff; color: #1d1d1d; }
        .editor-view.editor-bg-sepia text { background-color: #f4ecd8; color: #3b352b; }
        .editor-view.editor-bg-dark text { background-color: #1e1e1e; color: #e6e6e6; }
        .editor-map {
            border-left: 1px solid alpha(@view_fg_color, 0.08);
            background-color: alpha(@view_fg_color, 0.02);
        }
        """
    }

    /// One CSS class per badge color currently visible in the sidebar.
    private var badgeStyles: String {
        var seen: Set<String> = []
        var rules: [String] = []
        for row in rows where !row.isDirectory {
            let badge = FileTypeBadge.badge(forName: row.name)
            let hex = badge.hex
            guard seen.insert(hex).inserted else { continue }
            rules.append(".badge-\(hex.dropFirst()) { background-color: \(hex); }")
        }
        return rules.joined(separator: "\n")
    }
}
