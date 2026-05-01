import SwiftUI
import Highlightr

/// Bottom-right status pill. Dispatches by document kind so each
/// viewer surface gets a contextually useful readout: the editor sees
/// language / indent / line endings, images / video / PDF / binary
/// each get their own metadata stats.
struct StatusPill: View {
    @EnvironmentObject var workspace: Workspace

    var body: some View {
        if let doc = workspace.activeDocument {
            switch doc.kind {
            case .text:   TextStatusPill(document: doc)
            case .image:  ImageMetadataPill(url: doc.url)
            case .video:  VideoMetadataPill(url: doc.url)
            case .pdf:    PDFMetadataPill(url: doc.url)
            case .binary: BinaryMetadataPill(url: doc.url)
            }
        }
    }
}

/// Original status pill — language + indent + line endings, with a
/// popover for editing the document's formatting in place.
private struct TextStatusPill: View {
    @ObservedObject var document: Document
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @State private var showOptions = false

    var body: some View {
        Button(action: { showOptions.toggle() }) {
            HStack(spacing: 10) {
                Text(document.language.uppercased())
                pillDivider
                Text(indentLabel(document.indentation))
                pillDivider
                Text(document.lineEnding.rawValue)
            }
            .modifier(PillTextStyle())
            .modifier(StatusPillSurface(useGlass: windowGlass))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showOptions, arrowEdge: .bottom) {
            FormatOptionsView(document: document)
        }
    }

    private func indentLabel(_ indent: Indentation) -> String {
        "\(indent.kind.label): \(indent.width)"
    }
}

private struct ImageMetadataPill: View {
    let url: URL
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @State private var meta: ImageMetadata?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { item in
                if item.element == pillDividerToken {
                    pillDivider
                } else {
                    Text(item.element)
                }
            }
        }
        .modifier(PillTextStyle())
        .modifier(StatusPillSurface(useGlass: windowGlass))
        .task(id: url) { meta = await MediaMetadataLoader.image(at: url) }
    }

    private var segments: [String] {
        guard let meta else { return ["Loading…"] }
        var parts: [String] = []
        if let fmt = meta.format { parts.append(fmt) }
        if let s = meta.pixelSize {
            parts.append("\(Int(s.width))×\(Int(s.height))")
        }
        if let depth = meta.bitDepth {
            var label = "\(depth)-bit"
            if meta.hasAlpha == true { label += "·α" }
            parts.append(label)
        }
        if let bytes = meta.fileSize {
            parts.append(MediaMetadataLoader.formatBytes(bytes))
        }
        return interleave(parts)
    }
}

private struct VideoMetadataPill: View {
    let url: URL
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @State private var meta: VideoMetadata?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { item in
                if item.element == pillDividerToken {
                    pillDivider
                } else {
                    Text(item.element)
                }
            }
        }
        .modifier(PillTextStyle())
        .modifier(StatusPillSurface(useGlass: windowGlass))
        .task(id: url) { meta = await MediaMetadataLoader.video(at: url) }
    }

    private var segments: [String] {
        guard let meta else { return ["Loading…"] }
        var parts: [String] = []
        if let codec = meta.codec { parts.append(codec.uppercased()) }
        if let s = meta.resolution {
            parts.append("\(Int(s.width))×\(Int(s.height))")
        }
        if let fps = meta.frameRate {
            // Trim trailing .0 on whole-frame rates (24, 30, 60) — they
            // read better than `24.00 fps`.
            let rounded = (fps.rounded() == fps)
                ? String(format: "%.0f", fps)
                : String(format: "%.2f", fps)
            parts.append("\(rounded) fps")
        }
        if let dur = meta.durationSeconds {
            parts.append(MediaMetadataLoader.formatDuration(dur))
        }
        if let bytes = meta.fileSize {
            parts.append(MediaMetadataLoader.formatBytes(bytes))
        }
        return interleave(parts)
    }
}

private struct PDFMetadataPill: View {
    let url: URL
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @State private var meta: PDFMetadata?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { item in
                if item.element == pillDividerToken {
                    pillDivider
                } else {
                    Text(item.element)
                }
            }
        }
        .modifier(PillTextStyle())
        .modifier(StatusPillSurface(useGlass: windowGlass))
        .task(id: url) { meta = await MediaMetadataLoader.pdf(at: url) }
    }

    private var segments: [String] {
        guard let meta else { return ["Loading…"] }
        var parts: [String] = ["PDF"]
        if let count = meta.pageCount {
            parts.append("\(count) page\(count == 1 ? "" : "s")")
        }
        if let s = meta.pageSize {
            parts.append("\(Int(s.width.rounded()))×\(Int(s.height.rounded())) pt")
        }
        if let bytes = meta.fileSize {
            parts.append(MediaMetadataLoader.formatBytes(bytes))
        }
        return interleave(parts)
    }
}

