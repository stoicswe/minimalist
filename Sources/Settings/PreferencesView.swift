import SwiftUI
import AppKit
import StoreKit

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
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
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

// MARK: - About

/// Who made the app, and how to reach them. Everything a person might
/// want to change about the About tab lives here — the blurb, the
/// handle, the address — so none of it is buried in view code.
private enum DeveloperProfile {
    static let name = "Nathaniel Knudsen (@stoicswe)"
    static let role = "Developer"

    static let blurb = """
        Minimalist is a passion project — a quiet, distraction-free code and \
        text editor for the Mac. It grew out of wanting an editor that opens \
        instantly, stays out of the way, and treats your files as plain \
        files: no projects to configure, no lock-in, just you and the text.
        """

    static let blueskyHandle = "@stoicswe.com"
    static let blueskyURL = URL(string: "https://bsky.app/profile/stoicswe.com")

    static let email = "contact@stoicswe.com"
    static var emailURL: URL? { URL(string: "mailto:\(email)") }

    /// Portrait from the asset catalog; nil falls back to the enso mark.
    static var portrait: Image? {
        guard let image = NSImage(named: "DeveloperPortrait") else { return nil }
        return Image(nsImage: image)
    }
}

private struct AboutTab: View {
    @StateObject private var tipJar = TipJar()

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        portrait
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DeveloperProfile.name)
                                .font(.headline)
                            Text(DeveloperProfile.role)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(DeveloperProfile.blurb)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)

                contactRow(
                    label: "Bluesky",
                    value: DeveloperProfile.blueskyHandle,
                    systemImage: "at",
                    url: DeveloperProfile.blueskyURL
                )
                contactRow(
                    label: "Email",
                    value: DeveloperProfile.email,
                    systemImage: "envelope",
                    url: DeveloperProfile.emailURL
                )
            } header: {
                Text("About")
            }

            TipJarSection(tipJar: tipJar)

            Section {
            } footer: {
                Text(versionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .task { await tipJar.prepare() }
    }

    @ViewBuilder
    private var portrait: some View {
        Group {
            if let portrait = DeveloperProfile.portrait {
                portrait
                    .resizable()
                    .scaledToFill()
            } else {
                EnsoLogo(color: .secondary)
                    .padding(6)
            }
        }
        .frame(width: 64, height: 64)
        .background(Color.primary.opacity(0.05))
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func contactRow(
        label: String,
        value: String,
        systemImage: String,
        url: URL?
    ) -> some View {
        if let url {
            Link(destination: url) {
                rowBody(label: label, value: value, systemImage: systemImage)
            }
            .accessibilityLabel("\(label), \(value)")
        } else {
            rowBody(label: label, value: value, systemImage: systemImage)
        }
    }

    private func rowBody(label: String, value: String, systemImage: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// Read from the app bundle rather than hard-coded, so it can never
    /// drift from what actually shipped.
    private var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "Minimalist \(short) (\(build))"
    }
}

// MARK: - Tip jar

/// One tip size. The product IDs must match consumable in-app purchases
/// configured in App Store Connect (and in `Minimalist.storekit` for
/// local testing). `fallbackPrice` is only shown when the App Store
/// products can't be loaded — live builds show the store's localized
/// price.
private struct TipTier: Identifiable {
    let id: String
    let emoji: String
    let name: String
    let flavor: String
    let fallbackPrice: String

    static let all: [TipTier] = [
        TipTier(
            id: "com.stoicswe.minimalist.tip.small",
            emoji: "🫘",
            name: "Espresso Bean",
            flavor: "A little jolt of encouragement.",
            fallbackPrice: "$0.99"
        ),
        TipTier(
            id: "com.stoicswe.minimalist.tip.medium",
            emoji: "☕️",
            name: "Cup o' Joe",
            flavor: "Keeps the commits brewing.",
            fallbackPrice: "$4.99"
        ),
        TipTier(
            id: "com.stoicswe.minimalist.tip.large",
            emoji: "🥤",
            name: "Iced Shaken Cold Brew",
            flavor: "Fancy fuel for late-night features.",
            fallbackPrice: "$7.99"
        ),
    ]
}

/// StoreKit 2 wrapper for the tip tiers. Tips are consumables that grant
/// nothing — every purchase is finished immediately and answered with a
/// thank-you. When the store is unreachable (no network, or a build
/// distributed outside the Mac App Store), the tiers render disabled
/// with an explanatory footer instead of failing silently.
@MainActor
private final class TipJar: ObservableObject {
    enum Availability {
        case loading
        case ready
        case unavailable
    }

    @Published private(set) var availability: Availability = .loading
    @Published private(set) var products: [String: Product] = [:]
    /// Product ID of the purchase currently in flight, if any.
    @Published private(set) var purchasingID: String?
    @Published private(set) var thanked = false
    @Published private(set) var pendingApproval = false
    @Published private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    deinit {
        updatesTask?.cancel()
    }

    func prepare() async {
        // Finish any stray transactions (interrupted purchases, Ask to
        // Buy approvals landing later). Tips grant nothing, so finishing
        // — plus a thank-you — is all that's ever needed.
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await update in Transaction.updates {
                    guard case .verified(let transaction) = update else { continue }
                    await transaction.finish()
                    await MainActor.run {
                        self?.thanked = true
                        self?.pendingApproval = false
                    }
                }
            }
        }
        await loadProducts()
    }

    private func loadProducts() async {
        availability = .loading
        do {
            let loaded = try await Product.products(for: TipTier.all.map(\.id))
            guard !loaded.isEmpty else {
                availability = .unavailable
                return
            }
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            availability = .ready
        } catch {
            availability = .unavailable
        }
    }

    /// Localized price for a tier — the store's when loaded, the nominal
    /// USD fallback otherwise.
    func price(for tier: TipTier) -> String {
        products[tier.id]?.displayPrice ?? tier.fallbackPrice
    }

    func tip(_ tier: TipTier) async {
        guard purchasingID == nil, let product = products[tier.id] else { return }
        purchasingID = tier.id
        lastError = nil
        defer { purchasingID = nil }

        do {
            let result = try await purchase(product)
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                }
                thanked = true
                pendingApproval = false
            case .pending:
                pendingApproval = true
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = "The App Store couldn't complete the tip. Please try again later."
        }
    }

    private func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        // Anchor the App Store confirmation sheet to the Settings window
        // when we have one.
        if let window = NSApp.keyWindow {
            return try await product.purchase(confirmIn: window)
        }
        return try await product.purchase()
    }
}

