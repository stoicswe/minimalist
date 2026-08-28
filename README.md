# {m.Txt}: Minimal Text Editor (Minimalist)
The text editor for the rest of us. No AI, no excess, no plugins or agents.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/dark_mode.png">
  <source media="(prefers-color-scheme: light)" srcset="docs/screenshots/light_mode.png">
  <img alt="Minimalist editor" src="docs/screenshots/light_mode.png">
</picture>

<a href="https://apps.apple.com/us/app/m-txt-minimal-text-editor/id6764609511?mt=12&itscg=30200&itsct=apps_box_badge&mttnsubad=6764609511" style="display: inline-block;"> <img src="https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/black/en-us?releaseDate=1787875200" alt="Download on the App Store" style="width: 244px; height: 82px; vertical-align: middle; object-fit: contain;" /></a>
    

A minimalist text editor for macOS. SwiftUI on top and native AppKit running in the background for a simple user interface.

## Features

- Syntax highlighting for 100+ languages (Highlightr) with selectable light/dark themes
- Markdown rendering with toggleable reader view (swift-markdown-ui)
- Multi-tab, multi-window editing with persistent session recovery
- Git integration: branch display, commit history, per-file revision tracking
- File-tree sidebar with context menus and file-type icons
- Zen mode (`⌘⌃Z`) hides sidebar, tabs, and chrome
- Double-shift command palette for fast file and line jumps
- Code completion using language keywords and identifiers in the current document
- Minimap, external scrollbar, line numbers, word wrap, configurable indentation
- Editor backgrounds (white, sepia, dark) with optional animated patterns: sand, ripples, mist, stars, waves
- Accent color theming with per-element tint toggles
- Glass mode — window-level refraction with a floating tab bar
- iCloud sync for appearance and editor preferences across your Macs

## Requirements

- macOS 26 or later
- Xcode 16+ to build from source
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to regenerate the project

## Install

Grab the latest signed and notarized `.app` from the [Releases](https://github.com/stoicswe/minimalist/releases) page, unzip it, and drag it into `/Applications`.

## Build from source

```sh
git clone https://github.com/stoicswe/minimalist.git
cd minimalist
xcodegen generate
open Minimalist.xcodeproj
```

## License
[MIT](LICENSE) © Nathaniel Knudsen
