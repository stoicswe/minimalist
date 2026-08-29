# {m.txt} for Linux

GTK4/libadwaita front end for the Minimalist text editor, sharing the
[`MinimalistCore`](../MinimalistCore) model layer with the macOS app.
Built with [Adwaita for Swift](https://git.aparoksha.dev/aparoksha/adwaita-swift)
and [CodeEditor](https://git.aparoksha.dev/aparoksha/codeeditor)
(GtkSourceView).

## v1 scope

- File-tree sidebar (expand/collapse, hides `.minimal/`)
- Tabs, editor with syntax highlighting + line numbers (GtkSourceView)
- Open file / open folder / new untitled / save / save-as (Ctrl+O /
  Ctrl+Shift+O / Ctrl+N / Ctrl+S), close tab (Ctrl+W)
- Git branch display for the open folder (libgit2, shared `GitService`)

Not yet ported: media viewers, markdown/asciidoc readers, revision
history, zen mode, minimap, preferences, unsaved-changes prompts.

## Requirements

- **Swift 6.2+** (the Aparoksha packages' manifests require it). Ubuntu's
  `apt install swiftlang` is 6.1 as of 26.04 — install the
  [swift.org toolchain](https://www.swift.org/install/linux/) instead
  (the Ubuntu 24.04 tarball runs fine on newer releases).
- **libadwaita ≥ 1.7** (`AdwToggleGroup` and friends) — Ubuntu 25.04+;
  26.04 ships 1.9. Ubuntu 24.04's libadwaita 1.5 is too old.
- GTK stack: `sudo apt install pkg-config libadwaita-1-dev libgtksourceview-5-dev`

## Build & run (on the Linux machine)

```sh
cd LinuxApp
swift build
swift run Minimalist
```

## Container build check (no Linux machine needed)

Compiles for Linux from any Docker host — see
[dev-container/Dockerfile](dev-container/Dockerfile) for why this image
exists instead of the official `swift:*` ones:

```sh
docker build -t minimalist-linux-dev LinuxApp/dev-container
docker run --rm -v "$PWD:/src" -w /src/LinuxApp minimalist-linux-dev \
  swift build --scratch-path .build-linux
```
