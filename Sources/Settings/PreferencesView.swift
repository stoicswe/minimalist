import SwiftUI
import AppKit

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            AccentTab()
                .tabItem { Label("Accent", systemImage: "paintpalette") }
            FontsTab()
                .tabItem { Label("Fonts", systemImage: "textformat") }
        }
        .frame(width: 540, height: 460)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @AppStorage(PreferenceKeys.openLocationBehavior)
    private var openBehavior: String = OpenLocationBehavior.default
    @AppStorage(PreferenceKeys.enableAutocomplete)
    private var enableAutocomplete: Bool = true
    @AppStorage(PreferenceKeys.enableLanguageKeywords)
    private var enableLanguageKeywords: Bool = true
    @AppStorage(PreferenceKeys.iCloudSyncEnabled)
    private var iCloudSyncEnabled: Bool = false

    var body: some View {
        Form {
            Section {
                Picker("Open File / Folder", selection: $openBehavior) {
                    Text("Ask each time").tag(OpenLocationBehavior.ask)
                    Text("Same window").tag(OpenLocationBehavior.same)
                    Text("New window").tag(OpenLocationBehavior.new)
                }
            } header: {
                Text("Default open behavior")
            } footer: {
                Text("Controls where ⌘O / ⌘⇧O places the file or folder you pick. ⌘⇧N always opens an empty new window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Inline suggestions", isOn: $enableAutocomplete)
                Toggle("Suggest language keywords", isOn: $enableLanguageKeywords)
                    .disabled(!enableAutocomplete)
            } header: {
                Text("Editor")
            } footer: {
                Text("Inline suggestions show ghost-text completions as you type, drawn from identifiers in the file. With language keywords on, the file's language (Swift, Haskell, Python, etc.) also contributes its keywords to the suggestion pool. Press Tab to accept, Esc or any keystroke to dismiss.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Sync settings via iCloud", isOn: $iCloudSyncEnabled)
            } header: {
                Text("iCloud")
            } footer: {
                Text("Mirrors appearance, accent, inline-suggestion, and font settings across your Macs signed into the same iCloud account. Custom fonts that don't ship with macOS stay local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: iCloudSyncEnabled) { _, _ in
            PreferenceSync.shared.updateInstallationFromPreference()
        }
    }
}

// MARK: - Accent

private struct AccentTab: View {
    @AppStorage(PreferenceKeys.accentPresetID)
    private var accentID: String = AccentPresets.defaultID
    @AppStorage(PreferenceKeys.accentTintFolders)
    private var tintFolders: Bool = false
    @AppStorage(PreferenceKeys.accentTintTabs)
    private var tintTabs: Bool = false
    @AppStorage(PreferenceKeys.accentTintCurrentLine)
    private var tintCurrentLine: Bool = false

    var body: some View {
        Form {
            Section {
                Picker("Color", selection: $accentID) {
                    ForEach(AccentPresets.all) { preset in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                                )
                            Text(preset.displayName)
                        }
                        .tag(preset.id)
                    }
                }
            } header: {
                Text("Accent color")
            } footer: {
                Text("Tints the editor cursor, the right-click outline in the file tree, and the highlighted item in context menus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Folder icons", isOn: $tintFolders)
                Toggle("Tab background", isOn: $tintTabs)
                Toggle("Current-line highlight", isOn: $tintCurrentLine)
            } header: {
                Text("Apply tint")
            } footer: {
                Text("Each toggle adds the accent to that surface. Off keeps it neutral.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: accentID) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: tintFolders) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: tintTabs) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: tintCurrentLine) { _, _ in notifyEditorPrefsChanged() }
    }

    private func notifyEditorPrefsChanged() {
        NotificationCenter.default.post(name: .editorPreferencesChanged, object: nil)
    }
}

// MARK: - Appearance

private struct AppearanceTab: View {
    @AppStorage(PreferenceKeys.colorScheme) private var colorScheme: String = "system"
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @AppStorage(PreferenceKeys.syntaxThemeLight) private var syntaxThemeLight: String = SyntaxThemes.defaultLight
    @AppStorage(PreferenceKeys.syntaxThemeDark) private var syntaxThemeDark: String = SyntaxThemes.defaultDark
    @AppStorage(PreferenceKeys.editorBackgroundOverride) private var editorBgOverride: Bool = false
    @AppStorage(PreferenceKeys.editorBackgroundLight) private var editorBgLight: String = "white"
    @AppStorage(PreferenceKeys.editorBackgroundDark) private var editorBgDark: String = "dark"
    @AppStorage(PreferenceKeys.accentTintSidebar) private var accentTintSidebar: Bool = false
    @AppStorage(PreferenceKeys.editorBackgroundPattern) private var bgPatternRaw: String = "none"
    @AppStorage(PreferenceKeys.editorBackgroundPatternAnimated) private var bgPatternAnimated: Bool = false
    @AppStorage(PreferenceKeys.editorBackgroundPatternSpeed) private var bgPatternSpeed: Double = 1.0

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $colorScheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section {
                Picker("Style", selection: $windowGlass) {
                    Text("Solid").tag(false)
                    Text("Glass").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Window")
            } footer: {
                Text("Glass makes the entire window translucent so the desktop shows through. Solid keeps it opaque.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Tint sidebar with accent", isOn: $accentTintSidebar)
            } header: {
                Text("Sidebar")
            } footer: {
                Text("Washes the sidebar's background with a soft tint of your accent color — pastel in light mode, richer in dark mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Use a custom editor background", isOn: $editorBgOverride)
                Picker("Light mode", selection: $editorBgLight) {
                    ForEach(EditorBackgroundOption.allCases) { opt in
                        Text(opt.displayName).tag(opt.rawValue)
                    }
                }
                .disabled(!editorBgOverride)
                Picker("Dark mode", selection: $editorBgDark) {
                    ForEach(EditorBackgroundOption.allCases) { opt in
                        Text(opt.displayName).tag(opt.rawValue)
                    }
                }
                .disabled(!editorBgOverride)
            } header: {
                Text("Editor background")
            } footer: {
                Text("Overrides the editor pane's background with a fixed color. Each appearance can pick its own — sepia for daytime reading, dark for night.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Pattern", selection: $bgPatternRaw) {
                    ForEach(EditorBackgroundPattern.allCases) { p in
                        Text(p.displayName).tag(p.rawValue)
                    }
                }
                Toggle("Animate", isOn: $bgPatternAnimated)
                    .disabled(bgPatternRaw == "none")
                HStack {
                    Text("Speed")
                        .frame(width: 80, alignment: .leading)
                    Slider(value: $bgPatternSpeed, in: 0.1...2.0)
                    Text("\(Int(bgPatternSpeed * 100))%")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 40, alignment: .trailing)
                        .foregroundStyle(.secondary)
                }
                .disabled(bgPatternRaw == "none" || !bgPatternAnimated)
            } header: {
                Text("Editor pattern")
            } footer: {
                Text("A whisper-quiet zen-themed pattern over the editor background. Optional animation for sand drifts, ripples, drifting mist, or twinkling stars.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Syntax colors") {
                Picker("Light mode", selection: $syntaxThemeLight) {
                    ForEach(SyntaxThemes.light, id: \.self) { theme in
                        Text(prettyName(theme)).tag(theme)
                    }
                }
                Picker("Dark mode", selection: $syntaxThemeDark) {
                    ForEach(SyntaxThemes.dark, id: \.self) { theme in
                        Text(prettyName(theme)).tag(theme)
                    }
                }
            }
        }
        .formStyle(.grouped)
        // Push a redraw signal so AppKit-rendered surfaces (the line-number
        // ruler, syntax-highlighted text) refresh their appearance-dependent
        // colors and the active theme is re-applied.
        .onChange(of: colorScheme) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: windowGlass) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: syntaxThemeLight) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: syntaxThemeDark) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: editorBgOverride) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: editorBgLight) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: editorBgDark) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: accentTintSidebar) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: bgPatternRaw) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: bgPatternAnimated) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: bgPatternSpeed) { _, _ in notifyEditorPrefsChanged() }
    }

    private func prettyName(_ raw: String) -> String {
        raw.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func notifyEditorPrefsChanged() {
        NotificationCenter.default.post(name: .editorPreferencesChanged, object: nil)
    }
}