private struct BinaryMetadataPill: View {
    let url: URL
    @AppStorage(PreferenceKeys.windowGlass) private var windowGlass: Bool = false
    @State private var meta: BinaryMetadata?

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { item in
                if item.element == pillDividerToken {
                    pillDivider
                } else {
                    Text(item.element)
                }
            }
        }
        .modifier(PillTextStyle())
        .modifier(StatusPillSurface(useGlass: windowGlass))
        .task(id: url) { meta = await MediaMetadataLoader.binary(at: url) }
    }

    private var segments: [String] {
        guard let meta else { return ["Loading…"] }
        var parts: [String] = []
        if let type = meta.typeDescription {
            parts.append(type)
        }
        parts.append(MediaMetadataLoader.formatBytes(meta.fileSize))
        if let header = meta.magicHeader {
            parts.append(header)
        }
        return interleave(parts)
    }
}

// MARK: - Shared pill bits

/// Sentinel string used inside the pill segments array to mark where a
/// vertical divider should render. Picked to be a value no metadata
/// loader could ever produce.
private let pillDividerToken = "\u{2502}"

/// Slot a divider between every pair of values so the pill reads as
/// distinct chunks instead of a run-on string.
private func interleave(_ parts: [String]) -> [String] {
    var result: [String] = []
    for (idx, part) in parts.enumerated() {
        if idx > 0 { result.append(pillDividerToken) }
        result.append(part)
    }
    return result
}

private var pillDivider: some View {
    Capsule().fill(.secondary.opacity(0.4)).frame(width: 1, height: 10)
}

private struct PillTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
    }
}

private struct FormatOptionsView: View {
    @ObservedObject var document: Document

    @AppStorage("default.indent.kind") private var defaultKind: String = Indentation.Kind.spaces.rawValue
    @AppStorage("default.indent.width") private var defaultWidth: Int = 4
    @AppStorage("default.lineEnding") private var defaultEOL: String = LineEnding.lf.rawValue

    @State private var workingKind: Indentation.Kind = .spaces
    @State private var workingWidth: Int = 4
    @State private var workingEOL: LineEnding = .lf

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("File format")
                .font(.system(size: 13, weight: .semibold))

            HStack {
                Text("Language")
                Spacer()
                Picker("", selection: $document.language) {
                    ForEach(SupportedLanguages.all, id: \.id) { lang in
                        Text(lang.label).tag(lang.id)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("Indentation", selection: $workingKind) {
                    ForEach(Indentation.Kind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 6) {
                    Text("Width")
                    Spacer()
                    Text("\(workingWidth)")
                        .font(.system(.body, design: .monospaced))
                        .frame(minWidth: 18, alignment: .trailing)
                    Stepper("", value: $workingWidth, in: 1...8)
                        .labelsHidden()
                }

                Picker("Line endings", selection: $workingEOL) {
                    ForEach(LineEnding.allCases) { eol in
                        Text(eol.rawValue).tag(eol)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()

            HStack(spacing: 8) {
                Button("Reformat document") {
                    document.reformat(
                        eol: workingEOL,
                        indentation: Indentation(kind: workingKind, width: workingWidth)
                    )
                }
                .buttonStyle(.borderedProminent)

                Button("Apply") {
                    document.indentation = Indentation(kind: workingKind, width: workingWidth)
                    document.lineEnding = workingEOL
                }
            }

            Divider()

            Button("Save as defaults for new files") {
                defaultKind = workingKind.rawValue
                defaultWidth = workingWidth
                defaultEOL = workingEOL.rawValue
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            workingKind = document.indentation.kind
            workingWidth = document.indentation.width
            workingEOL = document.lineEnding
        }
    }
}

/// Cached, sorted list of Highlightr-supported languages plus a plaintext entry.
enum SupportedLanguages {
    struct Entry: Hashable {
        let id: String
        let label: String
    }

    static let all: [Entry] = {
        var entries: [Entry] = [Entry(id: "plaintext", label: "Plain Text")]
        let langs = (Highlightr()?.supportedLanguages() ?? []).sorted()
        entries.append(contentsOf: langs.map { Entry(id: $0, label: prettyLabel(for: $0)) })
        return entries
    }()

    private static func prettyLabel(for raw: String) -> String {
        switch raw {
        case "javascript": return "JavaScript"
        case "typescript": return "TypeScript"
        case "objectivec": return "Objective-C"
        case "objectivec_plain": return "Objective-C"
        case "cpp": return "C++"
        case "csharp": return "C#"
        case "json": return "JSON"
        case "yaml": return "YAML"
        case "xml": return "XML"
        case "css": return "CSS"
        case "scss": return "SCSS"
        case "html": return "HTML"
        case "sql": return "SQL"
        default: return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}

/// Pill surface — picks Liquid Glass refraction (Glass on) or
/// `.ultraThinMaterial` (Glass off). Both keep the same hairline border
/// + drop shadow shape so the pill silhouette doesn't shift between
/// modes; glass uses a lighter shadow since refraction already implies
/// depth.
struct StatusPillSurface: ViewModifier {
    let useGlass: Bool

    func body(content: Content) -> some View {
        if useGlass {
            content
                .glassEffect(.regular, in: .capsule)
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
    }
}
