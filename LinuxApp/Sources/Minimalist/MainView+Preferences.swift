import Adwaita
import Foundation
import MinimalistCore

extension MainView {

    /// Editor page: font, indentation, completion — the parts of the
    /// macOS Preferences window that apply on Linux.
    func editorPreferences(_ page: PreferencesDialog.PreferencesPage) -> PreferencesDialog.PreferencesPage {
        page
            .group("Font") {
                EntryRow("Font family", text: settingBinding(\.editorFontFamily))
                SpinRow("Size", value: settingBinding(\.editorFontSize), min: 7, max: 32)
            }
            .group("Editing") {
                SwitchRow("Line numbers", isOn: settingBinding(\.showLineNumbers))
                SwitchRow("Minimap", isOn: settingBinding(\.showMinimap))
                SwitchRow("Word wrap", isOn: settingBinding(\.wordWrap))
                SwitchRow("Highlight current line", isOn: settingBinding(\.highlightCurrentLine))
            }
            .group("Indentation", description: "Defaults for newly opened files") {
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
            .group("Completion") {
                SwitchRow("Suggest words from the document", isOn: settingBinding(\.completionEnabled))
                SwitchRow("Include language keywords", isOn: settingBinding(\.completionKeywords))
            }
    }

    /// Appearance page: syntax themes and the editor background presets.
    func appearancePreferences(_ page: PreferencesDialog.PreferencesPage) -> PreferencesDialog.PreferencesPage {
        page
            .group("Syntax theme") {
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
            .group("Editor background") {
                ComboRow(
                    "Background",
                    selection: .init {
                        onMain { DocumentStore.shared.settings.editorBackground } ?? "theme"
                    } set: { value in
                        onMain { DocumentStore.shared.settings.editorBackground = value == "theme" ? nil : value }
                        chromeTick &+= 1
                    },
                    values: ["theme", "white", "sepia", "dark"].map { Choice(id: $0) }
                )
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
