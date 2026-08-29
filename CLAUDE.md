# {m.txt} / Minimalist

Minimal text editor. One repo, two native front ends sharing one model layer:

| Directory | What it is | Toolchain |
|---|---|---|
| `Sources/` + `Resources/` | macOS app (SwiftUI + AppKit) | Xcode via `xcodegen generate`; Swift 6 language mode, MainActor-default isolation |
| `MinimalistCore/` | Shared platform-neutral model layer (SPM package) | Swift 6, **no AppKit/SwiftUI/Combine imports allowed — must compile on Linux** |
| `LinuxApp/` | Linux app (Adwaita for Swift + GtkSourceView) | Swift 6.2+, libadwaita ≥ 1.7 — see `LinuxApp/CLAUDE.md` |
| `snap/` | Snap package (`m-txt`, base core26) | Built by `.github/workflows/linux.yml` |

Rules that keep the split working:

- Model/logic code goes in `MinimalistCore` (public API, cross-platform); UI and platform services stay in the respective app. If you're porting a macOS feature to Linux and find logic living in `Sources/`, prefer moving it into the core so both apps share it.
- `MinimalistCore` uses `@Observable` (Observation), never Combine's `ObservableObject` — Combine doesn't exist on Linux.
- Run core tests with `swift test --package-path MinimalistCore` — they must pass on macOS **and** Linux.
- macOS builds: `xcodegen generate` after adding/removing files, then build the `m.txt` scheme. CI: `.github/workflows/ci.yml` (macOS), `linux.yml` (Ubuntu 26.04 + snap).
- Feature parity between the two apps is a goal: `LinuxApp/PORTING.md` is the canonical macOS feature spec and Linux parity tracker — update its matrix when you port something.
