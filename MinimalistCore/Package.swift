// swift-tools-version: 6.0

// Platform-neutral model layer shared by the macOS app (and, later, a
// Linux front end). Nothing in here may import AppKit, SwiftUI, or any
// other Apple-only UI framework — Foundation, Observation, and libgit2
// only.
import PackageDescription

let package = Package(
    name: "MinimalistCore",
    platforms: [
        // Floor for the @Observable macro; the app itself targets newer.
        .macOS(.v14)
    ],
    products: [
        .library(name: "MinimalistCore", targets: ["MinimalistCore"])
    ],
    dependencies: [
        // libgit2 compiled from source via SPM. Replaces /usr/bin/git
        // subprocesses, which App Sandbox (required for TestFlight / Mac
        // App Store) forbids. GPLv2 with linking exception — safe to embed.
        .package(url: "https://github.com/ibrahimcetin/libgit2.git", exact: "1.9.2")
    ],
    targets: [
        .target(
            name: "MinimalistCore",
            dependencies: [
                .product(name: "libgit2", package: "libgit2")
            ]
        ),
        .testTarget(
            name: "MinimalistCoreTests",
            dependencies: ["MinimalistCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
