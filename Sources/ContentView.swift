import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var workspace: Workspace

    /// Reserved strip at the leading edge of the sidebar so the manually
    /// positioned traffic-light buttons (see `TightTitlebarController`) have
    /// somewhere to live without overlapping content. Sized to clear the
    /// buttons (origin y=7 + ~14pt button) plus extra breathing room so
    /// the sidebar header isn't kissing the close-button row.
    private let titleBarReservedHeight: CGFloat = 38

    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @AppStorage(PreferenceKeys.zenMode) private var zenMode: Bool = false
    @AppStorage(PreferenceKeys.editorBackgroundOverride) private var editorBgOverride: Bool = false
    @AppStorage(PreferenceKeys.editorBackgroundLight) private var editorBgLight: String = "white"
    @AppStorage(PreferenceKeys.editorBackgroundDark) private var editorBgDark: String = "dark"
    @AppStorage(PreferenceKeys.colorScheme) private var colorSchemePref: String = "system"
    @AppStorage(PreferenceKeys.accentPresetID) private var accentID: String = AccentPresets.defaultID
    @AppStorage(PreferenceKeys.accentTintSidebar) private var accentTintSidebar: Bool = false
    @AppStorage(PreferenceKeys.editorBackgroundPattern) private var bgPatternRaw: String = "none"
    @AppStorage(PreferenceKeys.editorBackgroundPatternAnimated) private var bgPatternAnimated: Bool = false
    @AppStorage(PreferenceKeys.editorBackgroundPatternSpeed) private var bgPatternSpeed: Double = 1.0
    @Environment(\.colorScheme) private var environmentColorScheme

    /// In Glass mode the panes are fully see-through (their solid color
    /// overlay disappears) and the window-level visual-effect view kicks in
    /// at a light material. In Solid mode everything stays opaque and the
    /// VEV is removed entirely.
    private var paneTransparency: Double { windowGlass ? 1.0 : 0.0 }
    private var windowBlurLevel: Double { windowGlass ? 0.10 : 0.0 }

    /// When the user has enabled the editor-background override, the
    /// chosen color always wins — even in glass mode — so transparency
    /// snaps to 0 for the editor pane only.
    private var editorPaneTransparency: Double {
        editorBgOverride ? 0.0 : paneTransparency
    }

    /// Resolves the editor pane's base color: the user's chosen preset
    /// when the override is on, else the system `textBackgroundColor`.
    private var editorPaneBaseColor: Color {
        if editorBgOverride {
            let isDark = isDarkAppearance
            let key = isDark ? editorBgDark : editorBgLight
            let option = EditorBackgroundOption(rawValue: key) ?? (isDark ? .dark : .white)
            return option.color
        }
        return Color(nsColor: .textBackgroundColor)
    }

    /// Whether the editor pane is currently rendering on a dark surface.
    /// Used as the source of truth for tabs, corner buttons, etc. so they
    /// adapt to a forced-light/dark background even when it doesn't match
    /// the app appearance.
    private var editorSurfaceIsDark: Bool {
        guard editorBgOverride else { return isDarkAppearance }
        let raw = isDarkAppearance ? editorBgDark : editorBgLight
        return raw == "dark"
    }

    /// Resolves to the chosen pattern enum, falling back to `.none` for
    /// any stale or unknown value.
    private var editorBackgroundPattern: EditorBackgroundPattern {
        EditorBackgroundPattern(rawValue: bgPatternRaw) ?? .none
    }

    /// Pattern overlay layered between the editor's pane background and
    /// the editor itself. Returns an empty view when the pattern is set
    /// to `.none` so it adds zero render cost in the default case.
    /// Clipped so any path that strokes outside the pane (rain wall
    /// reflections, sand-garden swirls extending past the edge) stays
    /// trimmed and never propagates up into the editor's intrinsic size,
    /// which used to coax NSScrollView into showing a horizontal
    /// scroller even with word wrap on.
    @ViewBuilder
    private var editorBackgroundPatternOverlay: some View {
        if editorBackgroundPattern != .none {
            EditorBackgroundPatternView(
                pattern: editorBackgroundPattern,
                animated: bgPatternAnimated,
                speed: bgPatternSpeed,
                isDarkSurface: editorSurfaceIsDark,
                accent: AccentPresets.preset(forID: accentID).color
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)
        }
    }

    /// Subtle accent wash drawn on top of the sidebar's pane background.
    /// Light mode gets a pastel-strength tint so the sidebar feels
    /// touched-by-the-accent without overpowering the file tree; dark
    /// mode gets a richer alpha because the dark background absorbs
    /// more of the colored layer.
    @ViewBuilder
    private var sidebarAccentWash: some View {
        if accentTintSidebar {
            let accent = AccentPresets.preset(forID: accentID).color
            let alpha: Double = isDarkAppearance ? 0.22 : 0.10
            accent.opacity(alpha)
                .allowsHitTesting(false)
        }
    }

    private var isDarkAppearance: Bool {
        switch colorSchemePref {
        case "dark":  return true
        case "light": return false
        default:      return environmentColorScheme == .dark
        }
    }

    var body: some View {
        QuickSearchHost {
            Group {
                if zenMode {
                    zenLayout
                } else {
                    normalLayout
                }
            }
        }
        .background(WindowConfigurator(blur: windowBlurLevel))
    }

    /// Zen mode: just the editor + double-shift search. No sidebar, tabs,
    /// status pill, or overlay buttons.
    private var zenLayout: some View {
        ZStack {
            editorPaneBaseColor
                .opacity(editorPaneTransparency == 0 ? 1 : 0)
                .ignoresSafeArea()
            PaneBackground(
                baseColor: editorPaneBaseColor,
                transparency: editorPaneTransparency
            )
            .ignoresSafeArea()
            editorBackgroundPatternOverlay
                .ignoresSafeArea()
            ZenModeView()
                .padding(.top, titleBarReservedHeight)
        }
        .environment(\.editorSurfaceIsDark, editorSurfaceIsDark)
    }

    @ViewBuilder
    private var normalLayout: some View {
        ZStack {
            // Base coverage layer — fills any gaps (notably the HSplitView
            // divider seam) so they aren't transparent in Solid mode. In
            // Glass mode the layer is transparent and the window-level VEV
            // blur shows through everywhere uniformly.
            Color(nsColor: .windowBackgroundColor)
                .opacity(paneTransparency == 0 ? 1 : 0)
                .ignoresSafeArea()

            HSplitView {
                // Sidebar column: pane background as a ZStack sibling so it
                // fully extends to the window's top edge under
                // .ignoresSafeArea (a `.background(...)` modifier here
                // doesn't always extend).
                ZStack(alignment: .topLeading) {
                    PaneBackground(
                        baseColor: Color(nsColor: .windowBackgroundColor),
                        transparency: paneTransparency
                    )
                    sidebarAccentWash
                    VStack(spacing: 0) {
                        Color.clear.frame(height: titleBarReservedHeight)
                        TopBar()
                        FileTreeView()
                    }
                }
                .frame(minWidth: 180, idealWidth: 240)
                .ignoresSafeArea(.container, edges: .top)

                // Editor column: tabs sit at the very top of the window,
                // no strip above them.
                ZStack(alignment: .topLeading) {
                    PaneBackground(
                        baseColor: editorPaneBaseColor,
                        transparency: editorPaneTransparency
                    )
                    editorBackgroundPatternOverlay
                    EditorContainer()
                }
                .environment(\.editorSurfaceIsDark, editorSurfaceIsDark)
                .frame(minWidth: 400)
                .layoutPriority(1)
                .ignoresSafeArea(.container, edges: .top)
            }
        }
    }
}

