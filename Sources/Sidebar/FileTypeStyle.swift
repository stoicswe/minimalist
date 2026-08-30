import SwiftUI
import MinimalistCore

/// Visual style for a file in the sidebar: a 1–3 character monogram
/// and a muted color that suggests the file's language/type.
///
/// The mapping itself lives in `MinimalistCore.FileTypeBadge` so the
/// Linux sidebar draws the same chips; this is just the SwiftUI face of
/// it.
struct FileTypeStyle {
    let letter: String
    let color: Color

    static let neutral = FileTypeStyle(badge: .neutral)

    static func style(for url: URL) -> FileTypeStyle {
        FileTypeStyle(badge: FileTypeBadge.badge(for: url))
    }

    private init(badge: FileTypeBadge) {
        self.letter = badge.letter
        self.color = Color(
            red: Double(badge.red) / 255,
            green: Double(badge.green) / 255,
            blue: Double(badge.blue) / 255
        )
    }
}
