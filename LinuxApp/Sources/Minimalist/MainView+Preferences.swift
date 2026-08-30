import Adwaita
import Foundation
import MinimalistCore

extension MainView {

    /// The preferences dialog's content.
    ///
    /// Built on `PreferencesPage` inside a plain `Dialog` rather than
    /// Adwaita's `preferencesDialog` modifier: that one over-unrefs its
    /// pages when it closes and never clears its storage slot, so the
    /// dialog can't be reopened (and the freed objects go on to spray
    /// GObject criticals). Same reason for the shortcuts dialog below.
    @ViewBuilder var preferencesContent: Body {
        PreferencesPage()
            .child {
                FormSection("Font") {
                    EntryRow("Font family", text: settingBinding(\.editorFontFamily))
                    SpinRow("Size", value: settingBinding(\.editorFontSize), min: 7, max: 32)
                }
                FormSection("Editing") {
                    SwitchRow("Line numbers", isOn: settingBinding(\.showLineNumbers))
                    SwitchRow("Minimap", isOn: settingBinding(\.showMinimap))
                    SwitchRow("Word wrap", isOn: settingBinding(\.wordWrap))
                    SwitchRow("Highlight current line", isOn: settingBinding(\.highlightCurrentLine))
                }
                FormSection("Indentation") {
                    ComboRow(
                        "Indent using",
                        selection: settingBinding(\.indentKind),
                        values: [
                            Choice(id: Indentation.Kind.spaces.rawValue),
                            Choice(id: Indentation.Kind.tabs.rawValue),
                        ]
                    )
                    SpinRow("Width", value: settingBinding(\.indentWidth), min: 1, max: 8)
                    ComboRow(
                        "Line endings",
                        selection: settingBinding(\.defaultLineEnding),
                        values: LineEnding.allCases.map { Choice(id: $0.rawValue) }
                    )
                }
                .description("Defaults for newly opened files")
                FormSection("Completion") {
                    SwitchRow("Suggest words from the document", isOn: settingBinding(\.completionEnabled))
                    SwitchRow("Include language keywords", isOn: settingBinding(\.completionKeywords))
                }
                FormSection("Syntax theme") {
                    ComboRow(
                        "Light",
                        selection: settingBinding(\.syntaxThemeLight),
                        values: LanguageMap.styleSchemeIDs.map { Choice(id: $0) }
                    )
                    ComboRow(
                        "Dark",
                        selection: settingBinding(\.syntaxThemeDark),
                        values: LanguageMap.styleSchemeIDs.map { Choice(id: $0) }
                    )
                }
                FormSection("Editor background") {
                    ComboRow(
                        "Background",
                        selection: .init {
                            onMain { DocumentStore.shared.settings.editorBackground } ?? "theme"
                        } set: { value in
                            onMain {
                                DocumentStore.shared.settings.editorBackground = value == "theme" ? nil : value
                            }
                            chromeTick &+= 1
                        },
                        values: ["theme", "white", "sepia", "dark"].map { Choice(id: $0) }
                    )
                }
            }
            .topToolbar {
                HeaderBar.empty()
            }
    }

    /// The keyboard-shortcut reference, as a plain dialog for the same
    /// reason as the preferences one.
    @ViewBuilder var shortcutsContent: Body {
        PreferencesPage()
            .child {
                FormSection("Files") {
                    shortcutRow("New file", "Ctrl+N")
                    shortcutRow("Open file", "Ctrl+O")
                    shortcutRow("Open folder", "Ctrl+Shift+O")
                    shortcutRow("Save", "Ctrl+S")
                    shortcutRow("Save as", "Ctrl+Shift+S")
                }
                FormSection("Tabs") {
                    shortcutRow("Close tab", "Ctrl+W")
                    shortcutRow("Move tab left", "Ctrl+Alt+Left")
                    shortcutRow("Move tab right", "Ctrl+Alt+Right")
                    shortcutRow("Close window", "Ctrl+Shift+W")
                }
                FormSection("View") {
                    shortcutRow("Toggle sidebar", "Ctrl+B")
                    shortcutRow("Word wrap", "Ctrl+Alt+W")
                    shortcutRow("Zen mode", "Ctrl+Alt+Z")
                    shortcutRow("Search palette", "Shift Shift  ·  Ctrl+P")
                    shortcutRow("Preferences", "Ctrl+,")
                }
            }
            .topToolbar {
                HeaderBar.empty()
            }
    }

    @ViewBuilder private func shortcutRow(_ title: String, _ accelerator: String) -> Body {
        ActionRow()
            .title(title)
            .suffix {
                Text(accelerator)
                    .monospace()
                    .dimLabel()
                    .valign(.center)
            }
    }

    /// A binding onto one field of the persisted settings. Writing it
    /// saves the JSON and nudges the chrome to re-render.
    func settingBinding<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
        .init {
            onMain { DocumentStore.shared.settings[keyPath: keyPath] }
        } set: { newValue in
            onMain { DocumentStore.shared.settings[keyPath: keyPath] = newValue }
            chromeTick &+= 1
        }
    }
}