/// Configures the underlying NSWindow so content extends edge-to-edge,
/// hides the title bar entirely, repositions the traffic-light buttons,
/// and applies the user's window-level blur setting.
private struct WindowConfigurator: NSViewRepresentable {
    let blur: Double

    func makeNSView(context: Context) -> ConfigNSView {
        let view = ConfigNSView()
        view.blur = blur
        return view
    }

    func updateNSView(_ nsView: ConfigNSView, context: Context) {
        nsView.blur = blur
        // Window config is safe synchronously; only the VEV swap needs the
        // async hop to avoid re-entering the SwiftUI hosting view.
        if let window = nsView.window {
            TightTitlebarController.shared.attach(to: window)
        }
        DispatchQueue.main.async {
            nsView.applyBlur()
        }
    }

    /// Custom NSView with a `viewDidMoveToWindow` override so the saved
    /// blur state is applied at launch — `updateNSView` first fires before
    /// the view has a window, and the initial value would otherwise be lost
    /// until the user toggles the setting again.
    final class ConfigNSView: NSView {
        var blur: Double = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Configure the window synchronously so SwiftUI lays out with
            // `isOpaque=false`, `fullSizeContentView`, etc. from the very
            // first pass — otherwise the panes leave a transparent gap at
            // the top until the next layout cycle.
            if let window {
                TightTitlebarController.shared.attach(to: window)
            }
            // Only the VEV install/remove (which swaps `window.contentView`)
            // must be deferred — doing that synchronously inside this
            // callback re-enters the SwiftUI hosting view we live in and
            // AppKit aborts.
            DispatchQueue.main.async { [weak self] in
                self?.applyBlur()
            }
        }

