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

- `Sources/Minimalist/Main.swift` — `@main` App + Window scene.
- `Sources/Minimalist/MainView.swift` — the whole v1 UI + interaction
  logic (header bar, sidebar tree, tab strip, editor, dialogs).
- `Sources/Minimalist/DocumentStore.swift` — `@MainActor` singleton that
  owns `Document`/`FileNode` instances and per-document baselines, plus
  the `onMain {}` bridge (see below). Adwaita `@State` holds value
  snapshots (`FileRow`, `EditorTab`); reference-typed model state lives
  here.
- `Sources/Minimalist/LanguageMap.swift` — core language ids
  (highlight.js naming) → GtkSourceView `Language` cases.
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

### Shared-core discipline

Logic belongs in `../MinimalistCore` (pure Foundation + Observation +
libgit2; never AppKit/SwiftUI/GTK). If porting a macOS feature reveals
logic still living in the macOS app's `Sources/`, move it into the core
package (make it `public`, keep macOS building) rather than duplicating
it here. Add cross-platform tests to `MinimalistCore/Tests/`.