// MARK: - Fonts

private struct FontsTab: View {
    @AppStorage(PreferenceKeys.showLineNumbers) private var showLineNumbers: Bool = true
    @AppStorage(PreferenceKeys.wordWrap) private var wordWrap: Bool = true
    @AppStorage(PreferenceKeys.uiFontName) private var uiFontName: String = ""
    @AppStorage(PreferenceKeys.uiFontSize) private var uiFontSize: Double = 13
    @AppStorage(PreferenceKeys.editorFontName) private var editorFontName: String = ""
    @AppStorage(PreferenceKeys.editorFontSize) private var editorFontSize: Double = 13

    var body: some View {
        Form {
            Section("Editor") {
                Toggle("Show line numbers", isOn: $showLineNumbers)
                Toggle("Word wrap", isOn: $wordWrap)
                FontPickerRow(
                    label: "Editor font",
                    fontName: $editorFontName,
                    fontSize: $editorFontSize,
                    monospacedOnly: true
                )
            }
            Section("Interface") {
                FontPickerRow(
                    label: "UI font",
                    fontName: $uiFontName,
                    fontSize: $uiFontSize,
                    monospacedOnly: false
                )
            }
        }
        .formStyle(.grouped)
        .onChange(of: showLineNumbers) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: wordWrap) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: uiFontName) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: uiFontSize) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: editorFontName) { _, _ in notifyEditorPrefsChanged() }
        .onChange(of: editorFontSize) { _, _ in notifyEditorPrefsChanged() }
    }

    private func notifyEditorPrefsChanged() {
        NotificationCenter.default.post(name: .editorPreferencesChanged, object: nil)
    }
}

private struct FontPickerRow: View {
    let label: String
    @Binding var fontName: String
    @Binding var fontSize: Double
    let monospacedOnly: Bool

    @State private var families: [String] = []

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Picker("", selection: $fontName) {
                Text(monospacedOnly ? "System Monospaced" : "System").tag("")
                Divider()
                ForEach(families, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .labelsHidden()
            .frame(width: 240)

            HStack(spacing: 4) {
                Text("\(Int(fontSize))pt")
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 32, alignment: .trailing)
                Stepper("", value: $fontSize, in: 9...32, step: 1)
                    .labelsHidden()
            }
        }
        .task {
            families = loadFamilies()
        }
    }

    private func loadFamilies() -> [String] {
        let all = NSFontManager.shared.availableFontFamilies
        if !monospacedOnly { return all }
        return all.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch
        }
    }
}
