# {m.txt} for Linux

GTK4/libadwaita front end for the Minimalist text editor, sharing the
[`MinimalistCore`](../MinimalistCore) model layer with the macOS app.
Built with [Adwaita for Swift](https://git.aparoksha.dev/aparoksha/adwaita-swift),
with the editor written directly against GtkSourceView (via the
[CodeEditor](https://git.aparoksha.dev/aparoksha/codeeditor) package's
system-library target).

## What it does

The Linux app tracks the macOS one feature-for-feature, in GNOME idioms
(see [PORTING.md](PORTING.md) for the full parity matrix):

- File-tree sidebar: compacted `parent.child` chains, the same colored
  file-type monograms as macOS, right-click menu (new file/folder,
  rename, duplicate, copy path, delete to trash, revision & commit
  history), and drag-and-drop import
- Tabs with dirty dots, close buttons, italic single-slot preview tabs,
  reorder (Ctrl+Alt+←/→), and an unsaved-changes prompt on close
- GtkSourceView editor: syntax highlighting, line numbers, a **minimap**
  that scales the whole file (click or drag it to scroll), word wrap,
  per-file indentation and line endings,
  light/dark syntax themes, editor backgrounds, and completion from the
  document plus the language's keywords
- Status pill (language · indentation · line endings) with a popover to
  change any of them, or set them as the default
- Double-shift (or Ctrl+P) search palette: fuzzy file search, `:line`
  jumps, in-file matches, recents
- Git: branch pill with checkout / create-branch, per-file commit
  history with patches, and the app's own `.minimal/` revision history
  (autosaves + save/quit commits) with preview and revert
- Markdown reader view, image / audio / video viewers, hex viewer
- Zen mode (Ctrl+Alt+Z), preferences, and session restore (folder, tabs,
  active tab, recents) under `~/.local/state/m-txt/`
- An About dialog (primary menu) with the project blurb, contacts,
  license, and a Sponsor link in place of the macOS tip jar

Not yet ported: AsciiDoc reader, multi-window, internal drag-to-move in
the tree, and the macOS-only extras (glass mode, animated editor
backgrounds, iCloud sync). PDFs open in the system document viewer.

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

## Publishing to the Snap Store

CI builds the snap for amd64 and arm64 on every push to `main` and
`release/*` (`.github/workflows/linux.yml`), and publishes it once the
store credentials are in place:

| Branch | Channel |
|---|---|
| `main` | `beta` |
| `release/*` | `stable` |

Both builds also upload the `.snap` as a workflow artifact, so the
pipeline keeps working unchanged on forks and before the store is set up
— the publish step is skipped whenever the credentials secret is absent.

One-time setup, from a machine with `snapcraft` installed:

```sh
# The name must match `name:` in snap/snapcraft.yaml and the name you
# registered at https://snapcraft.io/account/register-snap
snapcraft login
snapcraft export-login --snaps m-txt \
  --acls package_access,package_push,package_update,package_release \
  --expires 2027-01-01 \
  -
```

Copy the whole block it prints into a repository secret named
`SNAPCRAFT_STORE_CREDENTIALS` (Settings → Secrets and variables →
Actions). The credentials expire on the date given; when the publish
step starts failing to authenticate, re-export and update the secret.

The snap's version comes from `git describe --tags --always`, so tag
release commits (`git tag v1.0.1`) to get a readable version in the
store listing rather than a bare commit SHA.

## Container build check (no Linux machine needed)

Compiles for Linux from any Docker host — see
[dev-container/Dockerfile](dev-container/Dockerfile) for why this image
exists instead of the official `swift:*` ones:

```sh
docker build -t minimalist-linux-dev LinuxApp/dev-container
docker run --rm -v "$PWD:/src" -w /src/LinuxApp minimalist-linux-dev \
  swift build --scratch-path .build-linux
```
