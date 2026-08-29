# Porting {m.txt} to Linux — feature spec & parity tracker

The macOS app (repo `Sources/`) is the reference implementation. The goal
is for the Linux app to feel like the same product: same layout, same
features, same behaviors — translated into GNOME idioms where a literal
copy would fight the platform (header bars instead of a custom titlebar,
Ctrl instead of ⌘). This document describes the macOS app as it exists
today, tracks parity status, and maps each feature to its Linux
implementation strategy.

**Keep the matrix in this file updated as features land.**

---

## 1. The macOS app, as shipped

### 1.1 Window layout

```
┌───────────────────────────────────────────────────────────────┐
│ ●●●  (custom tight titlebar — traffic lights repositioned,    │
│       no toolbar; content extends into the titlebar area)     │
│ ┌─────────────┬───────────────────────────────────────────┐   │
│ │ TopBar:     │ TabBar: [tab ●] [tab] [preview-italic]    │   │
│ │ folder-name │───────────────────────────────────────────│   │
│ │  · ⎇branch  │                                     ┌───┐ │   │
│ │─────────────│                                     │ m │ │   │
│ │ File tree   │           Editor / viewer           │ i │ │   │
│ │  ▸ dir      │                                     │ n │ │   │
│ │  ▾ dir      │                                     │ i │ │   │
│ │    file     │                                     │map│ │   │
│ │  a.b.c ▸    │                                     └───┘ │   │
│ │ (compacted) │                          [status pill] ◄──│   │
│ └─────────────┴───────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

- Two-pane `HSplitView`. Left column: **TopBar** (workspace folder name,
  a `·` separator, a **branch button**) stacked above the **file tree**.
  Right column: **TabBar** on top, editor/viewer below.
- **Minimap** docks at the editor's right edge (with a translucent
  viewport overlay; click/drag scrolls). When the minimap is off, a thin
  custom **external scrollbar** takes its place.
- **Status pill** floats bottom-trailing over the editor.
- **Zen mode** (⌘⌃Z) swaps to a chrome-free layout: no sidebar, no tabs,
  editor only.
- **Glass mode** (preference): window-level blur/refraction with a
  floating tab bar. macOS-distinctive — not expected to port.

### 1.2 Documents & viewers

`DocumentKind` (in MinimalistCore) routes each opened file:

| Kind | macOS viewer | Notes |
|---|---|---|
| text | NSTextView editor | The main experience (see 1.3) |
| text (md/adoc) | + toggleable **reader view** | Markdown via MarkdownUI (chunked lazy render); AsciiDoc via bundled asciidoctor.js in a WKWebView (`Resources/asciidoctor/` — portable assets). Local links open in the workspace; external links go to the system. |
| pdf | PDFKit viewer | read-only |
| image | zoomable image viewer | pixel size / depth / color model metadata |
| video / audio | AVKit players | audio: space = play/pause, title/artist metadata |
| binary | hex viewer | magic-bytes + size metadata |

Text detection: extension first, then UTF-8 probe (NUL byte ⇒ binary),
50 MB ceiling. Untitled documents are backed by temp files (crash-
recovery drafts are written on a debounce).

### 1.3 Editor features (text kind)

- Syntax highlighting for ~100 languages (Highlightr/highlight.js on
  macOS) with **separately selectable light and dark themes**.
- Line numbers ruler; word wrap (⌘⌥W toggles); configurable indentation
  (tabs/spaces + width, auto-detected per file, reformat on change).
- Line endings LF/CRLF/CR: detected, normalized on save, switchable.
- **Completion**: `CompletionEngine` (in core) suggests the shortest
  matching identifier from the document (+ language keywords, toggleable
  in preferences); rendered as inline ghost text, accepted with Tab.
- **Minimap**: color-run overview built off the main thread, viewport
  overlay, click-to-scroll.
- **Status pill** (per-kind): for text shows language · indent · EOL;
  clicking opens a popover to change language (picker), indentation,
  line endings, "use as default" toggles. For media kinds it shows
  metadata instead.
- Editor backgrounds: white / sepia / dark, plus optional **animated
  patterns** (sand, ripples, mist, stars, waves). Low-priority for
  Linux; treat as macOS-distinctive polish.

### 1.4 Tabs

- Pinned vs **preview** tabs: single-click in the tree opens a preview
  (italic title, single slot — next preview replaces it); editing or
  double-click pins it. Untitled tabs are also italic.
- Dirty dot on unsaved tabs; hover reveals a close button (with unsaved-
  changes confirm: Save / Don't Save / Cancel).
- Reorder via ⌘⌥←/→ (and drag). Tab activation persists.

### 1.5 Sidebar file tree

- Lazy directory loading; directories sort first; `.minimal/` hidden.
- **Compacted chains**: a folder whose only child is a folder renders as
  one `parent.child` dotted row.
- Per-type file icons.
- Context menu: New File…, New Folder…, Rename…, Duplicate, Copy, Paste,
  Reveal in Finder, Delete… (to Trash, confirm dialog), Show Revision
  History…, Show Commit History….
- Drag & drop: files dropped from outside copy in; internal drags move;
  open tabs follow renames/moves (`reflectMove`) and close on delete
  (`purgeTabs`).

### 1.6 Search palette

- **Double-shift** anywhere (normal and zen layouts, via
  `QuickSearchHost`) opens a Spotlight-style palette: fuzzy file search
  across the workspace, `:line` jumps, recent files (last 12) when the
  query is empty. Selecting opens the file and scrolls to the line
  (`Document.pendingScrollLine`).

### 1.7 Git & history (all libgit2 via MinimalistCore — no subprocesses)

- **Branch button** (TopBar): shows current branch (short SHA when
  detached); popover lists local branches, checkout, create-branch.
- **Commit History** (per file): read-only log of the *user's* repo for
  that file, with per-commit patch view. Never modifies the user's repo.
- **Revision History** (per file): the app's own two-track history in
  `<workspace>/.minimal/` — autosave snapshots (debounced, ≥60s apart,
  25 kept per file) + mirror commits on every ⌘S and a batch commit at
  quit ("session end"). Sheet lists both merged by date, previews
  content, and can revert (the revert itself autosaves first).

### 1.8 Persistence & app shell

- Multi-window: every window's folder + open tabs + active tab are
  snapshotted at quit and restored on launch (macOS uses security-scoped
  bookmarks — a sandbox artifact Linux doesn't need; plain paths do).
- Recents list (12) feeds the search palette.
- Open File/Folder honor a preference: open in same window vs new window.
- Preferences window: editor font + size, syntax themes (light/dark),
  editor background + pattern, accent color presets with per-element
  tint toggles (tabs, sidebar, …), indentation defaults, completion
  keywords toggle, open-location behavior, glass mode, iCloud pref sync
  (macOS-only).

### 1.9 Keyboard shortcuts (macOS ⌘ ⇒ Linux Ctrl unless noted)

| macOS | Action | Linux |
|---|---|---|
| ⌘N | New untitled tab | Ctrl+N ✓ |
| ⌘⇧N | New window | — (single window for now) |
| ⌘O | Open file | Ctrl+O ✓ |
| ⌘⇧O | Open folder | Ctrl+Shift+O ✓ |
| ⌘S | Save (untitled ⇒ Save As) | Ctrl+S ✓ |
| — | Save As | Ctrl+Shift+S ✓ |
| ⌘W | Close **window** | **Ctrl+Shift+W** — deliberate deviation |
| ⌘⇧W | Close **tab** | **Ctrl+W** — deliberate deviation: GNOME convention is Ctrl+W for tab close |
| ⌘⌥W | Toggle word wrap | Ctrl+Alt+W ✓ |
| ⌘⌃Z | Zen mode | **Ctrl+Alt+Z** (⌘⌃ has no GNOME analogue) ✓ |
| ⌘⌥← / ⌘⌥→ | Move tab left/right | Ctrl+Alt+← / Ctrl+Alt+→ ✓ |
| ⇧⇧ (double-shift) | Search palette | ⇧⇧ ✓, plus **Ctrl+P** as a discoverable alias |
| — | Toggle sidebar | Ctrl+B ✓ |
| — | Preferences | Ctrl+, ✓ |
| — | Keyboard shortcuts window | Ctrl+? ✓ |
| Space | Play/pause (audio viewer) | Handled by GTK's media controls ✓ |

---

## 2. Parity matrix

Status: ✅ done · 🟡 partial · ⬜ not started · ❌ intentionally skipped

| Feature | Linux status | Linux implementation |
|---|---|---|
| Window shell (header bar, split view) | ✅ | Adwaita `HeaderBar` + `OverlaySplitView` replaces the custom titlebar/TopBar; the folder name + branch pill live at the top of the sidebar |
| File tree (expand/collapse, hides `.minimal`) | 🟡 | Flattened `FileRow` list with compacted `parent.child` chains and the macOS monogram chips (`MinimalistCore.FileTypeBadge`). Missing: internal drag-to-move (external file drops do copy in) and live FS watching |
| Tabs (dirty dot, close button, preview, reorder) | ✅ | Pill tab strip; preview tabs are italic single-slot and pin on edit or double-click; Ctrl+Alt+←/→ reorders; closing a dirty tab raises the Save / Don't Save / Cancel `AlertDialog` |
| Text editor + highlighting + line numbers | ✅ | `SourceEditor` (GtkSourceView) with one buffer per open document, so undo, cursor, and scroll survive tab switches |
| Open/save/save-as/new untitled | ✅ | Portal dialogs (`fileImporter`/`folderImporter`/`fileExporter`) |
| Dirty indicator | ✅ | Per-tab `•` plus the window title |
| Git branch display | ✅ | Shared `GitService` |
| Branch popover (checkout / create) | ✅ | Menu off the sidebar's branch pill; create-branch uses an `AlertDialog` + `EntryRow` |
| Minimap | ✅ | **`GtkSourceMap`** docked at the editor's trailing edge; toggle floats over the editor |
| Status pill (language/indent/EOL popover) | ✅ | Bottom-trailing overlay + `Popover` with language / indentation / line-ending pickers and "Use as default" |
| Completion | ✅ | GtkSourceCompletion: a words provider over the document plus a second one fed from core's `LanguageKeywords`. **Deviation:** GNOME's completion list instead of macOS's inline ghost text |
| Word wrap toggle | ✅ | GtkSourceView wrap mode, Ctrl+Alt+W and a preference |
| Search palette (⇧⇧, files + `:line`, recents) | 🟡 | Overlay + `SearchEntry`, fuzzy filename ranking (`WorkspaceSearch`), in-file line matches, `:line` jumps, recents on an empty query. Missing: the macOS `.` folder-browse mode |
| Markdown reader view | ✅ | **Deviation:** a native Markdown → Pango renderer (`MarkdownRenderer`) instead of a WebKit page, which keeps WebKitGTK out of the snap |
| AsciiDoc reader | ⬜ | Would need WebKitGTK + the shared `Resources/asciidoctor/` assets |
| Revision history (autosaves + `.minimal` commits, revert) | ✅ | Core `RevisionTracker`: autosave debounce on edit, mirror commit on save, "session end" commit at quit; dialog lists revisions with preview + revert |
| Commit history (user repo log + patch) | ✅ | Core `GitClient.fileLog`/`patch` in a two-pane dialog |
| Preview tabs (italic, single-slot) | ✅ | `openFile(_:preview:)` mirrors `Workspace.openPreview` |
| Session restore (folder + tabs) | 🟡 | Plain paths in `~/.local/state/m-txt/session.json`, saved on every change. Missing: multiple windows (the Linux app is single-window) |
| Recents | ✅ | Same JSON state file; feeds the palette |
| Preferences window | ✅ | `PreferencesDialog`: editor font, line numbers/minimap/wrap/current line, indentation + line-ending defaults, completion toggles, syntax themes, editor background |
| Media viewers (image/video/audio) | ✅ | `Picture` for images, `GtkVideo` (GStreamer) for audio and video, with GTK's own transport controls |
| PDF viewer | ❌ | Hands the file to the system document viewer rather than shipping poppler |
| Hex viewer | ✅ | Core `HexDump` formatter; the viewer renders the first 64 KB |
| File-tree context menu ops | ✅ | Right-click popover: new file/folder, rename, duplicate, copy path, open folder, revision/commit history, delete. FS work is core `FileOps`; delete uses GIO's trash |
| Editor backgrounds (white/sepia/dark) | ✅ | CSS classes on the source view |
| Multi-window | ⬜ | macOS opens folders/files in new windows; Linux has one window |
| Animated background patterns | ❌ (for now) | macOS-distinctive; revisit after parity elsewhere |
| Accent theming per-element | ❌ (for now) | GNOME accent colors exist system-wide; revisit |
| Glass mode | ❌ | macOS-distinctive (window-server refraction) |
| iCloud preference sync | ❌ | No equivalent; Linux uses local state only |
| Zen mode | ✅ | Hides sidebar, tab strip, and header bar; Escape or the floating button leaves it |

## 3. What's left

1. **Internal drag & drop** in the file tree (move within the workspace).
2. **Multi-window** — window-per-folder plus a `SavedWindows`-style snapshot list.
3. **AsciiDoc reader** (WebKitGTK, sharing `Resources/asciidoctor/`).
4. **Folder-browse mode** (`.`) in the search palette.
5. **Richer media metadata** in the status pill (macOS shows pixel size / depth /
   duration / artist; Linux shows format + size).
6. **Live file-system watching** so the tree refreshes without a manual reload.

## 4. Engineering conventions (see also `CLAUDE.md` here)

- MinimalistCore is the source of truth for document/file/git/revision
  logic. Port by *reusing* it; extend it (public API + tests) when logic
  is missing, rather than re-implementing in the UI layer. It must never
  import UI frameworks and must keep passing `swift test` on both OSes.
- The macOS app is the behavioral reference — when in doubt about an
  interaction detail, read the corresponding file under `Sources/`
  (paths referenced throughout section 1).
- UI state pattern on Linux: Adwaita `@State` holds value snapshots;
  reference models live in `DocumentStore`; every core-model touch goes
  through `onMain {}`.
- Keep deviations deliberate and listed (like Ctrl+W) — GNOME HIG wins
  on input conventions, macOS wins on feature semantics.