private struct TipJarSection: View {
    @ObservedObject var tipJar: TipJar

    var body: some View {
        Section {
            if tipJar.thanked {
                HStack(spacing: 8) {
                    Text("🙏")
                    Text("Thank you for the coffee — it means a lot!")
                        .font(.callout)
                }
                .transition(.opacity)
            }

            ForEach(TipTier.all) { tier in
                tipRow(tier)
            }

            if tipJar.pendingApproval {
                Text("Your tip is awaiting approval — thanks in advance!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = tipJar.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Tip jar")
        } footer: {
            Text(footerText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .animation(.easeOut(duration: 0.2), value: tipJar.thanked)
    }

    private func tipRow(_ tier: TipTier) -> some View {
        HStack(spacing: 12) {
            Text(tier.emoji)
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text(tier.name)
                Text(tier.flavor)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button {
                Task { await tipJar.tip(tier) }
            } label: {
                if tipJar.purchasingID == tier.id {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 48)
                } else {
                    Text(tipJar.price(for: tier))
                        .frame(minWidth: 48)
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(tipJar.availability != .ready || tipJar.purchasingID != nil)
        }
        .padding(.vertical, 2)
    }

    private var footerText: String {
        switch tipJar.availability {
        case .ready, .loading:
            return "Tips are one-time thank-yous processed by the App Store. They don't unlock anything — every feature is already yours."
        case .unavailable:
            return "Tips are processed by the App Store and become available when Minimalist is installed from the Mac App Store."
        }
    }
}
