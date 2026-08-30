import Adwaita
import Foundation
import MinimalistCore

extension MainView {

    @ViewBuilder var contentPane: Body {
        VStack {
            if !zenMode, !tabs.isEmpty {
                tabStrip
            }
            editorArea
        }
        // One `.overlay` only: calling it twice replaces the overlay
        // content rather than nesting, and every child must carry its own
        // alignment — an unaligned one fills the pane and swallows the
        // clicks and scroll events meant for the tabs and the editor.
        .overlay {
            overlayControls
        }
    }

    // MARK: - Tabs

    @ViewBuilder var tabStrip: Body {
        ScrollView {
            HStack(spacing: 2) {
                ForEach(tabs, id: \.id) { tab in
                    tabView(tab)
                }
            }
            .halign(.start)
        }
        .vscrollbarPolicy(.never)
        .padding(6)
        .style("tab-bar")
    }

    @ViewBuilder func tabView(_ tab: EditorTab) -> Body {
        HStack(spacing: 2) {
            Button(tab.title) { activateTab(tab.id) }
                .child {
                    Text(tabTitle(tab))
                        .ellipsize()
                        .style("tab-preview", active: tab.isPreview || tab.isUntitled)
                }
                .flat()
                .style("tab-item")
                .inspect { storage, _ in installPinTab(storage, tabID: tab.id) }
            Button(icon: .custom(name: "window-close-symbolic")) { requestCloseTab(tab.id) }
                .flat()
                .style("tab-close")
        }
        .style("tab-slot")
        .style("tab-active", active: tab.id == activeTabID)
    }

    func tabTitle(_ tab: EditorTab) -> String {
        _ = chromeTick
        return (isDirty(tab.id) ? "• " : "") + tab.title
    }

    // MARK: - Editor / viewers

    @ViewBuilder var editorArea: Body {
        if let tab = activeTab {
            switch tab.kind {
            case .text:
                if tab.showReader {
                    readerView(for: tab)
                } else {
                    editor(for: tab)
                }
            case .image:
                ScrollView {
                    Picture(url: URL(fileURLWithPath: tab.id))
                        .canShrink(false)
                        .contentFit(.scaleDown)
                }
                .vexpand()
            case .video, .audio:
                MediaPlayer(path: tab.id)
                    .vexpand()
            case .binary:
                hexView(for: tab)
            case .pdf:
                StatusPage(
                    tab.title,
                    icon: .custom(name: "x-office-document-symbolic"),
                    description: "PDFs open in your system viewer."
                )
                .child {
                    Button("Open in Document Viewer") {
                        GTKBridge.openURI(URL(fileURLWithPath: tab.id).absoluteString)
                    }
                    .pill()
                    .suggested()
                    .halign(.center)
                }
            }
        } else {
            StatusPage(
                "No Open Files",
                icon: .custom(name: "document-open-symbolic"),
                description: "Open a folder or file to get started"
            )
        }
    }

    @ViewBuilder func editor(for tab: EditorTab) -> Body {
        let settings = onMain { DocumentStore.shared.settings }
        SourceEditor(
            text: .init { text(of: tab.id) } set: { newValue in
                // Only nudge the chrome when the dirty marker actually
                // flips — re-rendering on every keystroke would re-read
                // the whole buffer each time.
                let dirtyChanged = onMain { () -> Bool in
                    let before = DocumentStore.shared.isDirty(tab.id)
                    DocumentStore.shared.updateText(path: tab.id, text: newValue)
                    return before != DocumentStore.shared.isDirty(tab.id)
                }
                // Editing a preview tab pins it, as on macOS.
                if tab.isPreview { pin(tab.id) }
                if dirtyChanged { chromeTick &+= 1 }
            },
            documentID: tab.id,
            liveIDs: Set(tabs.map(\.id))
        )
        .language(LanguageMap.editorLanguage(for: tab.languageID))
        .schemes(light: settings.syntaxThemeLight, dark: settings.syntaxThemeDark)
        .lineNumbers(settings.showLineNumbers)
        .highlightCurrentLine(settings.highlightCurrentLine)
        .minimap(settings.showMinimap && !zenMode)
        .wordWrap(settings.wordWrap)
        .indentation(width: indentation(of: tab).width, spaces: indentation(of: tab).kind == .spaces)
        .completion(
            settings.completionEnabled,
            keywords: settings.completionKeywords
                ? Array(LanguageKeywords.list(for: tab.languageID))
                : []
        )
        .scroll(to: scrollLine, token: scrollToken)
        .background(settings.editorBackground)
        .vexpand()
    }

    @ViewBuilder func readerView(for tab: EditorTab) -> Body {
        let source = text(of: tab.id)
        let markup = MarkdownRenderer.pangoMarkup(from: source)
        let valid = GTKBridge.isValidMarkup(markup)
        ScrollView {
            Text(valid ? markup : source)
                .useMarkup(valid)
                .wrap()
                .selectable()
                .xalign(0)
                .halign(.start)
                .valign(.start)
                .padding(24)
                .style("reader")
        }
        .vexpand()
    }

