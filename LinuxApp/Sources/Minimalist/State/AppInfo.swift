import CAdw
import Foundation

/// Who made {m.txt} and how to reach them — the Linux counterpart of the
/// macOS Preferences "About" tab. Everything a person might want to
/// change (the blurb, the handle, the links) lives here rather than
/// buried in view code.
///
/// The macOS tab's tip jar is a StoreKit purchase flow, which has no
/// Linux equivalent; the sponsor link takes its place.
enum AppInfo {

    static let id = "com.stoicswe.minimalist"
    static let name = "{m.txt}"
    static let developer = "Nathaniel Knudsen"
    static let handle = "@stoicswe"
    static let copyright = "© 2026 Nathaniel Knudsen"

    /// Kept in step with the macOS bundle's `CFBundleShortVersionString`.
    /// Snap builds stamp their own (git-described) version at build time,
    /// so prefer that when it's there.
    static var version: String {
        ProcessInfo.processInfo.environment["SNAP_VERSION"] ?? "1.0.1"
    }

    static let blurb = """
        {m.txt} is a passion project — a quiet, distraction-free code and \
        text editor. It grew out of wanting an editor that opens instantly, \
        stays out of the way, and treats your files as plain files: no \
        projects to configure, no lock-in, just you and the text.
        """

    static let projectURL = URL(string: "https://github.com/stoicswe/minimalist")
    /// The developer's GitHub profile — the Credits page links the name.
    static let profileURL = URL(string: "https://github.com/stoicswe")
    static let issuesURL = URL(string: "https://github.com/stoicswe/minimalist/issues")
    static let blueskyURL = URL(string: "https://bsky.app/profile/stoicswe.com")
    static let blueskyHandle = "@stoicswe.com"
    static let email = "contact@stoicswe.com"
    static var emailURL: URL? { URL(string: "mailto:\(email)") }

    /// Where the tip jar points on Linux: the project on GitHub, whose
    /// Sponsor button is wired up through `.github/FUNDING.yml`.
    static let sponsorURL = URL(string: "https://github.com/stoicswe/minimalist")

    /// The app's own icon when it's installed in an icon theme (the snap
    /// ships one), otherwise a stock editor icon so the About dialog
    /// never shows a broken image in a development run.
    static var iconName: String {
        let candidates = [id, "m-txt", "accessories-text-editor", "text-editor"]
        guard let display = gdk_display_get_default(),
              let theme = gtk_icon_theme_get_for_display(display)
        else { return candidates.last ?? "text-editor" }
        for candidate in candidates where gtk_icon_theme_has_icon(theme, candidate) != 0 {
            return candidate
        }
        return "text-editor-symbolic"
    }
}
