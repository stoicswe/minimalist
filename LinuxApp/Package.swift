// swift-tools-version: 6.0

// Linux front end for {m.txt} — Adwaita for Swift (GTK4/libadwaita) +
// CodeEditor (GtkSourceView) on top of the shared MinimalistCore model
// layer. Built and run on Linux; macOS keeps its own SwiftUI app.
//
// CodeEditor pins adwaita-swift at `branch: "main"`, and SPM forbids a
// versioned dependency graph from containing branch dependencies — so
// both Aparoksha packages are tracked by branch here.
import PackageDescription

let package = Package(
    name: "MinimalistLinux",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../MinimalistCore"),
        .package(url: "https://git.aparoksha.dev/aparoksha/adwaita-swift", branch: "main"),
        .package(url: "https://git.aparoksha.dev/aparoksha/codeeditor", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Minimalist",
            dependencies: [
                .product(name: "MinimalistCore", package: "MinimalistCore"),
                .product(name: "Adwaita", package: "adwaita-swift"),
                .product(name: "CodeEditor", package: "codeeditor"),
            ],
            swiftSettings: [
                // Adwaita for Swift predates strict concurrency: its View
                // protocol requirements are nonisolated, while
                // MinimalistCore's model classes are @MainActor. GTK is
                // strictly single-threaded (everything runs on the main
                // thread), so the app bridges with MainActor.assumeIsolated
                // (see DocumentStore.onMain) and compiles in Swift 5 mode
                // until the toolkit adopts Swift 6 isolation.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