    @ViewBuilder func hexView(for tab: EditorTab) -> Body {
        // A GtkLabel lays out its whole string eagerly, so the viewer
        // shows a slice rather than HexDump's full 4 MB ceiling.
        let dump = HexDump.dump(url: URL(fileURLWithPath: tab.id), limit: 64 * 1_024)
        ScrollView {
            VStack(spacing: 8) {
                Text(dump.text)
                    .selectable()
                    .xalign(0)
                    .monospace()
                    .halign(.start)
                    .valign(.start)
                if dump.truncated {
                    Text("Showing the first 64 KB of \(HexDump.byteCount(dump.totalSize)).")
                        .caption()
                        .dimLabel()
                        .halign(.start)
                }
            }
            .padding(16)
        }
        .vexpand()
    }

    // MARK: - Floating controls

    /// Every overlay child is an always-present container carrying its
    /// own alignment. A bare `if` at this level becomes a `GtkStack` that
    /// fills the pane — invisible, but it swallows the clicks and scroll
    /// events meant for the tabs and the editor underneath.
    @ViewBuilder var overlayControls: Body {
        floatingToggles
        VStack {
            if zenMode {
                Button(icon: .custom(name: "view-restore-symbolic")) { zenMode = false }
                    .circular()
                    .style("float-btn")
                    .tooltip("Leave zen mode")
            }
        }
        .halign(.end)
        .valign(.start)
        .padding(14, [.top, .trailing])
        VStack {
            if let tab = activeTab {
                statusPill(for: tab)
            }
        }
        .halign(.end)
        .valign(.end)
        .padding(14, [.bottom, .trailing])
        VStack {
            if searchVisible {
                searchPalette
            }
        }
        .halign(.center)
        .valign(.start)
        .padding(60, [.top])
    }

    /// The macOS app floats its reader / minimap toggles over the
    /// editor's top-right corner; so does this one.
    @ViewBuilder var floatingToggles: Body {
        HStack(spacing: 8) {
            if activeTab?.supportsReader == true {
                Button(icon: .custom(name: "view-paged-symbolic")) { toggleReader() }
                    .circular()
                    .style("float-btn")
                    .style("float-btn-active", active: activeTab?.showReader == true)
                    .tooltip("Reader view")
            }
            if activeTab?.kind == .text, !zenMode {
                Button(icon: .custom(name: "view-dual-symbolic")) { toggleMinimap() }
                    .circular()
                    .style("float-btn")
                    .style(
                        "float-btn-active",
                        active: onMain { DocumentStore.shared.settings.showMinimap }
                    )
                    .tooltip("Minimap")
            }
        }
        .halign(.end)
        .valign(.start)
        .padding(14, [.top, .trailing])
    }

    @ViewBuilder func statusPill(for tab: EditorTab) -> Body {
        Button("") { statusPopoverVisible = true }
            .child {
                Text(statusLine(for: tab))
                    .caption()
                    .monospace()
            }
            .flat()
            .style("status-pill")
            .popover(visible: $statusPopoverVisible) {
                if tab.kind == .text {
                    documentOptions(for: tab)
                } else {
                    Text(statusLine(for: tab))
                        .padding(12)
                }
            }
    }

    /// Language · indentation · line endings, like the macOS status pill.
    func statusLine(for tab: EditorTab) -> String {
        _ = chromeTick
        switch tab.kind {
        case .text:
            let language = tab.languageID == "plaintext"
                ? "PLAIN TEXT"
                : tab.languageID.uppercased()
            let indent = indentation(of: tab)
            let indentLabel = indent.kind == .tabs ? "Tabs: \(indent.width)" : "Spaces: \(indent.width)"
            return "\(language)  |  \(indentLabel)  |  \(lineEnding(of: tab).rawValue.uppercased())"
        case .image, .video, .audio, .pdf, .binary:
            return HexDump.summary(url: URL(fileURLWithPath: tab.id))
        }
    }

    /// The popover behind the status pill: language, indentation and line
    /// endings for the active document.
    @ViewBuilder func documentOptions(for tab: EditorTab) -> Body {
        VStack(spacing: 8) {
            Text("Document")
                .heading()
                .halign(.start)
            Form {
                ComboRow(
                    "Language",
                    selection: .init { tab.languageID } set: { setLanguage($0, for: tab.id) },
                    values: languageChoices
                )
                ComboRow(
                    "Indentation",
                    selection: .init { indentation(of: tab).kind.rawValue } set: { raw in
                        setIndentation(
                            kind: Indentation.Kind(rawValue: raw) ?? .spaces,
                            width: indentation(of: tab).width,
                            for: tab.id
                        )
                    },
                    values: [Choice(id: Indentation.Kind.spaces.rawValue), Choice(id: Indentation.Kind.tabs.rawValue)]
                )
                SpinRow(
                    "Width",
                    value: .init { indentation(of: tab).width } set: { width in
                        setIndentation(kind: indentation(of: tab).kind, width: width, for: tab.id)
                    },
                    min: 1,
                    max: 8
                )
                ComboRow(
                    "Line endings",
                    selection: .init { lineEnding(of: tab).rawValue } set: { raw in
                        setLineEnding(LineEnding(rawValue: raw) ?? .lf, for: tab.id)
                    },
                    values: LineEnding.allCases.map { Choice(id: $0.rawValue) }
                )
            }
            Button("Use as default") { adoptDocumentDefaults(for: tab) }
                .flat()
        }
        .padding(12)
        .frame(maxWidth: 320)
    }

    var languageChoices: [Choice] {
        var ids = ["plaintext"]
        ids.append(contentsOf: LanguageMap.availableIDs)
        return ids.map { Choice(id: $0) }
    }
}
