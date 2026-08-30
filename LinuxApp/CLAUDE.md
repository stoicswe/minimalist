# LinuxApp — working notes for Claude

GTK4/libadwaita front end for {m.txt}, built with
[Adwaita for Swift](https://git.aparoksha.dev/aparoksha/adwaita-swift) and
[CodeEditor](https://git.aparoksha.dev/aparoksha/codeeditor) (GtkSourceView)
on top of the shared `../MinimalistCore` package.

**Read `PORTING.md` first** — it is the canonical spec of the macOS app's
features and layout, and the parity matrix this app is built against.
Update its matrix when you port something.

## Build / test / run (on this Ubuntu machine)

```sh
sudo apt install pkg-config libadwaita-1-dev libgtksourceview-5-dev
swift build                       # from LinuxApp/
swift run Minimalist              # launches the app
swift test --package-path ../MinimalistCore   # shared-core tests (must stay green)
```

Requirements (hard, discovered the annoying way):
- **Swift ≥ 6.2** — the Aparoksha package manifests demand it. Ubuntu's
  `apt install swiftlang` is 6.1: too old. Install the swift.org
  toolchain (the ubuntu24.04 tarball runs on newer releases; on 26.04 it
  needs a libxml2 compat symlink — see `dev-container/Dockerfile` for
  the exact recipe).
- **libadwaita ≥ 1.7** (Ubuntu 25.04+; 26.04 ships 1.9) — the generated
  bindings call `adw_toggle_group_*` etc. directly.
- Snap build: `snapcraft` at repo root (yaml in `../snap/`), or push to
  main/release/* and let `.github/workflows/linux.yml` build it.

## Architecture

- `Sources/Minimalist/Main.swift` — `@main` App + Window scene, window
  shortcuts, and the close hook that writes the session.
- `Sources/Minimalist/MainView.swift` — the window shell: all `@State`,
  the split view, and the dialog stack. Its areas live in extensions:
  `MainView+HeaderBar/Sidebar/Content/Actions/Search/History/`
  `Preferences/Style.swift`.
- `Sources/Minimalist/DocumentStore.swift` — `@MainActor` singleton that
  owns `Document`/`FileNode`/`RevisionTracker`, recents, settings, and
  the session snapshot, plus the `onMain {}` bridge (see below). Adwaita
  `@State` holds value snapshots (`FileRow`, `EditorTab`).
- `Sources/Minimalist/Editor/SourceEditor.swift` — the editor widget:
  GtkSourceView written against the C API (the upstream `CodeEditor`
  widget only does text + line numbers). Keeps one buffer per open
  document so undo, cursor, and scroll survive tab switches.
- `Sources/Minimalist/Editor/MinimapArea.swift` — the minimap, drawn with
  cairo on a `GtkDrawingArea`. Not `GtkSourceMap`: that renders the
  document at a 1pt font and scrolls, so a long file never fits, while
  the macOS minimap scales the *whole* file into the strip.
- `Sources/Minimalist/Support/GTKBridge.swift` — raw GTK the toolkit
  doesn't wrap: typed signal connections, the key controller behind ⇧⇧,
  right-click / double-click gestures, GIO trash, URI launching.
- `Sources/Minimalist/State/AppState.swift` — settings
  (`~/.config/m-txt/settings.json`) and session
  (`~/.local/state/m-txt/session.json`).
- `Sources/Minimalist/Viewers/` — `MarkdownRenderer` (Markdown → Pango
  markup for the reader view) and `MediaPlayer` (GtkVideo).
- `Sources/Minimalist/LanguageMap.swift` — core language ids
  (highlight.js naming) → GtkSourceView language ids, resolved against
  what the installed library actually ships.
- `snap-assets/minimalist-launch` — snap runtime env plumbing; delete
  when the gnome snapcraft extension supports core26.

### Concurrency model

The target compiles in **Swift 5 language mode** deliberately: Adwaita's
`View` protocol is nonisolated while `MinimalistCore`'s classes are
`@MainActor`. GTK is strictly single-threaded, so bridging with
`onMain { ... }` (`MainActor.assumeIsolated`) is sound. Wrap every
`Document`/`FileNode`/`RevisionTracker` touch in `onMain`; keep the
values you pass in/out `Sendable` snapshots.

### Toolkit gotchas (Adwaita for Swift is 0.x)

- Both Aparoksha deps are pinned `branch: "main"` — CodeEditor forces
  this (SPM forbids versioned→branch graphs). Expect occasional upstream
  API churn on `swift package update`.
- Modifier order matters: most modifiers (`.style`, `.padding`, …) type-
  erase to `AnyView`; widget-specific modifiers (`Button.keyboardShortcut`,
  `CodeEditor.language`, …) must be applied **before** any erasing one.
- When an API is unclear, **clone the upstream repos and read the source**
  — that is the documentation. `Sources/Demo/` in adwaita-swift and
  `Tests/main.swift` in codeeditor are working examples of nearly every
  pattern. Also `aparoksha/meta` (the `@State`/`Binding`/`Signal` layer).
- `Signal()` + `.signal()` triggers `fileImporter` / `folderImporter` /
  `fileExporter` dialogs (portal-backed).
- **`@State` writes inside `onAppear` are discarded.** `onAppear` runs
  while the view's storage is still being built, so the initial values
  win. Defer the work one main-loop turn — `.onAppear { Idle { … } }` —
  as `MainView` does for session restore.
- **Each `@State` write re-renders immediately.** Two related writes in
  one handler produce an intermediate render with mismatched values, so
  don't split one fact across two `@State`s (the editor binds straight
  through to its `Document` rather than mirroring the text in view
  state, which is why).
- **Every dialog needs its own `id`.** The dialog modifiers all share
  the view's `ViewStorage` and park their widget under `"dialog" + id`,
  so two dialogs without ids overwrite each other and the second never
  presents. `aboutDialog` takes no id and always uses the bare key, so
  leave that one to it.
- **`preferencesDialog` / `shortcutsDialog` are unusable as-is** (as of
  this checkout): on close they `g_object_unref` pages they don't own
  *and* never clear their storage slot, so the dialog can't reopen and
  the freed objects spray GObject criticals. Build those on the plain
  `dialog(visible:title:id:width:height:)` with `PreferencesPage` /
  `FormSection` content instead — see `MainView+Preferences.swift`.
- **`PreferencesGroup` has no public `init()`** — use its `FormSection`
  alias: `FormSection("Title") { rows }`.
- **`.overlay { }` twice replaces, it doesn't nest** — the second call
  lands on the `Overlay` widget's own `overlay` property. Put every
  floating element in one `.overlay`.
- **Every overlay child needs its own `halign`/`valign`.** A bare `if` at
  the top level of an overlay's `ViewBuilder` becomes a `GtkStack` that
  fills the pane; being invisible doesn't stop it from swallowing the
  clicks and scroll events meant for the widgets underneath. Wrap
  conditionals in an always-present aligned container.
- **`ViewStorage(pointer)` must hold an `OpaquePointer`.** Its
  `opaquePointer` accessor is a conditional cast, so storing a typed
  `UnsafeMutablePointer` silently yields `nil` later — call `.opaque()`
  when storing, `.cast()` when calling back into C. Which of the two a
  GTK function wants varies by type; the compiler is the oracle.

### Shared-core discipline

Logic belongs in `../MinimalistCore` (pure Foundation + Observation +
libgit2; never AppKit/SwiftUI/GTK). If porting a macOS feature reveals
logic still living in the macOS app's `Sources/`, move it into the core
package (make it `public`, keep macOS building) rather than duplicating
it here. Add cross-platform tests to `MinimalistCore/Tests/`.
