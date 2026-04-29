import SwiftUI
import AppKit

/// One named entry in the accent-color picker. Names lean on Japanese
/// aesthetic concepts and a few stoic terms — the through-line is
/// "quiet, grounded, considered."
struct AccentPreset: Identifiable, Hashable {
    let id: String
    let displayName: String
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1.0)
    }
}

enum AccentPresets {
    static let all: [AccentPreset] = [
        // Matcha — powdered tea green; the original example.
        AccentPreset(id: "matcha",     displayName: "Matcha",     red: 0.55, green: 0.72, blue: 0.42),
        // Sakura — cherry blossom; a quiet pink.
        AccentPreset(id: "sakura",     displayName: "Sakura",     red: 0.91, green: 0.65, blue: 0.71),
        // Ai — traditional indigo dye.
        AccentPreset(id: "ai",         displayName: "Ai",         red: 0.36, green: 0.49, blue: 0.65),
        // Kintsugi — the lacquered-gold mend of broken pottery.
        AccentPreset(id: "kintsugi",   displayName: "Kintsugi",   red: 0.83, green: 0.63, blue: 0.33),
        // Hinoki — Japanese cypress; warm wood tone.
        AccentPreset(id: "hinoki",     displayName: "Hinoki",     red: 0.79, green: 0.57, blue: 0.37),
        // Yūgen — depth and mystery; a twilight purple.
        AccentPreset(id: "yugen",      displayName: "Yūgen",      red: 0.48, green: 0.42, blue: 0.58),
        // Shibui — restrained, refined astringent beauty; muted teal.
        AccentPreset(id: "shibui",     displayName: "Shibui",     red: 0.43, green: 0.64, blue: 0.59),
        // Sumi — calligraphy-ink charcoal.
        AccentPreset(id: "sumi",       displayName: "Sumi",       red: 0.30, green: 0.32, blue: 0.36),
        // Ataraxia — Stoic tranquility; a pale dusk blue.
        AccentPreset(id: "ataraxia",   displayName: "Ataraxia",   red: 0.50, green: 0.62, blue: 0.72),
    ]

    static let defaultID = "matcha"

    static func preset(forID id: String) -> AccentPreset {
        all.first { $0.id == id } ?? all[0]
    }

    /// Read the user's currently-selected accent preset from UserDefaults.
    /// Lives outside SwiftUI so AppKit code paths (NSTextView, custom
    /// drawing) can resolve the color without an `@AppStorage`.
    static var current: AccentPreset {
        let id = UserDefaults.standard.string(forKey: PreferenceKeys.accentPresetID) ?? defaultID
        return preset(forID: id)
    }
}