        func applyToWindow() {
            guard let window else { return }
            TightTitlebarController.shared.attach(to: window)
            applyBlur()
        }

        func applyBlur() {
            guard let window else { return }
            TightTitlebarController.shared.setWindowBlur(blur, in: window)
        }
    }
}

private struct EditorContainer: View {
    @EnvironmentObject var workspace: Workspace
    /// Per-document toggle for the markdown reader view. Keyed by document
    /// id so each tab remembers its own mode while it's open.
    @State private var readerEnabled: [Document.ID: Bool] = [:]
    /// Application-wide toggle for the minimap side view, persisted across
    /// sessions so the user's choice sticks.
    @AppStorage(PreferenceKeys.showMinimap) private var showMinimap: Bool = false
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false

    /// Height of the tab bar — used as the editor's top content inset in
    /// glass mode so content scrolls behind the floating tab strip
    /// without putting cursor or first lines under the bar.
    private let tabBarHeight: CGFloat = 36

    @State private var isDropTarget = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if workspace.openDocuments.isEmpty {
                if workspace.rootNode == nil {
                    EmptyState()
                } else {
                    WatermarkBackground()
                }
            } else if windowGlass {
                // Glass: editor takes the full pane height and the tab
                // bar floats on top via `.overlay` so refraction in the
                // tab strip samples the editor content scrolling under it.
                activeContentView
                    .overlay(alignment: .top) {
                        TabBar()
                    }
            } else {
                VStack(spacing: 0) {
                    TabBar()
                    activeContentView
                }
            }

            // StatusPill dispatches by document kind internally — the
            // text editor sees language / indent / EOL, every other
            // kind sees its own metadata readout (dimensions, codec,
            // duration, magic bytes, etc.).
            if workspace.activeDocument != nil {
                StatusPill()
                    .padding(14)
            }

