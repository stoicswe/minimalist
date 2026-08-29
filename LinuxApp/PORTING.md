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

| macOS | Action | Linux v1 today |
|---|---|---|
| ⌘N | New untitled tab | Ctrl+N ✓ |
| ⌘⇧N | New window | — |
| ⌘O | Open file | Ctrl+O ✓ |
| ⌘⇧O | Open folder | Ctrl+Shift+O ✓ |
| ⌘S | Save (untitled ⇒ Save As) | Ctrl+S ✓ |
| ⌘W | Close **window** | — (window close button) |
| ⌘⇧W | Close **tab** | **Ctrl+W** — deliberate deviation: GNOME convention is Ctrl+W for tab close. Decide & document. |
| ⌘⌥W | Toggle word wrap | — |
| ⌘⌃Z | Zen mode | — |
| ⌘⌥← / ⌘⌥→ | Move tab left/right | — |
| ⇧⇧ (double-shift) | Search palette | — |
| Space | Play/pause (audio viewer) | — |

---

## 2. Parity matrix

Status: ✅ done · 🟡 partial · ⬜ not started · ❌ intentionally skipped

| Feature | Linux status | Linux strategy |
|---|---|---|
| Window shell (header bar, split view) | ✅ | Adwaita `HeaderBar` + `OverlaySplitView` replaces custom titlebar/TopBar |
| File tree (expand/collapse, hides `.minimal`) | 🟡 | Flattened `FileRow` list; missing: icons, compacted chains, context menu, drag & drop, live reload on FS changes |
| Tabs | 🟡 | `ToggleGroup` strip; missing: dirty dot per tab, close button per tab, preview tabs, reorder, unsaved-changes prompt |
| Text editor + highlighting + line numbers | ✅ | `CodeEditor` (GtkSourceView) — themes via GtkSourceView style schemes |
| Open/save/save-as/new untitled | ✅ | Portal dialogs (`fileImporter`/`folderImporter`/`fileExporter`) |
| Dirty indicator | 🟡 | Window title `•` only (active tab) |
| Git branch display | ✅ | Shared `GitService` |
| Branch popover (checkout / create) | ⬜ | `Popover` or `MenuButton` off the header bar |
| Minimap | ⬜ | **`GtkSourceMap`** — GtkSourceView's built-in minimap; bind to the same buffer |
| Status pill (language/indent/EOL popover) | ⬜ | Bottom overlay + `Popover`; pickers write through to `Document` |
| Completion (ghost text, keywords toggle) | ⬜ | GtkSourceCompletion provider fed by core `CompletionEngine` |
| Word wrap toggle | ⬜ | GtkSourceView wrap-mode property + shortcut |
| Search palette (⇧⇧, files + `:line`, recents) | ⬜ | Overlay + `SearchEntry`; needs a key-event hook for double-shift (GTK `EventControllerKey`) |
| Markdown reader view | ⬜ | Options: WebKitGTK page (closest to AsciiDoc path) or native widgets; toggle button appears for md/adoc only |
| AsciiDoc reader | ⬜ | WebKitGTK + the same `Resources/asciidoctor/` assets (share them — move to a common location) |
| Revision history (autosaves + `.minimal` commits, revert) | ⬜ | Core `RevisionTracker` is ready & tested; wire autosave debounce + ⌘S-commit hooks into save/edit paths, then a dialog for the list/preview/revert |
| Commit history (user repo log + patch) | ⬜ | Core `GitClient.fileLog`/`patch` ready; needs dialog UI |
| Preview tabs (italic, single-slot) | ⬜ | Port `Workspace.openPreview` semantics into the Linux tab layer |
| Session restore (folder + tabs per window) | ⬜ | Plain paths (no bookmarks); store JSON under `~/.local/state/m-txt/` rather than UserDefaults |
| Recents | ⬜ | Same JSON state file |
| Preferences window | ⬜ | `PreferencesDialog`/`PreferencesPage` (Adwaita has these); scope: font+size, syntax themes, indent defaults, keywords toggle, open-location behavior |
| Media viewers (image/video/audio) | ⬜ | GStreamer (GTK4 `Gtk.Video`/`MediaFile`); image via `Picture` |
| PDF viewer | ⬜ | poppler-glib, or ❌ v1 |
| Hex viewer | ⬜ | Monospace `TextEditor` rendering of hex dump (core can supply the formatter) |
| File-tree context menu ops | ⬜ | Core-worthy: move `FileOperations`' pure-FS parts (rename/duplicate/unique-name/copy/move) into MinimalistCore, leaving only dialogs + trash per-platform (Linux trash: GIO / `gio trash`) |
| Editor backgrounds (sepia/dark) | ⬜ | CSS providers on the source view |
| Animated background patterns | ❌ (for now) | macOS-distinctive; revisit after parity elsewhere |
| Accent theming per-element | ❌ (for now) | GNOME accent colors exist system-wide; revisit |
| Glass mode | ❌ | macOS-distinctive (window-server refraction) |
| iCloud preference sync | ❌ | No equivalent; Linux uses local state only |
| Zen mode | ⬜ | Hide sidebar + tab strip (`OverlaySplitView.visible`, collapse toolbar); fullscreen optional |

## 3. Suggested porting order

1. **Tabs to parity** (dirty dots, close buttons, preview semantics,
   unsaved-changes dialog — `AlertDialog`) and **sidebar context menu**
   (move pure-FS ops into core first).
2. **Session restore + recents** (unblocks daily-driver use).
3. **Minimap (`GtkSourceMap`) + status pill + word wrap** (editor feel).
4. **Search palette** (double-shift, file/line jump).
5. **Revision history + commit history** (core is done; UI only).
6. **Branch popover** (checkout/create).
7. **Readers** (markdown, asciidoc via WebKitGTK).
8. **Preferences dialog**, then viewers (image/audio/video/hex/pdf).

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