            if isDropTarget {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.06))
                    )
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            handleEditorDrop(providers: providers)
        }
    }

    private func handleEditorDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = resolveDroppedFileURL(from: item) else { return }
                // Skip directories — only files become tabs.
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard !isDirectory else { return }
                DispatchQueue.main.async {
                    workspace.open(url: url)
                }
            }
        }
        return accepted
    }

    @StateObject private var minimapBridge = MinimapBridge()

    @ViewBuilder
    private var activeContentView: some View {
        if let doc = workspace.activeDocument {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    primaryContent(for: doc)
                    if showMinimap && doc.kind == .text {
                        Divider()
                        MinimapView(document: doc, bridge: minimapBridge)
                            .frame(width: 96)
                            .background(Color.primary.opacity(0.02))
                    }
                    // External scrollbar pinned at the far-right edge so it
                    // sits past the minimap (when shown) instead of getting
                    // sandwiched between the editor and minimap. Specialized
                    // viewers manage their own scrolling, so we drop it
                    // entirely for non-text kinds.
                    if doc.kind == .text {
                        EditorScrollbar(bridge: minimapBridge)
                            .frame(width: 11)
                    }
                }
                HStack(spacing: 8) {
                    if DocumentKindDetector.supportsReaderView(doc.url) && doc.kind == .text {
                        readerToggle(for: doc)
                    }
                    if doc.kind == .text {
                        minimapToggle
                    }
                }
                // In glass mode the tab bar floats over the editor at
                // y=0..36 — push the corner buttons below it so they're
                // visible *and* clickable. Solid mode keeps the original
                // 12pt offset since the tab bar is stacked, not floating.
                .padding(.top, 12 + (windowGlass ? tabBarHeight : 0))
                .padding(.trailing, 14 + 11)
            }
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func primaryContent(for doc: Document) -> some View {
        switch doc.kind {
        case .pdf:
            PDFViewerView(url: doc.url)
                .id("pdf-\(doc.id)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, windowGlass ? tabBarHeight : 0)
        case .image:
            ImageViewerView(url: doc.url)
                .id("image-\(doc.id)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, windowGlass ? tabBarHeight : 0)
        case .video:
            VideoPlayerView(url: doc.url)
                .id("video-\(doc.id)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, windowGlass ? tabBarHeight : 0)
        case .binary:
            HexViewerView(url: doc.url)
                .id("hex-\(doc.id)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, windowGlass ? tabBarHeight : 0)
        case .text:
            textPrimaryContent(for: doc)
        }
    }

    @ViewBuilder
    private func textPrimaryContent(for doc: Document) -> some View {
        if DocumentKindDetector.supportsReaderView(doc.url) && (readerEnabled[doc.id] ?? false) {
            readerView(for: doc)
                .id("reader-\(doc.id)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Reader doesn't have a scroll content inset, so simply
                // pad it down so its first line isn't hidden by the
                // floating tab bar in glass mode.
                .padding(.top, windowGlass ? tabBarHeight : 0)
        } else {
            // Always hide the editor's internal scroller — the external
            // `EditorScrollbar` lives at the far-right of the window.
            EditorView(
                document: doc,
                workspace: workspace,
                minimapBridge: minimapBridge,
                hidesScroller: true,
                topContentInset: windowGlass ? tabBarHeight : 0
            )
            .id(doc.id)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // macOS Tahoe paints a "hard" scroll edge effect at the top
            // of any scroll view by default — a visible line at the
            // contentInset boundary. In glass mode the tab bar already
            // provides the visual divider, so suppress it.
            .scrollEdgeEffectStyle(windowGlass ? .soft : nil, for: .top)
        }
    }

    @ViewBuilder
    private func readerView(for doc: Document) -> some View {
        if DocumentKindDetector.isAsciiDoc(doc.url) {
            AsciiDocReaderView(text: doc.text, sourceURL: doc.url)
        } else {
            MarkdownReaderView(text: doc.text, sourceURL: doc.url)
        }
    }

    private func readerToggle(for doc: Document) -> some View {
        let active = readerEnabled[doc.id] ?? false
        return cornerToggleButton(
            symbol: active ? "pencil" : "book",
            help: active ? "Edit markdown" : "Reader view",
            action: { readerEnabled[doc.id] = !active }
        )
    }

    private var minimapToggle: some View {
        cornerToggleButton(
            symbol: showMinimap ? "sidebar.right" : "rectangle.righthalf.filled",
            help: showMinimap ? "Hide minimap" : "Show minimap",
            action: { showMinimap.toggle() }
        )
    }

    private func cornerToggleButton(
        symbol: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .modifier(CornerButtonSurface(useGlass: windowGlass))
        }
        .buttonStyle(.plain)
        .help(help)
    }

}

/// NSItemProvider hands fileURL items back as Data, NSURL, or URL
/// depending on the source. Normalize to URL.
private func resolveDroppedFileURL(from item: Any?) -> URL? {
    if let url = item as? URL { return url }
    if let url = item as? NSURL { return url as URL }
    if let data = item as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)
    }
    return nil
}

private struct WatermarkBackground: View {
    var body: some View {
        EnsoLogo(color: .primary.opacity(0.06))
            .frame(width: 320, height: 320)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

private struct EmptyState: View {
    @EnvironmentObject var workspace: Workspace

    var body: some View {
        VStack(spacing: 18) {
            Text("Minimalist")
                .font(.system(size: 36, weight: .light, design: .serif))
                .foregroundStyle(.secondary)
            Button("Open Folder") { workspace.openFolder() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TabBar: View {
    @EnvironmentObject var workspace: Workspace
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @Environment(\.editorSurfaceIsDark) private var editorIsDark

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                tabRow
            }
            .frame(height: 36)
            .scrollContentBackground(.hidden)
            // The hairline separates the tab strip from the editor body
            // in solid mode. In glass mode the strip floats over scrolling
            // content, so the line would draw straight through code.
            if !windowGlass {
                Rectangle()
                    .fill(EditorBackgroundOption.primary(onDarkSurface: editorIsDark).opacity(0.08))
                    .frame(height: 0.5)
            }
        }
    }

    /// In glass mode, multiple glass-backed tabs sit close together. The
    /// `GlassEffectContainer` gives them a shared sampling region so
    /// adjacent panes refract coherently instead of fighting each other.
    @ViewBuilder
    private var tabRow: some View {
        if windowGlass {
            GlassEffectContainer(spacing: 4) {
                tabRowContents
            }
        } else {
            tabRowContents
        }
    }

    private var tabRowContents: some View {
        HStack(spacing: 4) {
            ForEach(workspace.openDocuments) { doc in
                TabButton(document: doc)
            }
            // Trailing empty space — the whole top is window-draggable
            // via `isMovableByWindowBackground`, so this gives the user
            // grab area beyond the last tab.
            Color.clear.frame(width: 80)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

private struct TabButton: View {
    @EnvironmentObject var workspace: Workspace
    @ObservedObject var document: Document
    @State private var hovering = false
    @State private var historyContext: HistoryContext?

    @AppStorage(PreferenceKeys.accentPresetID)
    private var accentID: String = AccentPresets.defaultID
    @AppStorage(PreferenceKeys.accentTintTabs)
    private var tintTabs: Bool = false
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @Environment(\.editorSurfaceIsDark) private var editorIsDark

    private var tabTint: Double { tintTabs ? 1.0 : 0.0 }

    var isActive: Bool { workspace.activeDocumentID == document.id }


    private static let cornerRadius: CGFloat = 7

    private var accent: Color {
        AccentPresets.preset(forID: accentID).color
    }

    /// Solid-mode hover background. In Glass mode the surface modifier
    /// handles every state itself (idle inactive tabs get a faded glass
    /// treatment so they still read as tabs), so this view is only
    /// applied when glass is off.
    @ViewBuilder
    private var solidHoverBackground: some View {
        if !isActive && hovering {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(EditorBackgroundOption.primary(onDarkSurface: editorIsDark).opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(accent.opacity(0.07 * tabTint))
                )
        }
    }

    var body: some View {
        // ZStack — close button is a true sibling rendered after the
        // tab body, so it's always above the glass material in glass
        // mode. (`.overlay()` on a Button with `.glassEffect` could land
        // *under* the glass layer.) Hover is tracked once, on the ZStack,
        // so there's no nested-hover flicker on the X.
        ZStack(alignment: .trailing) {
            Button(action: { workspace.activate(document) }) {
                HStack(spacing: 6) {
                    Text(document.displayName)
                        .font(.system(size: 12))
                        .italic(document.isUntitled || document.isPreview)
                        .foregroundStyle(
                            isActive
                                ? EditorBackgroundOption.primary(onDarkSurface: editorIsDark)
                                : EditorBackgroundOption.secondary(onDarkSurface: editorIsDark)
                        )

                    if document.isDirty {
                        Circle()
                            .fill(EditorBackgroundOption.secondary(onDarkSurface: editorIsDark))
                            .frame(width: 5, height: 5)
                    }

                    // Reserve close-button space so the tab doesn't change
                    // width on hover.
                    Color.clear.frame(width: 12, height: 12)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(solidHoverBackground)
                .modifier(TabSurface(
                    isActive: isActive,
                    hovering: hovering,
                    useGlass: windowGlass,
                    accent: accent,
                    tabTint: tabTint
                ))
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { workspace.pin(document) }
            )

            TabCloseButton(
                action: { workspace.requestClose(document) },
                armed: hovering
            )
            .padding(.trailing, 8)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .animation(.easeOut(duration: 0.12), value: isActive)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .contextMenu {
            if !document.isUntitled {
                Button("Show Revision History…") {
                    historyContext = .revisions(document.url)
                }
                Button("Show Commit History…") {
                    historyContext = .commits(document.url)
                }
                Divider()
                Button("Reveal in Finder") {
                    FileOperations.revealInFinder(document.url)
                }
                Divider()
            }
            Button("Close Tab") { workspace.requestClose(document) }
            if document.isPreview {
                Button("Pin Tab") { workspace.pin(document) }
            }
        }
        .sheet(item: $historyContext) { ctx in
            switch ctx {
            case .revisions(let url):
                RevisionHistoryView(url: url, workspace: workspace)
            case .commits(let url):
                CommitHistoryView(url: url, workspace: workspace)
            }
        }
    }
}

/// Tab surface treatment. With Glass on, *every* tab is rendered with
/// Liquid Glass — active uses `.regular` (full refraction) plus the
/// accent wash, while inactive uses `.clear` (subtle, faded refraction)
/// so they're clearly secondary but still read as tabs. With Glass off
/// only the active tab gets a material background; inactive tabs are
/// painted by `solidHoverBackground` instead.
private struct TabSurface: ViewModifier {
    let isActive: Bool
    let hovering: Bool
    let useGlass: Bool
    let accent: Color
    let tabTint: Double

    /// Drives the solid-mode opacity scaling — based on the editor
    /// surface tone (which factors in the user's background override),
    /// not the app appearance.
    @Environment(\.editorSurfaceIsDark) private var editorIsDark

    private static let cornerRadius: CGFloat = 7

    /// Solid mode looks balanced on a dark surface but the same
    /// opacities read heavier on a light/sepia surface — that surface
    /// picks up every percentage point of the colored overlay. Dial
    /// things back on light surfaces so the pill stays airy.
    private var solidAccentOpacity: Double {
        editorIsDark ? 0.16 : 0.09
    }
    private var solidBorderOpacity: Double {
        editorIsDark ? 0.12 : 0.06
    }
    private var solidShadowOpacity: Double {
        editorIsDark ? 0.18 : 0.08
    }

    func body(content: Content) -> some View {
        if useGlass {
            glassBody(content)
        } else {
            solidBody(content)
        }
    }

    @ViewBuilder
    private func glassBody(_ content: Content) -> some View {
        if isActive {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
                .overlay(
                    // Glass refraction tends to wash colors a bit cooler,
                    // so the active tab's accent overlay gets a richer
                    // alpha than the solid-mode equivalent — same toggle,
                    // stronger paint.
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(accent.opacity(0.48 * tabTint))
                )
                // Refraction supplies most of the depth; a whisper of
                // shadow anchors the tab to the strip.
                .shadow(color: .black.opacity(0.06), radius: 1.5, x: 0, y: 0.5)
        } else {
            content
                .glassEffect(.clear, in: .rect(cornerRadius: Self.cornerRadius))
                .overlay(
                    // Slight extra accent on hover so the tab nudges
                    // toward "selectable" without competing with active.
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(accent.opacity((hovering ? 0.07 : 0.04) * tabTint))
                )
                .opacity(hovering ? 0.85 : 0.65)
        }
    }

    @ViewBuilder
    private func solidBody(_ content: Content) -> some View {
        if isActive {
            content
                .background(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .fill(accent.opacity(solidAccentOpacity * tabTint))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                                .stroke(Color.primary.opacity(solidBorderOpacity), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(solidShadowOpacity), radius: 3, x: 0, y: 1)
        } else {
            content
        }
    }
}

/// Tab "close" affordance — adopts a subtle red circular ring on hover
/// so the user gets a clear visual cue that the click closes the tab,
/// not just an ambiguous X. Click anywhere inside the 18×18 hit region.
/// Reader / minimap corner-button background. Glass mode uses Liquid
/// Glass refraction so the button blends with the rest of the glass UI;
/// solid mode keeps the previous `.ultraThinMaterial` chip.
private struct CornerButtonSurface: ViewModifier {
    let useGlass: Bool

    func body(content: Content) -> some View {
        if useGlass {
            content
                .glassEffect(.regular, in: .circle)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 0.5)
        } else {
            content
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle().stroke(.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        }
    }
}

private struct TabCloseButton: View {
    let action: () -> Void
    /// Driven by the parent tab's hover state. Avoids a nested `onHover`
    /// inside the close button, which used to flip in and out as the
    /// cursor crossed the small circular hit region.
    let armed: Bool

    @Environment(\.editorSurfaceIsDark) private var editorIsDark

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(
                    armed
                        ? Color.white
                        : EditorBackgroundOption.primary(onDarkSurface: editorIsDark).opacity(0.65)
                )
                .frame(width: 14, height: 14)
                .background(
                    Circle()
                        .fill(
                            armed
                                ? Color.red.opacity(0.92)
                                : EditorBackgroundOption.primary(onDarkSurface: editorIsDark).opacity(0.10)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.red.opacity(armed ? 1.0 : 0), lineWidth: 0.5)
                        )
                )
                // Rectangular hit shape so cursor jitter near the
                // corners of the 14×14 frame doesn't bounce hover state.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close Tab")
        .animation(.easeOut(duration: 0.10), value: armed)
    }
}

private struct CloseButton: View {
    let visible: Bool
    let action: () -> Void

    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 12, height: 12)
            .opacity(visible ? 0.7 : 0)
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }
}
